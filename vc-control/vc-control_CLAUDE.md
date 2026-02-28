# vc-control — Claude Code 指示書

## 概要

Python 3.11 製の WebSocket サーバ。Rust サーバ（Oxide Plugin）から座標を受信し、
差分抽出して接続中の VCアプリ全クライアントへブロードキャストする。
音量計算・距離計算は一切行わない。

## 技術スタック

| 項目 | 採用 | バージョン |
|------|------|----------|
| 言語 | Python | 3.11 |
| フレームワーク | FastAPI | 最新安定版 |
| WebSocket | websockets | 12.x |
| バリデーション | Pydantic v2 | 最新安定版 |
| コンテナ | Docker | python:3.11-slim |
| テスト | pytest + pytest-asyncio | 最新安定版 |

## ディレクトリ構成

```
vc-control/
├── CLAUDE.md
├── Dockerfile
├── requirements.txt
├── main.py              # uvicorn エントリポイント
├── config.py            # 環境変数読み込み（Pydantic Settings）
├── auth.py              # HMAC検証・セッション管理
├── state.py             # PlayerState・ServerState データクラス
├── delta.py             # 差分抽出・閾値フィルタ
├── broadcaster.py       # WS接続管理・ブロードキャスト
├── handlers/
│   ├── __init__.py
│   ├── oxide.py         # ws://localhost:8765/oxide
│   └── client.py        # wss://HOST:8766/client
└── tests/
    ├── test_delta.py
    ├── test_auth.py
    └── test_broadcaster.py
```

## 環境変数（config.py で定義）

| 変数 | 型 | デフォルト | 必須 | 説明 |
|------|----|----------|------|------|
| `OXIDE_TOKEN` | str | - | ✅ | Oxide接続認証トークン |
| `SHARED_SECRET` | str | - | ✅ | プレイヤートークンHMAC鍵 |
| `OXIDE_PORT` | int | 8765 | - | Oxide接続ポート |
| `CLIENT_PORT` | int | 8766 | - | クライアント接続ポート |
| `SESSION_TTL` | int | 14400 | - | セッション有効秒 |
| `STATE_TIMEOUT` | float | 5.0 | - | プレイヤー情報失効秒 |
| `POS_THRESHOLD` | float | 0.1 | - | 座標変化閾値(m) |
| `ANGLE_THRESHOLD` | float | 1.0 | - | 角度変化閾値(度) |
| `SSL_CERT` | str | - | ✅ | TLS証明書パス |
| `SSL_KEY` | str | - | ✅ | TLS秘密鍵パス |
| `DEBUG` | bool | false | - | デバッグログ有効化 |

## データモデル（state.py）

```python
@dataclass
class Vec3:
    x: float
    y: float
    z: float

@dataclass
class Rot2:
    yaw: float    # 水平方向角度(度, 0=北, 右回り)
    pitch: float  # 仰俯角(度, 上が正)

@dataclass
class PlayerState:
    steam_id: str
    pos: Vec3
    rot: Rot2
    alive: bool
    team_id: int | None
    last_updated: float  # unix time
    # Phase3追加予定フィールド:
    # radio_channel: int | None
    # radio_transmitting: bool

@dataclass
class ServerState:
    players: dict[str, PlayerState]       # steam_id → PlayerState
    prev_players: dict[str, PlayerState]  # 差分比較用（前フレーム）
    last_frame_tick: int

@dataclass
class ClientSession:
    session_id: str
    steam_id: str
    ws: WebSocket
    connected_at: float
    initialized: bool  # state_full 送信済みフラグ
```

## 差分抽出ロジック（delta.py）

閾値を下回る変化はスキップする。alive/team_id は閾値なしで即時送信。

```python
# 閾値（環境変数で上書き可能）
POS_THRESHOLD   = float(os.getenv("POS_THRESHOLD",   "0.1"))  # m
ANGLE_THRESHOLD = float(os.getenv("ANGLE_THRESHOLD", "1.0"))  # 度

def is_changed(prev: PlayerState, curr: PlayerState) -> bool: ...
def extract_delta(prev, curr) -> tuple[list[PlayerState], list[str]]: ...
# Returns: (changed_players, removed_steam_ids)
```

## WebSocket メッセージ仕様

設計書 §3 通信仕様書を参照。ここでは実装上の注意点のみ記載。

### Oxide → Server (`/oxide`)
- `Authorization: Bearer {OXIDE_TOKEN}` ヘッダで認証
- 認証失敗時は即座に WS を閉じる（コード 4001）
- 受信した frame は必ず prev_players と比較して差分のみ broadcast する
- `changed` も `removed` も空の場合は **broadcast しない**（帯域節約）

### Server → クライアント
- `state_full`: `auth_ack` 直後に1回だけ送信。その後は送らない
- `state_delta`: JSON は1回生成して全クライアントに同一 payload を送る
- `asyncio.gather(*tasks, return_exceptions=True)` で並列送信。例外は無視してログ出力

### クライアント認証
- `auth` メッセージ受信後、HMAC-SHA256 で検証
- タイムスタンプ有効期限: ±5分
- 使用済みトークンはメモリキャッシュ（TTL=10分）で管理
- 認証成功後に `auth_ack` → `state_full` の順で送信

## ブロードキャスト処理（broadcaster.py）

```python
# JSON生成は1回のみ。全クライアントに同一payloadを並列送信する
async def broadcast_delta(changed, removed, tick, ts):
    if not changed and not removed:
        return  # 送信なし
    payload = json.dumps({...})
    tasks = [s.ws.send(payload) for s in sessions.values() if s.initialized]
    await asyncio.gather(*tasks, return_exceptions=True)
```

## ヘルスチェック

`GET /health` → `{"status": "ok", "clients": N, "tick": N}` を返す

Dockerの `HEALTHCHECK` はこのエンドポイントを使う。

## テスト方針

- `delta.py` は純粋関数のため単体テストを必ず書く
- `auth.py` のHMAC検証・有効期限チェックは単体テストを書く
- `broadcaster.py` は asyncio のモックで統合テストを書く
- WebSocket の E2E テストは `pytest-asyncio` + `websockets` クライアントで行う

## Phase0 でやること

1. `Dockerfile` と `requirements.txt` を作成して `docker build` が通ること
2. `main.py` に `/health` エンドポイントのみ実装して `docker compose up` で起動確認
3. `/oxide` エンドポイントに WS 接続できること（認証は後回しでよい）
4. 受信した JSON をログ出力するだけの最小実装

## Phase1 でやること

1. `state.py` / `delta.py` 実装（単体テスト付き）
2. `broadcaster.py` 実装
3. `/client` エンドポイントに `state_full` / `state_delta` 送信
4. 認証は SteamID の形式チェックのみ（HMAC は Phase2）

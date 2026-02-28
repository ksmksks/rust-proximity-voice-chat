# RustProximityVoiceChat (RustPVC) 設計文書

**プロジェクト正式名称**: RustProximityVoiceChat  
**略称**: RustPVC  
**バージョン**: 1.3.0-design  
**作成日**: 2026-02-27  
**更新日**: 2026-02-27  
**ステータス**: 設計確定版  
**変更点 v1.1**: 7.4 UIレイアウト改訂 / 11.3 チーム通話方式変更 / 11.4 OBS節削除
**変更点 v1.2**: 1.2 OBS/VirtualCable削除 / 7.4 絵文字Muteボタン・お気に入り追加 / 11.1 無線PTT詳細化 / 11.3 チャンネルリスナー調査結果反映  
**変更点 v1.3**: 11.1 無線PTTをRustキーバインド方式に変更 / 11.3 チーム通話確定（ChannelListener fork+VoiceTarget）/ 11.4 電話統合を新規追加 / ロードマップ更新

---

## 目次

1. [システム全体アーキテクチャ設計書](#1-システム全体アーキテクチャ設計書)
2. [データフロー設計書](#2-データフロー設計書)
3. [通信仕様書](#3-通信仕様書)
4. [認証設計書](#4-認証設計書)
5. [Mumbleサーバ設定設計書](#5-mumbleサーバ設定設計書)
6. [VC Controlサーバ設計書](#6-vc-controlサーバ設計書)
7. [外部VCアプリ設計書](#7-外部vcアプリ設計書)
8. [距離減衰アルゴリズム設計書](#8-距離減衰アルゴリズム設計書)
9. [指向性アルゴリズム設計書](#9-指向性アルゴリズム設計書)
10. [負荷見積もり設計書](#10-負荷見積もり設計書)
11. [将来拡張設計](#11-将来拡張設計)
12. [セキュリティ設計書](#12-セキュリティ設計書)
13. [フェーズ分割ロードマップ](#13-フェーズ分割ロードマップ)
14. [プロジェクト構成・Docker設計書](#14-プロジェクト構成docker設計書)

---

# 1. システム全体アーキテクチャ設計書

## 1.1 設計方針

| 優先度 | 方針 |
|--------|------|
| 最高 | EAC互換・Steam規約準拠 |
| 最高 | クライアント無改造 |
| 高 | 拡張性（ゾーン・無線・録音） |
| 高 | 低遅延（目標 < 150ms E2E） |
| 高 | 同一VM運用での帯域最小化 |
| 中 | 運用コスト最小化 |

## 1.2 コンポーネント全体図

```
┌─────────────────────────────────────────────────────────────┐
│                     Rust Game Server (VM)                    │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Oxide/uMod Plugin: RustProximityVoiceChat (RustPVC) │   │
│  │  - Player position (x,y,z)                           │   │
│  │  - Eye direction (yaw,pitch)                         │   │
│  │  - Alive/Dead state                                  │   │
│  │  - TeamID                                            │   │
│  │  - SteamID                                           │   │
│  │  → WebSocket 20Hz → VC Control Server                │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Docker Compose                                       │  │
│  │  ┌─────────────────────┐  ┌───────────────────────┐  │  │
│  │  │  vc-control         │  │  mumble               │  │  │
│  │  │  Python 3.11        │  │  mumble/mumble-server │  │  │
│  │  │  FastAPI + WS       │  │  Opus 40kbps          │  │  │
│  │  │  :8765 (oxide)      │  │  :64738               │  │  │
│  │  │  :8766 (client)     │  │                       │  │  │
│  │  └─────────────────────┘  └───────────────────────┘  │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
         │ wss://  (8766)                  │ Mumble TLS (64738)
         ▼                                 ▼
┌─────────────────────────────────────────────────────────────┐
│              外部VCアプリ: RustPVC.exe (C# / WPF)           │
│  - WebSocket接続 (座標受信)                                   │
│  - Mumble接続 (音声送受信)                                    │
│  - 距離減衰計算 / 指向性計算                                   │
│  - 個別音量UI                                                 │
└─────────────────────────────────────────────────────────────┘
```

## 1.3 コンポーネント責務マトリクス

| 責務 | Oxide Plugin | VC Control | 外部VCアプリ | Mumble |
|------|:---:|:---:|:---:|:---:|
| 座標取得 | ✅ | - | - | - |
| 差分抽出 | ❌ | ✅ | - | - |
| 距離計算 | ❌ | ❌ | ✅ | ❌ |
| 音声中継 | ❌ | ❌ | - | ✅ |
| 音量制御 | ❌ | ❌ | ✅ | (受動) |
| 認証生成 | ✅ | 検証 | 提示 | - |
| UI | - | - | ✅ | - |
| Docker管理 | - | ✅ | - | ✅ |

## 1.4 外部依存関係

| コンポーネント | 技術 | バージョン |
|--------------|------|-----------|
| Oxide/uMod Plugin | C# (.NET Framework 4.x) | 最新安定版 |
| VC Control Server | Python 3.11 / FastAPI + websockets | 3.11-slim |
| 外部VCアプリ | C# .NET 8 / WPF | .NET 8 LTS |
| Mumble Server | mumble/mumble-server (Docker公式) | 1.5.x |
| コンテナ管理 | Docker Compose v2 | 2.x |

## 1.5 ネットワークポート一覧

| ポート | プロトコル | 用途 | 公開範囲 |
|--------|-----------|------|---------|
| 8765 | TCP/WS | VC Control (Oxide→Server) | localhost のみ |
| 8766 | TCP/WSS | VC Control (VCアプリ→Server) | 外部公開 |
| 64738 | TCP+UDP | Mumble | 外部公開 |
| 28015 | UDP/TCP | Rust Game | 外部公開 (変更不可) |
| 28016 | TCP | Rust RCON | 管理用のみ |

---

# 2. データフロー設計書

## 2.1 フロー A: 座標データ

```
[Rust Server 50ms tick]
    │
    ▼
Oxide Plugin (RustPVC)
    ├─ GetAllPlayers()
    ├─ player.transform.position  → Vec3
    ├─ player.eyes.rotation       → Quaternion → Euler
    ├─ player.IsAlive()           → bool
    └─ player.currentTeam?.teamID → ulong?
    │
    ▼ JSON 全プレイヤー分 (50人 × 80bytes ≒ 4KB)
WebSocket送信 (20Hz, localhost:8765)
    │
    ▼
VC Control Server (Docker: vc-control)
    ├─ 受信・パース
    ├─ 前フレームと差分比較
    │    座標差 < 0.1m かつ 角度差 < 1.0度 → スキップ
    │    alive / team_id 変化 → 必ず含める
    ├─ changed / removed を抽出
    ├─ changed空 かつ removed空 → 送信なし
    └─ 変化ありのみ state_delta としてブロードキャスト
         └─ 新規接続クライアント → state_full を送信
    │
    ▼ WSS (外部ネットワーク)
各VCアプリ (RustPVC.exe)
    ├─ state_full  → ローカル状態を全置換
    ├─ state_delta → ローカル状態にマージ
    ├─ removed     → 該当プレイヤーを削除
    ├─ last_updated記録 → 5秒無更新で自動削除
    ├─ 距離減衰計算
    ├─ 指向性(パン)計算
    └─ Mumble API で Volume/Pan 設定
```

## 2.2 フロー B: 音声データ

```
マイク入力
    │
    ▼
外部VCアプリ (Mumble クライアント機能)
    │ Opus encode (20ms / 40kbps)
    ▼
Mumble Server (Docker: mumble)
    │ 同チャンネル全員へ中継 (音量は変更しない)
    ▼
外部VCアプリ (各自のアプリ)
    │ 受信 → MumbleSharp Volume/Pan API
    ▼
スピーカー出力 (距離減衰・指向性適用済み)

```

## 2.3 フロー C: 認証フロー

```
プレイヤー → /vctoken コマンド
    │
    ▼ チャット表示: "Your RustPVC token: xxxx"
    │
外部VCアプリ起動
    ├─ SteamID + token 入力
    └─ VC Control Server へ auth 送信
    │
    ▼
VC Control Server
    ├─ HMAC-SHA256 検証
    ├─ timestamp 有効期限確認 (±5分)
    ├─ 使用済みトークン確認
    └─ セッション発行 → auth_ack + state_full
    │
    ▼
Mumble Server
    └─ username = SteamID64 で接続
```

## 2.4 タイミング図

```
t=0ms   Oxide 座標取得
t=5ms   JSON シリアライズ
t=10ms  VC Control 受信
t=11ms  差分抽出 (閾値フィルタ)
t=12ms  state_delta ブロードキャスト完了
t=15ms  VCアプリ マージ + 減衰計算
t=20ms  Mumble 音量反映
t=20ms  次フレーム開始
```

目標 E2E レイテンシ: 音声 < 80ms / 座標反映 < 30ms

## 2.5 差分送信による帯域削減

| 状態 | full毎回 | 差分送信 | 削減率 |
|------|---------|---------|--------|
| 全員移動中 | 4 MB/s | 3.2 MB/s | 20% |
| 半数静止 | 4 MB/s | 1.2 MB/s | 70% |
| 大半AFK/建築中 | 4 MB/s | 0.4 MB/s | 90% |
| **平均想定** | **4 MB/s** | **~1.5 MB/s** | **~60%** |

Rustは建築・農作業など静止シーンが多く、実測では70%+の削減が見込める。

## 2.6 状態整合性保証の3メカニズム

```
1. state_full (新規接続時1回)
   → ローカル状態を確実に初期化

2. removed イベント (離脱検出時即時)
   → プレイヤーをリストから確実に削除

3. last_updated タイムアウト (5秒)
   → WS一時切断・パケットロス等の取りこぼしをカバー
```

---

# 3. 通信仕様書

## 3.1 エンドポイント

| エンドポイント | 方向 | 説明 |
|--------------|------|------|
| `ws://localhost:8765/oxide` | Oxide→Server | 座標送信専用 (localhost限定) |
| `wss://HOST:8766/client` | VCアプリ↔Server | クライアント双方向 (TLS必須) |

## 3.2 メッセージ一覧

| type | 方向 | 頻度 | 説明 |
|------|------|------|------|
| `frame` | Oxide→Server | 20Hz | 全プレイヤー座標 |
| `auth` | VCアプリ→Server | 1回 | 認証要求 |
| `auth_ack` | Server→VCアプリ | 1回 | 認証応答 |
| `state_full` | Server→VCアプリ | 接続時1回 | 全プレイヤー状態 |
| `state_delta` | Server→VCアプリ | 20Hz (変化時のみ) | 差分状態 |
| `error` | Server→VCアプリ | 随時 | エラー通知 |
| `volume_override` | VCアプリ→Server | 随時 | 個別音量設定(将来) |

## 3.3 Oxide → VC Control: frame

```json
{
  "type": "frame",
  "server_id": "rust-main-01",
  "tick": 1234567,
  "timestamp_ms": 1700000000000,
  "players": [
    {
      "steam_id": "76561198000000001",
      "name": "PlayerName",
      "pos": { "x": 123.45, "y": 10.0, "z": -456.78 },
      "rot": { "yaw": 180.5, "pitch": -5.2 },
      "alive": true,
      "team_id": 42
    }
  ]
}
```

| フィールド | 型 | 説明 |
|-----------|-----|------|
| `server_id` | string | サーバ識別子 |
| `tick` | int | Rustサーバtick番号 |
| `timestamp_ms` | int64 | Unix時刻ms |
| `players[].pos` | object | ワールド座標(m) |
| `players[].rot.yaw` | float | 水平方向角度(度, 0=北, 右回り) |
| `players[].rot.pitch` | float | 仰俯角(度, 上が正) |
| `players[].team_id` | int or null | チームID |

## 3.4 Server → VCアプリ: state_full

```json
{
  "type": "state_full",
  "tick": 1234567,
  "timestamp_ms": 1700000000000,
  "players": [
    {
      "steam_id": "76561198000000001",
      "pos": { "x": 123.45, "y": 10.0, "z": -456.78 },
      "rot": { "yaw": 180.5, "pitch": -5.2 },
      "alive": true,
      "team_id": 42
    }
  ]
}
```

送信タイミング: `auth_ack` 直後1回のみ。

## 3.5 Server → VCアプリ: state_delta

```json
{
  "type": "state_delta",
  "tick": 1234568,
  "timestamp_ms": 1700000000050,
  "changed": [
    {
      "steam_id": "76561198000000001",
      "pos": { "x": 124.10, "y": 10.0, "z": -456.78 },
      "rot": { "yaw": 182.0, "pitch": -5.2 },
      "alive": true,
      "team_id": 42
    }
  ],
  "removed": [
    "76561198000000003"
  ]
}
```

- `changed`: 閾値を超えて変化したプレイヤー（全フィールドを含む）
- `removed`: 離脱したプレイヤーのSteamID64リスト
- `changed` 空 かつ `removed` 空の場合、フレーム送信なし

## 3.6 VCアプリ → Server: auth / auth_ack

```json
// 送信
{
  "type": "auth",
  "steam_id": "76561198000000001",
  "token": "<HMAC-SHA256 Base64URL>"
}

// 応答
{
  "type": "auth_ack",
  "success": true,
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "error": null
}
```

## 3.7 エラーメッセージ

```json
{
  "type": "error",
  "code": "AUTH_FAILED",
  "message": "Invalid token"
}
```

| コード | 説明 |
|--------|------|
| `AUTH_FAILED` | 認証失敗 |
| `TOKEN_EXPIRED` | トークン有効期限切れ |
| `TOKEN_USED` | トークン使用済み |
| `RATE_LIMIT` | 送信過多 |
| `INVALID_FORMAT` | JSONパースエラー |
| `SESSION_EXPIRED` | セッション期限切れ |

## 3.8 差分送信の閾値フィルタ仕様

```
is_changed(prev, curr):
  if prev.alive != curr.alive         → True (閾値なし)
  if prev.team_id != curr.team_id     → True (閾値なし)
  dist = |curr.pos - prev.pos|
  if dist >= 0.1m                     → True
  yaw_diff = |curr.yaw - prev.yaw| (ラップアラウンド考慮)
  if yaw_diff >= 1.0度                → True
  if |curr.pitch - prev.pitch| >= 1.0度 → True
  else                                → False (送信スキップ)
```

| パラメータ | 閾値 | 根拠 |
|-----------|------|------|
| 座標 | 0.1m | 静止判定として妥当。近距離音量変化に十分な精度 |
| 角度 | 1.0度 | パン変化1.7%は知覚閾値以下 |
| alive/team | なし | 音声制御上クリティカルなため即時送信 |

## 3.9 VCアプリ側ローカル状態管理

```
state_full 受信  → local_players を全置換
state_delta 受信 → changed をマージ、removed を削除
毎秒チェック     → last_updated から5秒超で自動削除
```

## 3.10 接続シーケンス

```
VCアプリ          VC Control Server
  │                      │
  ├── WS Connect ───────►│
  ├── auth ──────────────►│
  │◄── auth_ack ──────────┤
  │◄── state_full ────────┤  ← 接続直後に1回
  │                      │
  │◄── state_delta ───────┤  ← 変化ありフレームのみ (20Hz)
  │◄── state_delta ───────┤
  │        ...            │
  ├── WS Close ──────────►│
```

---

# 4. 認証設計書

## 4.1 認証方式

EAC/Steam規約に抵触しない外部トークン方式。  
HMAC-SHA256 でSteamIDの正当性を検証する。

## 4.2 認証フロー

```
[Oxide Plugin (RustPVC)]
  1. プレイヤーが /vctoken コマンド実行
  2. SteamID64 + Unix timestamp で HMAC-SHA256 生成
     input  = "{steam_id}:{timestamp_unix}"
     token  = Base64URL(HMAC-SHA256(shared_secret, input))
  3. チャット欄にトークン表示

[外部VCアプリ (RustPVC.exe)]
  4. ユーザが SteamID + token を入力 (初回のみ、設定保存可)
  5. VC Control Server へ auth 送信

[VC Control Server]
  6. 同一 shared_secret で HMAC 再生成 → 比較
  7. timestamp 有効期限確認 (±5分)
  8. 使用済みトークン確認 (メモリキャッシュ TTL=10分)
  9. 成功 → session_id (UUIDv4) 発行 → auth_ack → state_full
```

## 4.3 トークン仕様

| 項目 | 値 |
|------|-----|
| アルゴリズム | HMAC-SHA256 |
| 入力 | `{steam_id}:{timestamp_unix}` |
| 出力形式 | Base64URL (43文字) |
| 有効期限 | 発行から5分 |
| 再利用 | 不可 |

## 4.4 セッション管理

| 項目 | 値 |
|------|-----|
| session_id | UUIDv4 |
| 有効期限 | 4時間 |
| 保存場所 | メモリ (将来: Redis) |
| 切断時 | セッション削除 |

## 4.5 Mumble 接続との紐付け

```
Mumble username = SteamID64 文字列
Mumble password = (初期実装: 空 / 将来: session_id で検証)
VCアプリが両接続を管理し、SteamID で音量ターゲットを識別
```

## 4.6 脅威モデルと対策

| 脅威 | 対策 |
|------|------|
| SteamIDなりすまし | HMAC + shared_secret |
| トークン盗用 | 短期TTL (5分) + 使い捨て |
| リプレイ攻撃 | 使用済みトークン記録 |
| 総当たり | HMAC256bit強度 |
| セッション盗用 | TLS (wss://) 必須 |

---

# 5. Mumbleサーバ設定設計書

## 5.1 Docker起動方式

Mumble Server は `mumble/mumble-server` 公式Dockerイメージを使用。  
設定は `murmur.ini` をホスト側でマウントして管理する。

```
docker/mumble/
├── murmur.ini      # サーバ設定
└── Dockerfile      # 公式イメージ + カスタム設定
```

## 5.2 murmur.ini 設計

```ini
# ネットワーク
host=0.0.0.0
port=64738

# 音質・遅延
bandwidth=40000          # 40kbps (Opus最適)
opusthreshold=0          # 全クライアントOpus強制

# 接続数
users=60                 # 最大60 (50+余裕)
usersperchannel=60

# セキュリティ
serverpassword=           # 空 (アプリ側で制御)
sslCert=/etc/mumble-server/ssl/server.crt
sslKey=/etc/mumble-server/ssl/server.key
allowhtml=false
sendversion=false

# 低遅延チューニング
timeout=30
textmessagelength=0      # テキスト無効
imagemessagelength=0     # 画像無効

# ログ
loglevel=1               # Warning以上のみ

# ICE (将来: 外部チャンネル制御用)
# ice="tcp -h 127.0.0.1 -p 6502"
```

## 5.3 Opusパラメータ

| パラメータ | 値 | 理由 |
|-----------|-----|------|
| フレームサイズ | 20ms | 遅延・品質バランス |
| ビットレート | 32~40kbps | 50人 × 5KB/s = 250KB/s |
| サンプルレート | 48000Hz | Mumble標準 |
| チャンネル | モノラル | ゲーム音声として十分 |
| FEC | 有効 | パケットロス対策 |
| DTX | 有効 | 無音時帯域節約 |

## 5.4 チャンネル構成（初期）

```
Root
└── RustPVC-Main (全員ここ)
    ├── [Phase3] Zone-SafeZone
    ├── [Phase3] Zone-RadTown
    └── [Phase3] TeamOnly-{TeamID}
```

## 5.5 ホストOS チューニング

```bash
# UDP受信バッファ拡張 (/etc/sysctl.conf)
net.rmem_max = 26214400
net.wmem_max = 26214400

# ファイアウォール
ufw allow 64738/tcp
ufw allow 64738/udp
ufw allow 8766/tcp
```

---

# 6. VC Controlサーバ設計書

## 6.1 技術スタック

| 項目 | 選択 | 理由 |
|------|------|------|
| 言語 | Python 3.11 | asyncio成熟、開発速度 |
| フレームワーク | FastAPI + websockets 12.x | 型安全・高性能WS |
| コンテナ | Docker (python:3.11-slim) | 軽量・再現性 |
| 状態管理 | メモリ内dict | 初期実装 (将来: Redis) |
| 認証 | hmac (stdlib) | 依存最小 |

## 6.2 モジュール構成

```
vc-control/
├── Dockerfile
├── requirements.txt
├── main.py              # エントリポイント、uvicorn起動
├── config.py            # 設定値 (環境変数読み込み)
├── auth.py              # HMAC検証、セッション管理
├── state.py             # PlayerState管理
├── delta.py             # 差分抽出・閾値フィルタ
├── broadcaster.py       # WS接続管理・ブロードキャスト
├── handlers/
│   ├── oxide.py         # /oxide エンドポイント
│   └── client.py        # /client エンドポイント
└── models.py            # Pydantic モデル定義
```

## 6.3 内部状態モデル

```python
@dataclass
class Vec3:
    x: float; y: float; z: float

@dataclass
class Rot2:
    yaw: float; pitch: float

@dataclass
class PlayerState:
    steam_id: str
    pos: Vec3
    rot: Rot2
    alive: bool
    team_id: int | None
    last_updated: float        # unix time

@dataclass
class ServerState:
    players: dict[str, PlayerState]
    prev_players: dict[str, PlayerState]  # 差分比較用
    last_frame_tick: int

@dataclass
class ClientSession:
    session_id: str
    steam_id: str
    ws: WebSocket
    connected_at: float
    initialized: bool          # state_full 送信済みフラグ
```

## 6.4 差分抽出ロジック (delta.py)

```python
POS_THRESHOLD   = float(os.getenv("POS_THRESHOLD",   "0.1"))   # m
ANGLE_THRESHOLD = float(os.getenv("ANGLE_THRESHOLD", "1.0"))   # 度

def is_changed(prev: PlayerState, curr: PlayerState) -> bool:
    if prev.alive != curr.alive:       return True
    if prev.team_id != curr.team_id:   return True
    dx = curr.pos.x - prev.pos.x
    dy = curr.pos.y - prev.pos.y
    dz = curr.pos.z - prev.pos.z
    if dx*dx + dy*dy + dz*dz >= POS_THRESHOLD ** 2:
        return True
    yaw_diff = abs(curr.rot.yaw - prev.rot.yaw) % 360
    if yaw_diff > 180: yaw_diff = 360 - yaw_diff
    if yaw_diff >= ANGLE_THRESHOLD:    return True
    if abs(curr.rot.pitch - prev.rot.pitch) >= ANGLE_THRESHOLD:
        return True
    return False

def extract_delta(
    prev: dict[str, PlayerState],
    curr: dict[str, PlayerState]
) -> tuple[list[PlayerState], list[str]]:
    changed = [
        curr[sid] for sid in curr
        if sid not in prev or is_changed(prev[sid], curr[sid])
    ]
    removed = [sid for sid in prev if sid not in curr]
    return changed, removed
```

## 6.5 処理フロー

### Oxide ハンドラ (oxide.py)

```
受信 → JSONパース → Oxide認証確認 (OXIDE_TOKEN ヘッダ)
    → curr_dict 構築
    → extract_delta(state.prev_players, curr_dict)
    → changed空 かつ removed空 → スキップ
    → broadcaster.broadcast_delta(changed, removed, tick, ts)
    → state.prev_players = curr_dict
```

### クライアント ハンドラ (client.py)

```
WS接続
    → auth メッセージ受信
    → auth.verify(steam_id, token) → OK
    → auth_ack 送信
    → broadcaster.send_full(session, state) → state_full 送信
    → session.initialized = True
    → 切断まで待機 (delta は broadcaster が送信)
```

### ブロードキャスタ (broadcaster.py)

```python
async def broadcast_delta(changed, removed, tick, ts):
    if not changed and not removed:
        return
    payload = json.dumps({
        "type": "state_delta",
        "tick": tick,
        "timestamp_ms": ts,
        "changed": [to_dict(p) for p in changed],
        "removed": removed
    })
    # JSON生成は1回。全クライアントに同一payloadを並列送信
    tasks = [
        s.ws.send(payload)
        for s in sessions.values() if s.initialized
    ]
    await asyncio.gather(*tasks, return_exceptions=True)

async def send_full(session, state):
    payload = json.dumps({
        "type": "state_full",
        "tick": state.last_frame_tick,
        "timestamp_ms": int(time.time() * 1000),
        "players": [to_dict(p) for p in state.players.values()]
    })
    await session.ws.send(payload)
    session.initialized = True
```

## 6.6 パフォーマンス設計

| 項目 | 目標 | 設計 |
|------|------|------|
| ブロードキャスト遅延 | < 5ms | asyncio gather 並列送信 |
| delta JSON生成 | 1回のみ | 50クライアント全員に同一payload |
| 差分抽出コスト | < 0.5ms | 単純ループ (50人) |
| 無変化フレームコスト | ≒ 0 | 送信処理自体をスキップ |
| メモリ追加消費 | +~20KB | prev_players の保持 |
| CPU使用率 | < 5% | シングルコア想定 |

## 6.7 環境変数

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `OXIDE_TOKEN` | (必須) | Oxide接続認証共有鍵 |
| `SHARED_SECRET` | (必須) | プレイヤートークン HMAC鍵 |
| `OXIDE_PORT` | 8765 | Oxide接続ポート |
| `CLIENT_PORT` | 8766 | クライアント接続ポート |
| `SESSION_TTL` | 14400 | セッション有効秒 |
| `STATE_TIMEOUT` | 5.0 | プレイヤー情報失効秒 |
| `POS_THRESHOLD` | 0.1 | 座標変化閾値(m) |
| `ANGLE_THRESHOLD` | 1.0 | 角度変化閾値(度) |
| `SSL_CERT` | (必須) | TLS証明書パス |
| `SSL_KEY` | (必須) | TLS秘密鍵パス |

---

# 7. 外部VCアプリ設計書

## 7.1 技術スタック

| 項目 | 選択 |
|------|------|
| 言語 | C# .NET 8 |
| UI | WPF (MVVM) |
| Mumble接続 | MumbleSharp (修正版) |
| WebSocket | System.Net.WebSockets |
| DI | Microsoft.Extensions.DependencyInjection |
| MVVM | CommunityToolkit.Mvvm |

## 7.2 プロジェクト構成

```
vc-app/
├── RustPVC.csproj
├── App.xaml / App.xaml.cs
├── Views/
│   ├── MainWindow.xaml          # メイン画面
│   ├── VolumePanel.xaml         # 個別音量スライダー一覧
│   └── SettingsWindow.xaml      # 接続設定
├── ViewModels/
│   ├── MainViewModel.cs
│   ├── PlayerVolumeViewModel.cs
│   └── SettingsViewModel.cs
├── Models/
│   ├── PlayerState.cs
│   ├── Vec3.cs
│   └── AudioSettings.cs
├── Services/
│   ├── VcControlService.cs      # WebSocket接続・状態管理
│   ├── MumbleService.cs         # Mumble接続・音量制御
│   ├── ProximityAudioEngine.cs  # 減衰・指向性計算
│   └── AuthService.cs           # トークン・セッション管理
└── Core/
    ├── DistanceAttenuation.cs
    ├── DirectionalAudio.cs
    └── AppSettings.cs           # 設定永続化 (JSON)
```

## 7.3 クラス責務

| クラス | 責務 |
|--------|------|
| `VcControlService` | WS接続・auth・state受信・自動再接続 |
| `ProximityAudioEngine` | 距離減衰・指向性計算 → AudioParams |
| `MumbleService` | Mumble接続・Volume/Pan API呼び出し |
| `PlayerVolumeViewModel` | UI状態: 距離・音量スライダー・ミュート |
| `AuthService` | トークン保存・セッション管理 |

## 7.4 UIレイアウト（概念）

```
┌───────────────────────────────────────────┐
│ RustPVC  ● 接続中  [設定]                  │
├───────────────────────────────────────────┤
│ 近くのプレイヤー (距離近い順・自動更新)       │
│                                           │
│ ⭐ ● PlayerA   12m  [========--] 🔊        │
│    ● PlayerB   35m  [=====-----] 🔊        │
│    ○ PlayerC   89m  [----------] 🔇        │
│ ⭐ ● PlayerD  102m  [----------] 🔊 ※1    │
│                                           │
├───────────────────────────────────────────┤
│ マスター音量: [========--] 80%              │
└───────────────────────────────────────────┘
※1 お気に入り登録済みは最大聴取距離超でも表示
```

**UI仕様**

| 要素 | 説明 |
|------|------|
| ● (緑丸) | 生存プレイヤー |
| ○ (グレー丸) | 死亡プレイヤー。音量は自動で0、スライダーはグレーアウト |
| 距離表示 | 自分との現在距離(m)。座標フレーム受信のたびにリアルタイム更新 |
| 音量スライダー | 個別音量オーバーライド。0%〜200%で表示、内部値は0.0〜2.0。距離減衰値に乗算。100%超は音声増幅 |
| 🔊 / 🔇 ボタン | クリックでそのプレイヤーをミュート/解除。🔇時はスライダーもグレーアウト |
| ⭐ お気に入り | 右クリックメニューから登録/解除。登録済みは最大聴取距離超でもリストに残る |
| リスト順 | お気に入り → 距離近い順。フレーム受信ごとに再ソート |
| 最大聴取距離超え | 通常プレイヤーはリストから非表示（デフォルト100m超）。お気に入りは除外 |

**お気に入り仕様**

- 登録はプレイヤー行の右クリックメニュー → 「お気に入りに追加」
- 登録データは `AppSettings.json` に SteamID64 で永続化
- お気に入りプレイヤーはリスト最上部に固定表示（距離順ソートの前に挿入）
- 最大聴取距離を超えても表示は維持するが、音量は距離減衰計算通り（= 0に近い）
- ミュートとお気に入りは独立して設定可能

## 7.5 設定永続化項目

| 設定 | デフォルト |
|------|-----------|
| VC Control Server URL | `wss://localhost:8766/client` |
| Mumble Host | `localhost` |
| Mumble Port | `64738` |
| SteamID | (手動入力) |
| Token | (手動入力・保存可) |
| 最大聴取距離 | 100.0m |
| 減衰カーブ | InverseSquare |
| マスター音量 | 1.0 |

---

# 8. 距離減衰アルゴリズム設計書

## 8.1 距離計算

```
distance = sqrt((x2-x1)² + (y2-y1)² + (z2-z1)²)
```

Y軸（高さ）を含む3Dユークリッド距離。

## 8.2 減衰モデル（3種、設定で切替可）

### 逆二乗減衰（デフォルト・推奨）

```
ref_dist = 3.0m   (この距離以内は最大音量)
max_dist = 100.0m (この距離以遠は無音)

if distance <= ref_dist:
    return 1.0
if distance >= max_dist:
    return 0.0
normalized = (distance - ref_dist) / (max_dist - ref_dist)
return (1.0 - normalized) ^ 2
```

### 線形減衰

```
return 1.0 - clamp((distance - ref_dist) / (max_dist - ref_dist), 0, 1)
```

### 対数減衰（現実に近い）

```
return clamp(1.0 - log10(distance / ref_dist) / log10(max_dist / ref_dist), 0, 1)
```

## 8.3 減衰カーブ比較

```
音量
1.0 |●
    |  \
0.8 |   \
    |    ── 逆二乗
0.6 |      \
    |   ────\ 線形
0.4 |         \
    |    ────\ \ 対数
0.2 |            ─\
    |               ──────
0.0 +──────────────────── 距離(m)
    0   20   40   60   80  100
```

## 8.4 死亡プレイヤー処理

| 状態 | 音量係数 |
|------|---------|
| 生存→生存 | 通常計算 |
| 生存→死亡(受信) | 0.0 (無音) |
| 死亡→死亡 | 0.0 (無音) |

## 8.5 個別音量オーバーライド

```
final_volume = attenuation_volume × user_override × master_volume

attenuation_volume : 距離減衰計算結果 (0.0 ~ 1.0)
user_override      : UIスライダー値   (0%〜200%表示, 内部値0.0〜2.0, デフォルト100%)
                     ※ 100%超は音声増幅（Mumble側クリッピングに注意）
master_volume      : マスター音量     (0.0 ~ 1.0, デフォルト1.0)
```

---

# 9. 指向性アルゴリズム設計書

## 9.1 設計方針

L/R パンニングで方向定位を実現する。  
3Dバイノーラルは MumbleSharp の制約上実装しない。

## 9.2 パン計算

```
// 相手の位置ベクトル差
diff = other.pos - self.pos

// 自分の向き（yaw）から Right ベクトル生成
self_right = Vec3(cos(self.yaw_rad), 0, -sin(self.yaw_rad))

// 水平面での右方向成分 → パン値
horizontal_diff = Vec3(diff.x, 0, diff.z)
if length(horizontal_diff) < 0.001:
    pan = 0.0                              // 真上/真下
else:
    pan = dot(normalize(horizontal_diff), self_right)  // -1.0(左) ~ +1.0(右)
```

## 9.3 仰角補正（オプション）

```
vertical_angle = atan2(diff.y, length(horizontal_diff))
vertical_factor = 1.0 - 0.2 × abs(sin(vertical_angle))
// 仰角が大きいほど最大20%音量減 (自然な立体感)
```

## 9.4 等電力パンニング（Mumble適用）

```csharp
float panRad    = pan * (MathF.PI / 2f);
float leftGain  = MathF.Cos((panRad + MathF.PI / 2f) / 2f);
float rightGain = MathF.Cos((panRad - MathF.PI / 2f) / 2f);

leftSample  *= volume * leftGain;
rightSample *= volume * rightGain;
```

## 9.5 更新頻度とコスト

| 項目 | 値 |
|------|-----|
| 更新頻度 | 20Hz (座標フレームと同期) |
| 1ペア計算 | ~20 float演算 |
| 50人分 | ~1000演算 |
| 20Hz換算 | ~20,000演算/秒 → CPU負荷無視できる |

---

# 10. 負荷見積もり設計書

## 10.1 コンポーネント別負荷

### Oxide Plugin

| 項目 | 見積もり |
|------|---------|
| 座標取得 + JSON serialize (50人) | ~1.5ms/frame |
| WS送信 (4KB × 20Hz) | 80KB/s (localhost) |
| CPU追加負荷 | < 1% |

### VC Control Server (Docker)

| 項目 | 従来(full) | 差分送信 |
|------|-----------|---------|
| 送信帯域 (50クライアント) | 4 MB/s | ~1.5 MB/s |
| JSON生成 | 毎フレーム全員分 | 変化分のみ1回 |
| CPU使用率 | < 5% | < 3% |
| メモリ | < 50MB | < 70MB (+prev_players) |

### Mumble Server (Docker)

| 項目 | 見積もり |
|------|---------|
| 同時5人発話 → 50人受信 | 40kbps×5 入力, ~10Mbps 出力 |
| CPU | < 20% (2コア) |
| メモリ | < 100MB |

### 外部VCアプリ (クライアント)

| 項目 | 見積もり |
|------|---------|
| 座標受信・マージ | < 1ms |
| 距離・指向性計算 (50人) | < 1ms |
| Mumble 音量設定 (50回) | < 5ms |
| 合計CPU | < 5% |

## 10.2 同一VM帯域サマリ

```
VM内部通信 (Oxide → VC Control, localhost):
  80KB/s → 実質無負荷

外部送信 (VC Control → VCアプリ 50クライアント):
  full毎回: 4 MB/s = 32 Mbps
  差分送信: ~1.5 MB/s = ~12 Mbps (平均)
  ピーク:   ~3.2 MB/s = ~26 Mbps (全員移動時)

音声 (Mumble → 各クライアント):
  5人発話 × 40kbps × 50クライアント = ~10 Mbps

合計外部送信ピーク: ~36 Mbps
推奨上流回線: 100 Mbps
最低上流回線: 50 Mbps (差分送信あり・平均時)
```

## 10.3 スケーラビリティ上限

| 接続数 | 差分送信帯域(平均) | 判定 |
|--------|-----------------|------|
| 10 | ~300KB/s | ✅ |
| 50 | ~1.5MB/s | ✅ 設計範囲内 |
| 100 | ~3MB/s | ⚠️ 帯域注意 |
| 200 | ~6MB/s | ❌ 要スケールアウト |

---

# 11. 将来拡張設計

## 11.1 無線通話（ウォーキートーキー）

### 概要

特定アイテム所持中に、Rustのキーバインドで設定したキーを**押している間だけ**無線送信が
有効になるPTT（Push-To-Talk）方式。距離に依存せず同一radio_channelの全員に届く。

グローバルキーフックは EAC との干渉リスクがあるため使用しない。
代わりに Rust 標準の `input.bind` + Oxide `OnServerCommand` フックを使用する。
これはEACに干渉せず、Rustバニラ機能の範囲内で動作する。

### PTTトリガー方式: Rustキーバインド

```
【プレイヤー設定手順（初回のみ）】
Rustコンソールで以下を実行:
  input.bind h +pvc.radio    ← h キーに無線PTTを割り当てる例
  input.bind h -pvc.radio    ← 離した時のコマンド

【動作フロー】
PTTキー押下
  → Rust クライアントが +pvc.radio コマンドをサーバへ送信
  → Oxide OnServerCommand フックで検知
  → radio_transmitting = true を VC Control Server へ送信
  → VCアプリが VoiceTarget を無線チャンネル参加者に設定 → 無線送信開始

PTTキー離す
  → Rust クライアントが -pvc.radio コマンドをサーバへ送信
  → Oxide OnServerCommand フックで検知
  → radio_transmitting = false を VC Control Server へ送信
  → VCアプリが VoiceTarget を解除 → 通常近接ボイスに戻る
```

### アイテム所持判定

```
Oxide Plugin が毎フレーム (20Hz) チェック:
  無線機アイテムを所持している → radio_channel を付与して送信
  所持していない → radio_channel = null、radio_transmitting = false に強制リセット

※ アイテムを捨てた・破壊された場合も即座にリセットされる
```

### 音声適用（受信側）

```
送信者の radio_transmitting = true
かつ 自分と同一 radio_channel
かつ 距離 > max_dist
  → volume = 0.2 (固定) / pan = 0.0 (定位なし)
  → バンドパスフィルタ (300-3000Hz) でトランシーバー感を演出

距離 <= max_dist の場合:
  → 通常の近接音声として処理（無線より近接優先）
```

### フレーム拡張（state_delta への追加フィールド）

```json
{
  "players": [{
    "steam_id": "...",
    "radio_channel": 1,          // null = 無線なし / 1〜10 = チャンネル番号
    "radio_transmitting": true   // +pvc.radio 受信中 = true
  }]
}
```

### VCアプリ設定項目追加

| 設定 | デフォルト | 説明 |
|------|-----------|------|
| 無線チャンネル番号 | 1 | 接続する無線チャンネル (1〜10) |
| 無線受信音量 | 0.2 | 無線受信時の固定音量 |

PTTキーの設定はVCアプリ側ではなくRustコンソールの `input.bind` で行う。

### EAC安全性

| 方式 | EACリスク | 採用 |
|------|----------|------|
| `SetWindowsHookEx WH_KEYBOARD_LL` (低レベルフック) | 高（チートと同手法） | ❌ 不採用 |
| `RegisterHotKey` (Windows API) | 低〜中 | ❌ 不採用（不確実） |
| Rust `input.bind` + Oxide フック | **なし**（ゲーム標準機能） | ✅ **採用** |

## 11.2 ゾーン方式

```json
{
  "zones": [
    {"id": "bandit",  "center": {"x":0,"y":0,"z":0},      "radius": 150, "mumble_channel": "Zone-Bandit"},
    {"id": "outpost", "center": {"x":500,"y":0,"z":-200}, "radius": 100, "mumble_channel": "Zone-Outpost"}
  ]
}
```

VC Control Server がゾーン判定 → Murmur ICE API でチャンネル移動 → `channel_change` イベント送信。

## 11.3 チーム通話

### チャンネルリスナーAPI 調査結果

Mumble 1.4でChannelListeners（チャンネルに参加せずにリッスンする機能）が追加された。
これを使えば「通常チャンネルに所属しながらチームチャンネルも同時受信」が可能になる。

**MumbleSharp (v2.0.1) の対応状況:**
- IMumbleProtocol / BasicMumbleProtocol のソースコードを調査した結果、
  ChannelListener関連のメソッド・プロトコルメッセージは**実装されていない**
- MumbleSharpはMumble 1.2〜1.3相当のプロトコルに留まっており、1.4の新機能は未対応
- リポジトリのIssue/PRにもChannelListener対応の動きは確認できない

**結論: Phase3時点ではMumbleSharpのforkが必要**

### 実装方針（2段階）

**確定方針: MumbleSharp fork + ChannelListener + VoiceTarget**

チャンネル構成:

```
Root
├── RustPVC-Main   ← 全員が所属する近接ボイスチャンネル
└── RustPVC-Team-{teamID}   ← チームごとの専用チャンネル (Phase3で作成)
```

受信（ChannelListener）:

```
MumbleSharpをforkしてChannelListener protobufメッセージを実装
  LocalUser は RustPVC-Main に所属したまま
  LocalUser.AddChannelListener(teamChannelId) を呼び出す
  → RustPVC-Main の音声 + RustPVC-Team-{teamID} の音声を同時受信
  → チーム音声は pan=0.0、team_volume (デフォルト0.5) で受信
サーバ側: Mumble 1.5.x (Docker公式イメージ) は ChannelListener 対応済み
```

送信（VoiceTarget / Whisper）:

```
VoiceTarget は MumbleSharp v2.0.1 に実装済み（BasicMumbleProtocol 確認済み）
  通常時: VoiceTarget なし → RustPVC-Main へ近接ボイス送信
  チーム送信時: VoiceTarget = TeamChannel → チームメンバーのみに送信
  ※ チーム送信は常時ではなく、将来的にPTTキーで切り替え可能にする
```

音声の二重受信対策:

```
チームメンバーが近接範囲内にいる場合:
  ChannelListener 経由のチーム音声と近接音声が重複する
  → VCアプリ側で「同一SteamIDの音声は1系統のみ採用」するマージ処理が必要
  → 優先度: 近接音声 > チーム音声（距離情報があるため）
```

### リスク

| 項目 | リスク | 対策 |
|------|--------|------|
| MumbleSharp fork メンテコスト | 中 | 最小限の変更に留める |
| Mumbleサーバ側の権限設定 | 低 | allowlisten=true (デフォルト有効) |
| 音声の二重受信 | 中 | 同一ユーザが両チャンネルにいる場合の重複制御が必要 |

## 11.4 電話統合（Telephone / Mobile Phone）

### 概要

Rustのゲーム内電話（固定電話・携帯電話）で通話開始時に、RustPVCの音声を使って
「電話らしい音質」の1対1通話を実現する。無線通話と同じVoiceTarget + フィルタ方式。

### Oxide フック

```csharp
// 通話開始（発信者・受信者の両方のSteamIDを取得可能）
void OnPhoneCallStarted(PhoneController phone, PhoneController otherPhone, BasePlayer player)

// 通話終了
void OnPhoneCallEnded(PhoneController phone, BasePlayer player)
// ※ OnPhoneHangUp が存在しない場合は OnPhoneCallEnded で代用
```

### 動作フロー

```
【通話開始】
OnPhoneCallStarted 発火
  → 発信者SteamID と 受信者SteamID を取得
  → VC Control Server へ phone_call_start イベント送信
      {type: "phone_call_start", caller: "steamid_A", receiver: "steamid_B"}
  → VCアプリ(A): VoiceTarget を B のみに設定
  → VCアプリ(B): VoiceTarget を A のみに設定
  → 双方向の1対1通話が成立

【音声処理（受信側）】
  距離減衰: 無効（どこにいても同じ音量）
  パン: 0.0（定位なし）
  音量: phone_volume (デフォルト0.8)
  フィルタ: バンドパス (300-3000Hz) で電話音質を演出

【通話終了】
OnPhoneCallEnded 発火
  → VC Control Server へ phone_call_end イベント送信
  → VoiceTarget を解除 → 通常の近接ボイスに戻る
```

### 通信仕様追加（VC Control Server → VCアプリ）

```json
// 通話開始通知
{
  "type": "phone_call_start",
  "caller_steam_id": "76561198000000001",
  "receiver_steam_id": "76561198000000002"
}

// 通話終了通知
{
  "type": "phone_call_end",
  "caller_steam_id": "76561198000000001",
  "receiver_steam_id": "76561198000000002"
}
```

### 無線・電話・近接ボイスの比較

| 項目 | 近接ボイス | 無線通話 | 電話通話 |
|------|----------|---------|---------|
| トリガー | 常時 | `input.bind` PTT | `OnPhoneCallStarted` |
| 対象 | 近接全員 | 同一radio_channelの全員 | 特定の2者間 |
| 距離依存 | あり | なし | なし |
| 音質フィルタ | なし | バンドパス | バンドパス |
| パン | あり | なし | なし |
| 送信方式 | 通常送信 | VoiceTarget (チャンネル) | VoiceTarget (ユーザ指定) |
| Oxide フック | - | OnServerCommand | OnPhoneCallStarted |

### VCアプリ設定項目追加

| 設定 | デフォルト | 説明 |
|------|-----------|------|
| 電話受信音量 | 0.8 | 電話通話時の固定音量 |

## 11.5 ロードマップとの対応

| フェーズ | 拡張機能 |
|---------|---------|
| Phase 3 | 無線通話・チーム通話 (ChannelListener fork + VoiceTarget)・電話統合 |
| Phase 4 | ゾーン方式・Murmur ICE API 連携 |

---

# 12. セキュリティ設計書

## 12.1 脅威と対策マトリクス

| 脅威 | 対策 | 優先度 |
|------|------|--------|
| SteamIDなりすまし | HMAC-SHA256 + 有効期限 | 最高 |
| 盗聴 (座標) | wss:// TLS 1.3 | 高 |
| 盗聴 (音声) | Mumble TLS (標準) | 高 |
| DoS (接続数) | 接続数制限 + レートリミット | 高 |
| 座標改ざん | Oxide のみ送信権限、OXIDE_TOKEN | 中 |
| 情報漏洩 | ログに座標を記録しない | 中 |
| セッション固定 | 再認証時に session_id 再生成 | 中 |

## 12.2 通信暗号化

```
Oxide → VC Control (localhost): ws:// (暗号化不要、同一ホスト)
VCアプリ → VC Control (外部):  wss:// TLS 1.3 (必須)
VCアプリ → Mumble:             TLS (Mumble標準)
証明書: Let's Encrypt (公開サーバ) / 自己署名 (内部テスト)
```

## 12.3 レートリミット

| エンドポイント | 制限 |
|--------------|------|
| /oxide (接続数) | 最大3接続 |
| /client (接続数) | 最大70接続 |
| auth メッセージ | 10回/分/IP |
| 座標フレーム | 最大30フレーム/秒 |

## 12.4 ログ方針

記録する: 接続/切断 (SteamID, IP, 時刻) / 認証成否 / 異常切断  
記録しない: 座標値 / 音声内容 / チャット内容  
保持期間: 7日間

## 12.5 Oxide Plugin セキュリティ

- `OXIDE_TOKEN` ヘッダによるサーバ間認証
- Oxide → VC Control は localhost 限定接続推奨
- `shared_secret` はサーバ設定ファイルで管理 (サーバ管理者責任範囲)

---

# 13. フェーズ分割ロードマップ

## フェーズ概要

```
Phase 0: 環境構築      [1週間]  → 全コンポーネント疎通確認
Phase 1: MVP           [2〜3週間] → 距離減衰が動くプロトタイプ
Phase 2: 品質向上      [2週間]  → 本番投入可能な安定版
Phase 3: 拡張機能      [4〜5週間] → 無線・チーム通話・電話統合・ゾーン方式
Phase 4: 本番運用      [継続]   → 監視・自動化・ドキュメント
```

## Phase 0: 環境構築

| タスク | 詳細 |
|--------|------|
| Docker Compose 構築 | vc-control + mumble 起動確認 |
| Mumble 通話テスト | マイクテスト・Opus確認 |
| VC Control 骨格 | WS受信のみ動作確認 |
| VCアプリ骨格 | C# プロジェクト作成・Mumble接続 |
| Oxide Plugin骨格 | 座標ログ出力のみ |

完了条件: 2人でMumble通話成功 + VC Controlへ座標が届いている

## Phase 1: MVP

| タスク | 詳細 |
|--------|------|
| Oxide Plugin | 座標JSON送信 (20Hz) |
| VC Control | 差分送信・ブロードキャスト実装 |
| VCアプリ | WS受信・距離計算・Mumble音量設定 |
| 認証 | SteamID手動入力 (HMAC未実装可) |

完了条件: 2人で距離に応じた音量変化を体感確認

## Phase 2: 品質向上

| タスク | 詳細 |
|--------|------|
| 認証完全実装 | HMAC-SHA256トークン |
| 指向性(パン)実装 | L/R パンニング |
| TLS化 | wss:// 対応 |
| 自動再接続 | WS切断時の再接続 (exponential backoff) |
| 個別音量UI完成 | スライダー・ミュート |
| エラーハンドリング | 全コンポーネント |
| Docker本番設定 | ヘルスチェック・ログ設定 |

完了条件: 5人での実戦テストで安定動作

## Phase 3: 拡張機能

| タスク | 詳細 |
|--------|------|
| 無線通話 | アイテム判定 + `input.bind` PTT + VoiceTarget + バンドパスフィルタ |
| チーム通話 | MumbleSharp fork (ChannelListener実装) + VoiceTarget |
| 電話統合 | OnPhoneCallStarted/Ended フック + VoiceTarget + バンドパスフィルタ |
| 音声二重受信対策 | チームメンバー近接時のマージ処理実装 |
| ゾーン方式 | エリア別チャンネル切り替え（Murmur ICE API） |

## Phase 4: 本番運用

| タスク | 詳細 |
|--------|------|
| 監視 | Dockerヘルスチェック + 死活監視 |
| 自動起動 | systemd + Docker自動再起動 |
| 負荷計測 | 実50人での帯域・CPU実測 |
| プレイヤー向け手順書 | /vctokenからVCアプリ接続まで |

## 技術リスク

| リスク | 確率 | 対策 |
|--------|------|------|
| MumbleSharp VolAPI制限 | 中 | Phase0でAPI確認、必要なら fork |
| MumbleSharp fork (ChannelListener) | 中 | 最小限の実装に留める。protobuf定義はMumble公式を参照 |
| PTT `input.bind` コマンド衝突 | 低 | コマンド名に `pvc.` プレフィックスを付けて衝突回避 |
| 電話フック `OnPhoneCallEnded` 欠落 | 低 | 複数フックで終了を検知（Hangup/Timeout含む） |
| Oxide API変更 | 低 | バージョン固定 |
| EACによる外部プロセス検出 | 低 | DLL注入なし、プロセス改変なし |
| 帯域不足 (同一VM) | 中 | 差分送信で対応済み |

---

# 14. プロジェクト構成・Docker設計書

## 14.1 リポジトリ構成

```
RustProximityVoiceChat/
├── README.md
├── .gitignore
│
├── oxide-plugin/                    # Oxide Mod (C#)
│   ├── RustProximityVoiceChat.cs    # メインプラグインファイル
│   └── README.md
│
├── vc-control/                      # VC Control Server (Python)
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── main.py
│   ├── config.py
│   ├── auth.py
│   ├── state.py
│   ├── delta.py
│   ├── broadcaster.py
│   ├── models.py
│   └── handlers/
│       ├── __init__.py
│       ├── oxide.py
│       └── client.py
│
├── mumble/                          # Mumble Server (Docker)
│   ├── Dockerfile
│   ├── murmur.ini
│   └── ssl/                         # .gitignore対象
│       ├── server.crt
│       └── server.key
│
├── vc-app/                          # 外部VCアプリ (C# WPF)
│   ├── RustPVC.csproj
│   ├── RustPVC.sln
│   ├── App.xaml
│   ├── Views/
│   ├── ViewModels/
│   ├── Models/
│   ├── Services/
│   └── Core/
│
├── docker/                          # Docker Compose + ビルドスクリプト
│   ├── docker-compose.yml           # 本番用
│   ├── docker-compose.dev.yml       # 開発用 (ポート開放・ボリュームマウント)
│   ├── build.sh                     # Linux/Mac ビルドスクリプト
│   ├── build.ps1                    # Windows ビルドスクリプト
│   └── .env.example                 # 環境変数テンプレート
│
└── docs/                            # 設計文書
    └── design-v1.0.md               # 本文書
```

## 14.2 docker-compose.yml

```yaml
version: "3.9"

services:
  vc-control:
    build:
      context: ../vc-control
      dockerfile: Dockerfile
    container_name: rustpvc-vc-control
    restart: unless-stopped
    ports:
      - "8766:8766"          # 外部公開 (VCアプリ接続)
    expose:
      - "8765"               # 内部のみ (Oxide接続)
    environment:
      - OXIDE_TOKEN=${OXIDE_TOKEN}
      - SHARED_SECRET=${SHARED_SECRET}
      - OXIDE_PORT=8765
      - CLIENT_PORT=8766
      - SESSION_TTL=14400
      - STATE_TIMEOUT=5.0
      - POS_THRESHOLD=0.1
      - ANGLE_THRESHOLD=1.0
      - SSL_CERT=/certs/server.crt
      - SSL_KEY=/certs/server.key
    volumes:
      - ../mumble/ssl:/certs:ro
    networks:
      - rustpvc-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8765/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  mumble:
    build:
      context: ../mumble
      dockerfile: Dockerfile
    container_name: rustpvc-mumble
    restart: unless-stopped
    ports:
      - "64738:64738/tcp"
      - "64738:64738/udp"
    volumes:
      - ../mumble/murmur.ini:/etc/mumble-server/mumble-server.ini:ro
      - ../mumble/ssl:/etc/mumble-server/ssl:ro
      - mumble-data:/var/lib/mumble-server
    networks:
      - rustpvc-net
    healthcheck:
      test: ["CMD-SHELL", "nc -z localhost 64738 || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  rustpvc-net:
    driver: bridge

volumes:
  mumble-data:
```

## 14.3 docker-compose.dev.yml

```yaml
version: "3.9"

services:
  vc-control:
    extends:
      file: docker-compose.yml
      service: vc-control
    ports:
      - "8765:8765"          # 開発時は外部公開
      - "8766:8766"
    volumes:
      - ../vc-control:/app   # ホットリロード用ソースマウント
      - ../mumble/ssl:/certs:ro
    environment:
      - DEBUG=1
      - SSL_CERT=/certs/server.crt
      - SSL_KEY=/certs/server.key

  mumble:
    extends:
      file: docker-compose.yml
      service: mumble
```

## 14.4 vc-control/Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# 依存インストール (レイヤーキャッシュ最適化)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ソースコピー
COPY . .

# 非rootユーザで実行
RUN useradd -m appuser
USER appuser

EXPOSE 8765 8766

CMD ["python", "-m", "uvicorn", "main:app", \
     "--host", "0.0.0.0", \
     "--port", "8766", \
     "--ssl-certfile", "/certs/server.crt", \
     "--ssl-keyfile", "/certs/server.key"]
```

## 14.5 mumble/Dockerfile

```dockerfile
FROM mumble/mumble-server:1.5

# カスタム設定をイメージに焼き込まない
# → murmur.ini はボリュームマウントで差し込む (docker-compose.yml参照)
# → SSL証明書も同様

# ポート
EXPOSE 64738/tcp 64738/udp
```

## 14.6 build.sh（Linux/Mac）

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 引数処理
MODE="${1:-prod}"   # prod | dev
ACTION="${2:-up}"   # up | down | build | logs

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
if [ "$MODE" = "dev" ]; then
  COMPOSE_FILE="$SCRIPT_DIR/docker-compose.dev.yml"
fi

# .env 確認
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "[ERROR] $SCRIPT_DIR/.env が存在しません。"
  echo "        .env.example をコピーして設定してください。"
  exit 1
fi

echo "[RustPVC] mode=$MODE action=$ACTION"

case "$ACTION" in
  up)
    docker compose -f "$COMPOSE_FILE" --env-file "$SCRIPT_DIR/.env" up -d --build
    echo "[RustPVC] 起動完了"
    docker compose -f "$COMPOSE_FILE" ps
    ;;
  down)
    docker compose -f "$COMPOSE_FILE" down
    ;;
  build)
    docker compose -f "$COMPOSE_FILE" --env-file "$SCRIPT_DIR/.env" build --no-cache
    ;;
  logs)
    docker compose -f "$COMPOSE_FILE" logs -f
    ;;
  *)
    echo "Usage: $0 [prod|dev] [up|down|build|logs]"
    exit 1
    ;;
esac
```

## 14.7 build.ps1（Windows）

```powershell
param(
    [string]$Mode   = "prod",   # prod | dev
    [string]$Action = "up"      # up | down | build | logs
)

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile    = Join-Path $ScriptDir ".env"
$ComposeFile = Join-Path $ScriptDir "docker-compose.yml"

if ($Mode -eq "dev") {
    $ComposeFile = Join-Path $ScriptDir "docker-compose.dev.yml"
}

if (-not (Test-Path $EnvFile)) {
    Write-Error "[ERROR] $EnvFile が存在しません。.env.example をコピーして設定してください。"
    exit 1
}

Write-Host "[RustPVC] mode=$Mode action=$Action"

switch ($Action) {
    "up" {
        docker compose -f $ComposeFile --env-file $EnvFile up -d --build
        Write-Host "[RustPVC] 起動完了"
        docker compose -f $ComposeFile ps
    }
    "down"  { docker compose -f $ComposeFile down }
    "build" { docker compose -f $ComposeFile --env-file $EnvFile build --no-cache }
    "logs"  { docker compose -f $ComposeFile logs -f }
    default {
        Write-Host "Usage: build.ps1 [-Mode prod|dev] [-Action up|down|build|logs]"
        exit 1
    }
}
```

## 14.8 docker/.env.example

```dotenv
# ==============================
# RustPVC Docker 環境変数設定
# ==============================
# このファイルを .env にコピーして値を設定すること
# .env は .gitignore に含まれており、リポジトリに含まれない

# VC Control Server 認証鍵 (Oxide接続用)
# openssl rand -hex 32 で生成すること
OXIDE_TOKEN=CHANGE_ME_OXIDE_TOKEN

# プレイヤートークン HMAC 署名鍵
# openssl rand -hex 32 で生成すること
SHARED_SECRET=CHANGE_ME_SHARED_SECRET
```

## 14.9 .gitignore 対象

```gitignore
# 環境変数・秘密情報
docker/.env
mumble/ssl/server.crt
mumble/ssl/server.key

# Python
__pycache__/
*.pyc
.venv/

# .NET
vc-app/bin/
vc-app/obj/

# OS
.DS_Store
Thumbs.db
```

## 14.10 起動手順サマリ

```bash
# 1. リポジトリクローン
git clone https://github.com/your-org/RustProximityVoiceChat
cd RustProximityVoiceChat/docker

# 2. 環境変数設定
cp .env.example .env
vi .env   # OXIDE_TOKEN, SHARED_SECRET を設定

# 3. SSL証明書配置 (自己署名の場合)
openssl req -x509 -newkey rsa:4096 -keyout ../mumble/ssl/server.key \
  -out ../mumble/ssl/server.crt -days 365 -nodes

# 4. 起動 (本番)
./build.sh prod up

# 5. 起動確認
docker compose ps

# 6. ログ確認
./build.sh prod logs
```

---

*文書終端 — RustProximityVoiceChat (RustPVC) Design Documents v1.0.0*

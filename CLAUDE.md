# RustProximityVoiceChat (RustPVC) — Claude Code 指示書

## プロジェクト概要

- **正式名称**: RustProximityVoiceChat
- **略称**: RustPVC
- **目的**: Rust専用の近接ボイスチャット基盤。距離減衰・指向性・個別音量調整・無線通話・電話統合を外部アプリで実現する
- **設計書**: `docs/design-v1.3.md` を必ず参照すること
- **ロードマップ**: `ROADMAP.md` を参照すること

## 絶対制約（変更禁止）

- クライアント改造禁止（DLL注入・Harmony・EAC無効化・Rust本体改変すべて禁止）
- Steam規約違反禁止
- EAC有効のまま運用すること
- Rustゲームサーバへの直接アクセス禁止（Oxide Plugin経由のみ）

## コンポーネント構成

```
RustProximityVoiceChat/
├── CLAUDE.md                    ← このファイル
├── ROADMAP.md                   ← バージョン別ロードマップ
├── docs/
│   └── design-v1.3.md           ← 設計書（実装前に必ず参照）
├── oxide-plugin/                ← C# Oxide Mod
│   ├── CLAUDE.md
│   └── RustProximityVoiceChat.cs
├── vc-control/                  ← Python 3.11 WebSocket サーバ
│   ├── CLAUDE.md
│   └── ...
├── mumble/                      ← Murmur Docker設定
│   ├── CLAUDE.md
│   └── ...
├── vc-app/                      ← C# WPF クライアントアプリ
│   ├── CLAUDE.md
│   └── ...
└── docker/                      ← Docker Compose + ビルドスクリプト
    ├── docker-compose.yml
    ├── docker-compose.dev.yml
    ├── build.sh
    ├── build.ps1
    └── .env.example
```

## ネットワーク構成

| ポート | 用途 | 公開範囲 |
|--------|------|---------|
| 8765 | VC Control ← Oxide (WS) | localhost のみ |
| 8766 | VC Control ← VCアプリ (WSS) | 外部公開 |
| 64738 | Mumble (TCP+UDP) | 外部公開 |
| 28015 | Rust Game | 外部公開 (変更不可) |
| 28016 | Rust RCON | 管理用のみ |

## 共通コーディングルール

### 全般
- コードコメントは日本語で書く
- TODO/FIXME は `// TODO(vX.Y.Z):` 形式で記載する（例: `// TODO(v0.5.0): HMAC認証実装`）
- 実装しないバージョンの機能はスタブを作らず、TODOコメントのみ残す
- ハードコードは禁止。設定値はすべて環境変数または設定ファイルから読み込む

### Git
- コミットメッセージは英語: `feat:`, `fix:`, `docs:`, `chore:`, `test:` プレフィックス
- スコープはコンポーネント名: `feat(vc-control):`, `feat(oxide-plugin):`, `feat(vc-app):` など
- 各バージョンの完了時に `git tag vX.Y.Z` を打つ
- 各コンポーネントは独立してコミット可能な粒度を保つ

### セキュリティ
- シークレット（OXIDE_TOKEN, SHARED_SECRET）は絶対にコードに書かない
- `.env` は `.gitignore` に含まれていることを確認してからコミットする
- ログに座標・音声・チャット内容を記録しない

## バージョン・フェーズ対応表

| バージョン | フェーズ | 概要 |
|-----------|---------|------|
| v0.1.0 | Phase0 | Docker・Mumble起動確認 |
| v0.2.0 | Phase0 | Oxide Plugin骨格・WS疎通確認 ← **Phase0完了** |
| v0.3.0 | Phase1 | 座標送信・差分ブロードキャスト |
| v0.4.0 | Phase1 | 距離減衰・トーク制御 (MVP) ← **Phase1完了** |
| v0.5.0 | Phase2 | HMAC認証・TLS |
| v0.6.0 | Phase2 | 指向性・個別音量UI・自動再接続 ← **Phase2完了** |
| v0.7.0 | Phase3 | 無線PTT |
| v0.8.0 | Phase3 | チーム通話 (ChannelListener fork) |
| v0.9.0 | Phase3 | 電話統合 ← **Phase3完了** |
| v1.0.0 | Phase4 | 本番運用 ← **正式リリース** |

詳細は `ROADMAP.md` を参照。

## 現在のバージョン: v0.1.0 作業中

v0.1.0 の完了条件:
- [ ] `./docker/build.sh dev up` で vc-control / mumble が起動する
- [ ] `curl http://localhost:8765/health` → `{"status":"ok"}` を返す
- [ ] Mumble クライアント2台で通話できる
- [ ] `RustPVC-Main` チャンネルが Mumble サーバ上に存在する

## pvc. コマンド一覧（Oxide Plugin 実装対象）

| コマンド | 種別 | 動作 | 実装バージョン |
|---------|------|------|--------------|
| `+pvc.talk` | PTT押下 | マイクON | v0.4.0 |
| `-pvc.talk` | PTT離す | マイクOFF | v0.4.0 |
| `pvc.mute` | トグル | ミュートON/OFF | v0.4.0 |
| `+pvc.mute` | 一時押し | ミュートON | v0.4.0 |
| `-pvc.mute` | 一時離す | ミュートOFF | v0.4.0 |
| `+pvc.radio` | 無線PTT押下 | 無線送信開始 | v0.7.0 |
| `-pvc.radio` | 無線PTT離す | 無線送信停止 | v0.7.0 |

## 設計書との整合性

実装前に必ず `docs/design-v1.3.md` の該当セクションを確認すること。

| 実装内容 | 参照セクション |
|---------|--------------|
| WebSocket メッセージ形式 | §3 通信仕様書 |
| 差分送信ロジック | §2 データフロー / §6 VC Control |
| 距離減衰計算 | §8 距離減衰アルゴリズム |
| 指向性計算 | §9 指向性アルゴリズム |
| 認証フロー | §4 認証設計書 |
| Docker構成 | §14 プロジェクト構成 |
| トーク制御 | §7.4 外部VCアプリ / §11.1 将来拡張 |
| 無線PTT | §11.1 将来拡張 |
| チーム通話 | §11.3 将来拡張 |
| 電話統合 | §11.4 将来拡張 |

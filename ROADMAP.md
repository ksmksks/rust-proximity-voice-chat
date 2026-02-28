# RustProximityVoiceChat (RustPVC) — ロードマップ

**バージョン体系**: セマンティックバージョニング準拠  
`v{major}.{minor}.{patch}` — minor が上がるたびに動作確認可能な状態  
`v1.0.0` = 本番運用開始

---

## バージョン一覧

| バージョン | フェーズ | 概要 | 想定期間 |
|-----------|---------|------|---------|
| [v0.1.0](#v010--docker--mumble-起動確認) | Phase0 | Docker・Mumble起動確認 | 〜3日 |
| [v0.2.0](#v020--oxide-plugin-骨格--ws疎通確認) | Phase0 | Oxide Plugin骨格・WS疎通確認 | 〜4日 |
| [v0.3.0](#v030--座標送信--差分ブロードキャスト) | Phase1 | 座標送信・差分ブロードキャスト | 〜1週間 |
| [v0.4.0](#v040--vcアプリ-距離減衰--トーク制御-mvp) | Phase1 | VCアプリ距離減衰・トーク制御 (MVP) | 〜1週間 |
| [v0.5.0](#v050--hmac認証--tls) | Phase2 | HMAC認証・TLS | 〜1週間 |
| [v0.6.0](#v060--指向性--個別音量ui--自動再接続) | Phase2 | 指向性・個別音量UI・自動再接続 | 〜1週間 |
| [v0.7.0](#v070--無線ptt) | Phase3 | 無線PTT | 〜1週間 |
| [v0.8.0](#v080--チーム通話-channellistener-fork--voicetarget) | Phase3 | チーム通話 | 〜2週間 |
| [v0.9.0](#v090--電話統合) | Phase3 | 電話統合 | 〜1週間 |
| [v1.0.0](#v100--本番運用) | Phase4 | 本番運用・監視 | 〜1週間 |

---

## v0.1.0 — Docker + Mumble 起動確認

**Phase0 前半**

### 完了条件
- [ ] `./docker/build.sh dev up` で vc-control / mumble が起動する
- [ ] `docker compose ps` で両コンテナが `healthy` になる
- [ ] `curl http://localhost:8765/health` → `{"status":"ok"}` を返す
- [ ] Mumble クライアント2台で `localhost:64738` に接続して音声通話できる
- [ ] `RustPVC-Main` チャンネルが Mumble サーバ上に存在する

### 想定コミット
```
chore: リポジトリ初期化・.gitignore 作成
chore: docker/ ディレクトリ構成作成 (.env.example, build.sh, build.ps1)
feat(docker): docker-compose.yml 作成 (vc-control + mumble)
feat(docker): docker-compose.dev.yml 作成
feat(mumble): Dockerfile + murmur.ini 作成
feat(vc-control): Dockerfile + requirements.txt 作成
feat(vc-control): /health エンドポイント最小実装 (FastAPI)
docs: SSL証明書生成手順を README に記載
```

### 依存関係
なし（最初のバージョン）

---

## v0.2.0 — Oxide Plugin 骨格 + WS疎通確認

**Phase0 後半**

### 完了条件
- [ ] Oxide Plugin が Rust サーバにロードされてエラーが出ない
- [ ] `/vctoken` コマンドがチャット欄に文字列を返す（トークン生成は後回し可）
- [ ] Oxide Plugin が vc-control の `/oxide` エンドポイントに WS 接続できる
- [ ] vc-control がフレームを受信してログに出力する
- [ ] VCアプリ骨格が Mumble サーバに接続して `RustPVC-Main` チャンネルに参加できる
- [ ] 2人でMumble通話成功 + vc-control に座標ログが届く ← **Phase0完了**

### 想定コミット
```
feat(oxide-plugin): RustProximityVoiceChat.cs 初期作成・プラグイン登録
feat(oxide-plugin): OnServerInitialized / Unload / OnPlayerConnected 骨格
feat(oxide-plugin): timer.Every による座標ログ出力 (20Hz)
feat(oxide-plugin): WebSocket 接続・/oxide エンドポイントへの接続
feat(oxide-plugin): /vctoken コマンド骨格（文字列返却のみ）
feat(vc-control): /oxide WebSocket エンドポイント追加・受信ログ出力
feat(vc-app): C# WPF プロジェクト作成・NuGet パッケージ追加
feat(vc-app): MumbleSharp 接続・RustPVC-Main チャンネル参加
docs: Phase0 完了確認手順を README に記載
```

### 依存関係
v0.1.0 完了後

---

## v0.3.0 — 座標送信・差分ブロードキャスト

**Phase1 前半**

### 完了条件
- [ ] Oxide Plugin が 20Hz で `frame` JSON を vc-control へ送信している
- [ ] vc-control が `state.py` / `delta.py` で差分抽出を行っている
- [ ] `delta.py` の単体テストがすべて通る（閾値フィルタの境界値含む）
- [ ] VCアプリが `/client` に接続して `state_full` を受信できる
- [ ] プレイヤーが移動すると `state_delta` が届く
- [ ] 全員静止時はフレームが送信されない（帯域節約を確認）

### 想定コミット
```
feat(oxide-plugin): frame JSON 送信実装 (pos/rot/alive/team_id/steam_id)
feat(oxide-plugin): /vctoken HMAC-SHA256 トークン生成実装
feat(vc-control): models.py / state.py 実装 (PlayerState, ServerState, ClientSession)
feat(vc-control): delta.py 実装 (is_changed, extract_delta)
test(vc-control): test_delta.py 単体テスト作成
feat(vc-control): broadcaster.py 実装 (broadcast_delta, send_full)
feat(vc-control): /client WebSocket エンドポイント実装
feat(vc-control): auth.py 骨格 (SteamID形式チェックのみ、HMAC は v0.5.0)
feat(vc-app): VcControlService.cs WS接続・state_full/delta 受信
feat(vc-app): PlayerState.cs / AppSettings.cs モデル定義
```

### 依存関係
v0.2.0 完了後

---

## v0.4.0 — VCアプリ 距離減衰・トーク制御 (MVP)

**Phase1 後半 / MVP完了**

### 完了条件
- [ ] 距離に応じて相手の音量が変化する（近いと大きく、遠いと小さく）
- [ ] 最大聴取距離（100m）を超えると音量が0になる
- [ ] **オープントーク**: 常時マイクON で音声が届く
- [ ] **PTTモード**: `+pvc.talk` 押下中のみ音声が届く
- [ ] **ミュートトグル**: `pvc.mute` でON/OFF切り替えができる
- [ ] **ミュート一時押し**: `+pvc.mute` 押下中のみミュートになる
- [ ] VCアプリの設定画面でオープントーク/PTTを切り替えられる
- [ ] MumbleSharp の Volume API が実際に機能することを確認済み
- [ ] 2人での実プレイで距離減衰・PTT動作を体感確認 ← **Phase1完了 (MVP)**

### 想定コミット
```
feat(oxide-plugin): OnServerCommand で pvc.talk/pvc.mute/pvc.radio フック実装
feat(oxide-plugin): talking_state / mute_state フレームへの付与
feat(vc-control): talk/mute イベントの state_delta への反映
feat(vc-app): DistanceAttenuation.cs 実装 (InverseSquare/Linear/Logarithmic)
test(vc-app): DistanceAttenuation 単体テスト
feat(vc-app): ProximityAudioEngine.cs 実装 (音量最終計算)
feat(vc-app): MumbleService.cs Volume API 呼び出し実装
feat(vc-app): トークモード管理 (OpenTalk/PTT・mute_active/ptt_active)
feat(vc-app): SettingsWindow.xaml トークモード選択UI
feat(vc-app): MainWindow.xaml 基本レイアウト (プレイヤーリスト・距離表示)
docs: キーバインド設定例を README に追記
```

### キーバインド設定例（README 掲載内容）

```bash
# PTTモード使用時
input.bind mouse4 +pvc.talk
input.bind mouse4 -pvc.talk

# ミュートトグル（どちらのモードでも使用可）
input.bind m pvc.mute

# ミュート一時押し（オープントーク時に便利）
input.bind alt +pvc.mute
input.bind alt -pvc.mute

# 無線PTT（Phase3、先行して設定しておいても良い）
input.bind t +pvc.radio
input.bind t -pvc.radio
```

### 依存関係
v0.3.0 完了後  
MumbleSharp Volume API の動作確認が必須 → 動作しない場合は fork してから進める

---

## v0.5.0 — HMAC認証・TLS

**Phase2 前半**

### 完了条件
- [ ] `/vctoken` が正しい HMAC-SHA256 トークンを生成する
- [ ] vc-control がトークンを検証し、無効なトークンは `AUTH_FAILED` を返す
- [ ] タイムスタンプ有効期限（±5分）が機能する
- [ ] 使い捨てトークン（再利用不可）が機能する
- [ ] vc-control ↔ VCアプリ間が `wss://` (TLS) で通信している
- [ ] Mumble サーバも TLS 接続できている

### 想定コミット
```
feat(oxide-plugin): /vctoken HMAC-SHA256 完全実装 (timestamp付き)
feat(vc-control): auth.py HMAC検証・タイムスタンプ確認・使い捨てトークン実装
test(vc-control): test_auth.py 単体テスト (有効/無効/期限切れ/使用済み)
feat(vc-control): uvicorn TLS設定 (SSL_CERT/SSL_KEY 環境変数)
feat(vc-app): AuthService.cs トークン入力・送信・セッション管理
feat(vc-app): TLS接続対応 (自己署名証明書の許可設定含む)
feat(docker): 本番用 SSL 設定の docker-compose.yml 更新
```

### 依存関係
v0.4.0 完了後

---

## v0.6.0 — 指向性・個別音量UI・自動再接続

**Phase2 後半 / 本番投入可能**

### 完了条件
- [ ] 相手が右にいると右から、左にいると左から音が聞こえる（パンニング）
- [ ] 個別音量スライダーが 0%〜200% の範囲で機能する（デフォルト100%、100%超は増幅）
- [ ] 🔊/🔇 ミュートボタンが機能する
- [ ] ⭐ お気に入り登録・解除ができ、`settings.json` に永続化される
- [ ] プレイヤーリストが距離近い順に自動ソートされる
- [ ] 死亡プレイヤーのスライダーがグレーアウトし音量0になる
- [ ] WS切断時に自動再接続する（指数バックオフ）
- [ ] 全コンポーネントでエラーハンドリングが実装されている
- [ ] 5人での実戦テストで安定動作 ← **Phase2完了**

### 想定コミット
```
feat(vc-app): DirectionalAudio.cs 実装 (パン計算・等電力パンニング)
test(vc-app): DirectionalAudio 単体テスト
feat(vc-app): MumbleService.cs Pan API 呼び出し実装
feat(vc-app): VolumePanel.xaml 個別音量スライダー・ミュートボタン UI
feat(vc-app): PlayerVolumeViewModel.cs 実装
feat(vc-app): お気に入り機能 (右クリックメニュー・AppSettings永続化)
feat(vc-app): プレイヤーリスト距離ソート・死亡グレーアウト
feat(vc-app): VcControlService.cs 自動再接続 (exponential backoff)
fix(vc-control): エラーハンドリング・例外ログ整備
fix(oxide-plugin): 再接続処理・例外ガード追加
feat(docker): healthcheck・ログ設定本番化
```

### 依存関係
v0.5.0 完了後

---

## v0.7.0 — 無線PTT

**Phase3 第1弾**

### 完了条件
- [ ] 無線機アイテム所持中のみ `+pvc.radio` が有効になる
- [ ] `+pvc.radio` 押下中のみ無線チャンネル参加者全員に音声が届く
- [ ] 無線音声にバンドパスフィルタ（300-3000Hz）が適用されている
- [ ] 最大聴取距離外でも無線で届く
- [ ] 無線チャンネル番号（1〜10）を VCアプリ設定で変更できる
- [ ] アイテムを手放すと即座に無線が無効になる

### 想定コミット
```
feat(oxide-plugin): 無線機アイテム所持判定・radio_channel/transmitting フレーム付与
feat(vc-control): radio_transmitting の state_delta 反映
feat(vc-app): VoiceTarget (Whisper) 実装 - 無線チャンネル参加者指定
feat(vc-app): バンドパスフィルタ実装 (300-3000Hz)
feat(vc-app): 無線受信時の音声処理 (volume固定・pan無効化)
feat(vc-app): SettingsWindow 無線チャンネル番号設定
```

### 依存関係
v0.6.0 完了後

---

## v0.8.0 — チーム通話（ChannelListener fork + VoiceTarget）

**Phase3 第2弾**

### 完了条件
- [ ] MumbleSharp fork で ChannelListener protobuf メッセージが実装されている
- [ ] 近接チャンネルに所属したままチームチャンネルの音声を同時受信できる
- [ ] チームメンバーの音声が距離に関係なく届く（team_volume=0.5）
- [ ] 近接範囲内のチームメンバーは近接音声優先でマージされる（二重受信なし）
- [ ] `RustPVC-Team-{teamID}` チャンネルが自動作成・削除される

### 想定コミット
```
chore(vc-app): MumbleSharp fork 作成・ChannelListener protobuf 定義追加
feat(vc-app): ChannelListener 登録/解除 API 実装
feat(vc-app): チーム音声受信処理 (team_volume・pan無効化)
feat(vc-app): 二重受信マージ処理 (近接優先)
feat(vc-control): チームチャンネル自動作成・削除 (Murmur API)
test(vc-app): ChannelListener 統合テスト
```

### 依存関係
v0.7.0 完了後  
MumbleSharp fork 完了が前提

---

## v0.9.0 — 電話統合

**Phase3 第3弾 / Phase3完了**

### 完了条件
- [ ] ゲーム内電話で通話開始すると RustPVC 経由で音声が繋がる
- [ ] 電話音声にバンドパスフィルタ（300-3000Hz）が適用されている
- [ ] 距離に関係なく 1対1 で音声が届く
- [ ] 電話を切ると通常の近接ボイスに戻る
- [ ] 携帯電話・固定電話の両方で動作する ← **Phase3完了**

### 想定コミット
```
feat(oxide-plugin): OnPhoneCallStarted / OnPhoneCallEnded / OnPhoneDialTimedOut フック実装
feat(vc-control): phone_call_start / phone_call_end イベント中継
feat(vc-app): 電話通話状態管理 (caller/receiver SteamID ペア)
feat(vc-app): VoiceTarget ユーザ指定送信 (2者間)
feat(vc-app): 電話受信音声処理 (バンドパスフィルタ・距離無効化)
fix(oxide-plugin): 電話タイムアウト・強制切断時の後処理
```

### 依存関係
v0.8.0 完了後

---

## v1.0.0 — 本番運用

**Phase4完了 / 正式リリース**

### 完了条件
- [ ] systemd で Docker が自動起動する
- [ ] コンテナ異常終了時に自動再起動する
- [ ] 死活監視が動作している（アラート通知）
- [ ] 実50人での帯域・CPU使用率を計測済み
- [ ] プレイヤー向け接続手順書が完成している
- [ ] キーバインド設定例が README に掲載されている

### 想定コミット
```
chore(docker): restart: always + healthcheck 本番設定
feat(ops): systemd unit ファイル作成
feat(ops): 死活監視スクリプト作成
docs: プレイヤー向け接続手順書 (PLAYER_GUIDE.md)
docs: キーバインド設定リファレンス
docs: 負荷計測結果を README に記載
chore: v1.0.0 リリースタグ
```

### 依存関係
v0.9.0 完了後

---

## pvc.コマンド リファレンス

| コマンド | 種別 | 動作 | 有効条件 |
|---------|------|------|---------|
| `+pvc.talk` | PTT押下 | マイクON | PTTモード選択時のみ |
| `-pvc.talk` | PTT離す | マイクOFF | PTTモード選択時のみ |
| `pvc.mute` | トグル | ミュートON/OFF切り替え | 常時 |
| `+pvc.mute` | 一時押し | ミュートON | 常時 |
| `-pvc.mute` | 一時離す | ミュートOFF | 常時 |
| `+pvc.radio` | 無線PTT押下 | 無線送信開始 | 無線機所持時のみ (v0.7.0〜) |
| `-pvc.radio` | 無線PTT離す | 無線送信停止 | 無線機所持時のみ (v0.7.0〜) |

## キーバインド設定例

```bash
# =============================
# RustPVC キーバインド設定例
# Rustコンソール (F1) で実行
# =============================

# --- PTT（PTTモード選択時）---
input.bind mouse4 +pvc.talk
input.bind mouse4 -pvc.talk

# --- ミュートトグル ---
input.bind m pvc.mute

# --- ミュート一時押し（オープントーク時に一時消音）---
input.bind alt +pvc.mute
input.bind alt -pvc.mute

# --- 無線PTT（v0.7.0〜、無線機所持時のみ有効）---
input.bind t +pvc.radio
input.bind t -pvc.radio

# =============================
# 推奨セット: 配信者向け
# =============================
# モード: オープントーク
# Alt で一時消音、T で無線
input.bind alt +pvc.mute
input.bind alt -pvc.mute
input.bind t +pvc.radio
input.bind t -pvc.radio

# =============================
# 推奨セット: ガチ勢向け
# =============================
# モード: PTT
# マウスサイドボタンでPTT、M でミュートトグル、T で無線
input.bind mouse4 +pvc.talk
input.bind mouse4 -pvc.talk
input.bind m pvc.mute
input.bind t +pvc.radio
input.bind t -pvc.radio
```

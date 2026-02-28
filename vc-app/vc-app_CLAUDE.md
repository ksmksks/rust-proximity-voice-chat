# vc-app — Claude Code 指示書

## 概要

C# WPF 製の外部 VCアプリ。
- VC Control Server から座標を受信してローカル状態を管理する
- 距離減衰・指向性を計算して Mumble の音量/パンを制御する
- プレイヤーごとの個別音量UIを提供する

Mumble サーバへの音声送受信は MumbleSharp が担う。
RustPVC はその上で音量・パンのみを制御する。

## 技術スタック

| 項目 | 採用 | バージョン |
|------|------|----------|
| 言語 | C# | 12 |
| フレームワーク | .NET 8 / WPF | .NET 8 LTS |
| UI パターン | MVVM | CommunityToolkit.Mvvm |
| Mumble | MumbleSharp | 2.0.1 |
| WebSocket | System.Net.WebSockets | .NET 8 組み込み |
| DI | Microsoft.Extensions.DependencyInjection | .NET 8 組み込み |
| 設定永続化 | System.Text.Json | .NET 8 組み込み |

## ディレクトリ構成

```
vc-app/
├── CLAUDE.md
├── RustPVC.sln
├── RustPVC.csproj
├── App.xaml / App.xaml.cs
├── Views/
│   ├── MainWindow.xaml / .cs
│   ├── VolumePanel.xaml / .cs       # プレイヤー一覧・スライダー
│   └── SettingsWindow.xaml / .cs    # 接続設定
├── ViewModels/
│   ├── MainViewModel.cs
│   ├── PlayerVolumeViewModel.cs
│   └── SettingsViewModel.cs
├── Models/
│   ├── PlayerState.cs               # 座標・方向・状態
│   ├── Vec3.cs
│   └── AudioSettings.cs
├── Services/
│   ├── VcControlService.cs          # WS接続・状態受信
│   ├── MumbleService.cs             # Mumble接続・Volume/Pan制御
│   ├── ProximityAudioEngine.cs      # 減衰・指向性計算
│   └── AuthService.cs              # トークン・セッション管理
└── Core/
    ├── DistanceAttenuation.cs       # 距離減衰アルゴリズム
    ├── DirectionalAudio.cs          # 指向性(パン)アルゴリズム
    └── AppSettings.cs               # 設定永続化 (JSON)
```

## UIレイアウト仕様

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

### UIルール
- ● = 生存（緑）、○ = 死亡（グレー）。死亡プレイヤーは音量0・スライダーグレーアウト
- 🔊 / 🔇 = ミュートボタン。ミュート中はスライダーもグレーアウト
- ⭐ = お気に入り。右クリックメニューで登録/解除。`AppSettings.json` に SteamID64 で永続化
- リストは距離近い順に自動ソート（お気に入りは最上部に固定）
- 最大聴取距離超は非表示（お気に入りのみ例外として表示を維持）

## ローカル状態管理（VcControlService.cs）

```csharp
// WS メッセージ受信時の処理
// state_full  → _localPlayers を全置換
// state_delta → changed をマージ、removed を削除
// 毎秒チェック → last_updated から STATE_TIMEOUT 秒超で自動削除

private Dictionary<string, PlayerState> _localPlayers = new();
private const float STATE_TIMEOUT = 5.0f;
```

自動再接続: 指数バックオフ（初回1秒、最大60秒）

## 距離減衰（DistanceAttenuation.cs）

設計書 §8 参照。デフォルトは逆二乗減衰。

```csharp
public static float Calculate(float distance, AttenuationMode mode,
    float refDist = 3.0f, float maxDist = 100.0f)

public enum AttenuationMode { InverseSquare, Linear, Logarithmic }
```

## 指向性・パン計算（DirectionalAudio.cs）

設計書 §9 参照。

```csharp
// 自分の向き(yaw)と相手の位置から -1.0(左) 〜 +1.0(右) のパン値を返す
public static float CalculatePan(Vec3 selfPos, float selfYawDeg, Vec3 otherPos)

// 等電力パンニングで L/R ゲインを計算
public static (float left, float right) PanToGain(float pan)
```

## 音量計算の優先順位

```
final_volume = attenuation × user_override × master_volume

attenuation   : DistanceAttenuation.Calculate() の結果 (0.0〜1.0)
user_override : UIスライダー値 (0%〜200%表示, 内部値0.0〜2.0, デフォルト100%)
               ※ 100%超は音声を増幅する（Mumble側クリッピングに注意）
master_volume : マスター音量 (0.0〜1.0, デフォルト1.0)

死亡プレイヤー → final_volume = 0.0 (強制)
ミュート中     → final_volume = 0.0 (強制)
```

## MumbleService.cs の責務

- MumbleSharp で Mumble サーバに接続・維持
- `ProximityAudioEngine` が計算した volume/pan を受け取り Mumble API に設定
- `username = SteamID64` で接続（認証用）
- Phase3: VoiceTarget（Whisper）の設定・解除

## 設定永続化（AppSettings.cs）

`%APPDATA%\RustPVC\settings.json` に保存。

```csharp
public class AppSettings
{
    public string VcControlUrl  { get; set; } = "wss://localhost:8766/client";
    public string MumbleHost    { get; set; } = "localhost";
    public int    MumblePort    { get; set; } = 64738;
    public string SteamId       { get; set; } = "";
    public string Token         { get; set; } = "";  // 保存可
    public float  MaxDistance   { get; set; } = 100.0f;
    public string AttenuationMode { get; set; } = "InverseSquare";
    public float  MasterVolume  { get; set; } = 1.0f;
    public HashSet<string> Favorites { get; set; } = new();  // SteamID64
}
```

## コーディングルール

- MVVM を厳守。View の code-behind にビジネスロジックを書かない
- Service クラスは interface を定義して DI で注入する（テスト可能にする）
- `async/await` を使う。`Task.Run` でUIスレッドをブロックしない
- WPF の UI 更新は `Application.Current.Dispatcher.InvokeAsync` 経由
- `INotifyPropertyChanged` は `CommunityToolkit.Mvvm` の `[ObservableProperty]` を使う

## トーク制御（v0.4.0実装）

### モード選択（設定画面）

| モード | 動作 |
|--------|------|
| OpenTalk | 常時マイクON。ミュートキーで無音化 |
| PTT | `+pvc.talk` 押下中のみ送信 |

### 状態管理ロジック

```csharp
// トークモード（設定永続化）
public enum TalkMode { OpenTalk, PTT }

// マイクON/OFF の最終判定（優先順位順）
bool IsMicActive()
{
    if (mute_active) return false;          // ミュート最優先
    if (mode == TalkMode.PTT) return ptt_active;
    return true;                             // OpenTalk は常時ON
}

// 状態更新（VC Control からのイベントで呼び出し）
void OnPvcCommand(string cmd)
{
    switch (cmd)
    {
        case "+pvc.talk":  ptt_active  = true;  break;
        case "-pvc.talk":  ptt_active  = false; break;
        case "pvc.mute":   mute_active = !mute_active; break; // トグル
        case "+pvc.mute":  mute_active = true;  break;
        case "-pvc.mute":  mute_active = false; break;
    }
    ApplyMicState(IsMicActive());
}
```

### AppSettings への追加

```csharp
public TalkMode TalkMode { get; set; } = TalkMode.OpenTalk;
```

## Phase0 でやること

1. プロジェクト作成・NuGet パッケージ追加（MumbleSharp, CommunityToolkit.Mvvm）
2. MumbleSharp で Mumble サーバに接続できること
3. 手動入力した SteamID で `RustPVC-Main` チャンネルに参加できること
4. 2台のアプリで音声通話できること（音量制御なし）

## Phase1 でやること

1. `VcControlService` 実装（WS接続・state受信・ローカル状態管理）
2. `DistanceAttenuation` / `DirectionalAudio` 実装（単体テスト付き）
3. `ProximityAudioEngine` が計算結果を `MumbleService` へ渡す
4. 基本的な WPF ウィンドウとプレイヤーリスト表示

## Phase2 でやること

1. 認証フロー完全実装（トークン入力・セッション管理）
2. 個別音量スライダー・ミュートボタン UI
3. お気に入り機能
4. 自動再接続（指数バックオフ）

## Phase3 でやること（将来）

1. VoiceTarget（Whisper）API 実装
2. バンドパスフィルタ（無線・電話音質）
3. MumbleSharp fork の ChannelListener API 呼び出し
4. 電話通話・無線 PTT の状態管理

## 注意事項

- MumbleSharp の `Volume` API が期待通り動くか Phase0 で必ず確認する
  → 動作しない場合は fork して修正する必要がある
- `.NET 8 WPF` は Windows のみ対応（Mac/Linux 非対応）
- `settings.json` に Token を保存するため、ファイルのアクセス権に注意

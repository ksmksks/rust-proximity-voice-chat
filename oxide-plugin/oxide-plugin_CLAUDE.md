# oxide-plugin — Claude Code 指示書

## 概要

Rust サーバ上で動作する Oxide/uMod プラグイン。
プレイヤーの座標・方向・状態を 20Hz で VC Control Server へ送信する。
距離計算・音量計算・クライアント側への直接アクセスは一切行わない。

## 技術スタック

| 項目 | 採用 |
|------|------|
| 言語 | C# (.NET Framework 4.x) |
| フレームワーク | Oxide/uMod 最新安定版 |
| ファイル | 単一ファイル `RustProximityVoiceChat.cs` |
| WebSocket ライブラリ | Oxide 組み込みの `WebSocketClient` または `System.Net.WebSockets` |

## ファイル構成

```
oxide-plugin/
├── CLAUDE.md
└── RustProximityVoiceChat.cs   # プラグイン本体（単一ファイル）
```

Oxide プラグインは単一 `.cs` ファイルが標準。分割しない。

## プラグイン基本構造

```csharp
using Oxide.Core;
using Oxide.Core.Plugins;
using UnityEngine;
using System.Collections.Generic;

namespace Oxide.Plugins
{
    [Info("RustProximityVoiceChat", "RustPVC", "1.0.0")]
    [Description("Proximity voice chat integration for RustPVC")]
    public class RustProximityVoiceChat : RustPlugin
    {
        // 設定クラス
        private PluginConfig _config;

        // 送信タイマー（20Hz = 0.05秒間隔）
        private Timer _broadcastTimer;

        // WebSocket接続
        private WebSocket _ws;

        void OnServerInitialized() { ... }
        void Unload() { ... }
        void OnPlayerConnected(BasePlayer player) { ... }
        void OnPlayerDisconnected(BasePlayer player, string reason) { ... }

        // Phase3: 無線PTT
        // void OnServerCommand(ConsoleSystem.Arg arg) { ... }
    }
}
```

## 設定ファイル（oxide/config/RustProximityVoiceChat.json）

```json
{
  "VcControlUrl": "ws://localhost:8765/oxide",
  "OxideToken": "CHANGE_ME",
  "BroadcastHz": 20,
  "ServerId": "rust-main-01"
}
```

設定値はハードコードしない。必ず `PluginConfig` クラスから読み込む。

## 送信フォーマット（設計書 §3 参照）

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

## 座標・方向の取得方法

```csharp
// 座標
Vector3 pos = player.transform.position;

// 方向（eyes の rotation から Euler 角を取得）
Vector3 euler = player.eyes.rotation.eulerAngles;
float yaw   = euler.y;          // 水平方向(0〜360度)
float pitch = -euler.x;         // 仰俯角（Unityは反転しているため負にする）
// pitch は -90〜90 度に clamp する
pitch = Mathf.Clamp(pitch, -90f, 90f);

// 生死
bool alive = player.IsAlive();

// チームID（チームなしの場合は null）
ulong? teamId = player.currentTeam != null ? player.currentTeam.teamID : (ulong?)null;

// SteamID
string steamId = player.UserIDString;  // SteamID64 の文字列
```

## 送信タイマー実装

```csharp
// 20Hz = 0.05秒ごとに実行
_broadcastTimer = timer.Every(1f / _config.BroadcastHz, BroadcastFrame);

private void BroadcastFrame()
{
    // 接続中のプレイヤーのみ取得
    var players = BasePlayer.activePlayerList;
    if (players.Count == 0) return;

    // JSON組み立て → WebSocket送信
    // ...
}
```

## WebSocket 接続管理

- 起動時に `OnServerInitialized` で接続
- 切断時は指数バックオフで再接続（最大60秒間隔）
- `Authorization: Bearer {OxideToken}` ヘッダを付与
- 送信失敗時はログ出力してスキップ（サーバを止めない）

## `/vctoken` コマンド（Phase1実装）

```csharp
[ChatCommand("vctoken")]
private void CmdVcToken(BasePlayer player, string command, string[] args)
{
    string steamId = player.UserIDString;
    long timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
    string token = GenerateHmacToken(steamId, timestamp);
    // チャット欄に表示（本人にのみ見える）
    player.ChatMessage($"[RustPVC] Your token: {token}\nExpires in 5 minutes.");
}
```

## トーク制御フック（v0.4.0実装）

```csharp
// OnServerCommand で以下のコマンドを検知し、VC Control へ送信する
// コマンド名は pvc. プレフィックスで他プラグインと衝突回避

object OnServerCommand(ConsoleSystem.Arg arg)
{
    if (arg.Connection == null) return null;
    var player = arg.Connection.player as BasePlayer;
    if (player == null) return null;

    string cmd = arg.cmd.FullName;
    string steamId = player.UserIDString;

    switch (cmd)
    {
        case "+pvc.talk":  SendTalkEvent(steamId, "talk_start");  break;
        case "-pvc.talk":  SendTalkEvent(steamId, "talk_stop");   break;
        case "pvc.mute":   SendTalkEvent(steamId, "mute_toggle"); break;
        case "+pvc.mute":  SendTalkEvent(steamId, "mute_start");  break;
        case "-pvc.mute":  SendTalkEvent(steamId, "mute_stop");   break;
    }
    return null; // デフォルト動作は維持する
}

// VC Control へのイベント送信（frame とは別の即時メッセージ）
private void SendTalkEvent(string steamId, string eventType)
{
    var payload = JsonConvert.SerializeObject(new {
        type = "talk_event",
        steam_id = steamId,
        event = eventType,
        timestamp_ms = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()
    });
    _ws.Send(payload);
}
```

## Phase3: 無線PTT フック

```csharp
// +pvc.radio / -pvc.radio コマンドを受信して radio_transmitting フラグを管理
// OnServerCommand フックで arg.cmd.FullName を確認する
// TODO(phase3): 無線PTT実装
```

## Phase0 でやること

1. プラグインが Oxide にロードされてエラーが出ないこと
2. `OnServerInitialized` でログ出力のみ（WS接続は後回し）
3. `timer.Every` でプレイヤーの座標をサーバコンソールにログ出力

## Phase1 でやること

1. WebSocket 接続実装
2. 20Hz の `frame` 送信
3. `/vctoken` コマンド実装（HMAC生成）
4. 切断時の再接続処理

## 注意事項

- `BasePlayer.activePlayerList` の反復中に例外が発生しても送信処理全体を止めない
- JSON 生成は `Oxide.Core.Libraries.Covalence` の `JsonConvert` または `Newtonsoft.Json` を使う
- サーバのメインスレッドをブロックしない（WS送信は非同期で行う）
- プラグインのアンロード時に必ず WebSocket を閉じ、タイマーを破棄する

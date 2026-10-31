# Observability Design

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/observability-requirements.md`（NFR7.x）、`reliability-requirements.md`、`scalability-requirements.md`。

## 1. メトリクスの収集

| メトリクス（名前空間 `Minecraft`） | 送信元 | 間隔 | ディメンション |
|---|---|---|---|
| `ServerUp` / `PlayersOnline` | `health.sh`（server list ping） | 1 分 | `Server=prod` |
| `BackupFailures` / `BackupSizeBytes` / `BackupDurationSeconds` / `BackupBucketBytes` | `backup-*.sh` / `stop.sh` | 実行ごと | `Server=prod`, `Kind=hourly\|stop` |
| `disk_used_percent` | CloudWatch Agent（`metrics_namespace` を `Minecraft` に設定） | 1 分 | `path=/srv/minecraft` |
| `StartupDurationSeconds` | start.yml（Job Summary と SNS 本文） | 起動ごと | — |

- ディメンションにはインスタンス ID を使いません。置き換えでメトリクスが途切れないように、固定値 `Server=prod` にします。

## 2. アラームとイベント

| 名前 | 種別 | 条件 | 欠測の扱い | 宛先 |
|---|---|---|---|---|
| `backup-failed` | CloudWatch アラーム | `BackupFailures` Sum ≥ 1（5 分） | `notBreaching`（送信がない＝実行がない） | SNS |
| `disk-high` | CloudWatch アラーム | `disk_used_percent` ≥ 80（15 分） | `notBreaching`（停止中） | SNS |
| `backup-bucket-large` | CloudWatch アラーム | `BackupBucketBytes` ≥ 80 GB | `notBreaching` | SNS |
| 無応答・ホストの固着・12 時間の上限 | watchdog Lambda | reliability-design.md §5 | 稼働中の欠測は異常 | SNS |
| 起動完了・手動停止・自動停止・MOD 失敗 | ホスト上のスクリプト（`app-server` の `sns:Publish`）が SNS に送る | — | — | SNS |
| 起動失敗（ホストに届かない場合を含む）・スモークテスト失敗 | start.yml / deploy.yml（`ci-ops` / `ci-apply` の `sns:Publish`）が SNS に送る | — | — | SNS |
| 予算 | Budgets | 80% / 100%（実績と予測） | — | SNS |

- SNS のメッセージには、属性 `severity`（`info` / `warn` / `error`）と `event` を付けます。notifier はこれを見て、色（🟢 🔵 🟡 🔴）と絵文字を決めます。
- メールは SNS の購読で届くので、すべてのイベントが届きます。
  - 成功系をメールで受け取らないようにするため、購読にサブスクリプションフィルター（`severity` が `warn` / `error`）を付けます。
- Discord に送る成功系は、起動完了・手動停止・自動停止だけです（requirements FR8.2 の変更どおり）。毎時バックアップの成功は送りません。

## 3. 通知メッセージの形式

- SNS の本文は JSON で、`event`、`severity`、`occurred_at`（ISO 8601、UTC）、`fields`（キーと値の一覧）を持たせます。
- notifier は、これを Discord の Embed（タイトル、色、フィールド、JST の時刻）に変換します。本文の検査（識別子の検出）は security-design.md §4 のとおりです。

## 4. ログ

| ロググループ | 内容 | 保持 |
|---|---|---|
| `/minecraft/prod/server` | コンテナのログ（Docker の `awslogs` ドライバー） | 14 日 |
| `/minecraft/prod/scripts` | journald から CloudWatch Agent で送るスクリプトのログ | 14 日 |
| `/aws/lambda/${prefix}-app-watchdog` / `-notifier` | Lambda のログ | 14 日 |

- スクリプトは `logger -t mc-<name>` で `key=value` 形式の 1 行ログを出します（例: `event=backup kind=hourly result=ok bytes=…`）。
- 起動から停止までの 1 セッションに `session_id`（起動時に生成する UUID）を付け、メトリクス以外のログと SNS 本文に含めます。これで、1 回の稼働を追跡できます。

## 5. ダッシュボード

- 作りません。確認は Discord の履歴と、CloudWatch のメトリクスとログで行います。

## Sources

- `nfr-requirements/observability-requirements.md` NFR7.1〜NFR7.16
- `nfr-requirements/scalability-requirements.md` NFR2.8、NFR2.9

## Assumptions & Open Questions

- メールの購読にはサブスクリプションフィルターを付け、`warn` / `error` だけを通す。成功系は Discord だけに送る（承認前の確認で本人が決定）。

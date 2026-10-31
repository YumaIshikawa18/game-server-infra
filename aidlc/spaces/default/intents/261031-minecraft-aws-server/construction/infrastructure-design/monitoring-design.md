# Monitoring Design

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/observability-design.md`、`reliability-design.md`、`scalability-design.md`、`logical-components.md`。

## Metrics & KPIs

| Metric | Source | Threshold | Why it matters |
|---|---|---|---|
| `Minecraft/ServerUp` | `health.sh`（1 分ごと、server list ping） | 稼働中に 0 または欠測が 60 分続いたら停止 | ヘルス指標。無応答の判定（NFR7.1, NFR7.9） |
| `Minecraft/PlayersOnline` | `health.sh` | 0 が 30 分続いたら自動停止 | 課金の抑制（NFR7.2） |
| `Minecraft/BackupFailures` | `backup-hourly.sh` / `stop.sh` | 1 以上で通知 | エラー指標（NFR7.3） |
| `Minecraft/BackupSizeBytes`、`BackupDurationSeconds` | 同上 | 参考値（アラームなし） | 容量の推移の把握 |
| `Minecraft/BackupBucketBytes` | `backup-hourly.sh` | 80 GB 以上で警告 | コスト（NFR2.9） |
| `Minecraft/disk_used_percent`（path=/srv/minecraft） | CloudWatch Agent | 80% 以上が 15 分で警告 | 容量（NFR2.8） |
| `AWS/EC2 StatusCheckFailed` | EC2 | 1 が 15 分続いたら watchdog が停止 | ホストの異常 |
| 起動所要時間 | start.yml の Job Summary と SNS の本文 | 10 分超でワークフロー失敗 | NFR3.1 |

## Alerts

| Alert | Condition | Severity | Routes to |
|---|---|---|---|
| `mc-backup-failed` | `BackupFailures` Sum ≥ 1（期間 5 分、1/1） | error | `alerts` → Discord ＋ メール |
| `mc-disk-high` | `disk_used_percent` ≥ 80（期間 5 分、3/3） | warn | `alerts` → Discord ＋ メール |
| `mc-backup-bucket-large` | `BackupBucketBytes` Max ≥ 80 GiB（期間 1 時間、1/1） | warn | `alerts` → Discord ＋ メール |
| watchdog 強制停止 | reliability-design.md §5 の (a)〜(c) | error | Lambda → SNS → Discord ＋ メール |
| 起動失敗 / MOD 取得失敗 | start.yml の失敗、mod-sync の失敗 | error | SNS → Discord ＋ メール |
| スモークテスト失敗 | deploy.yml の apply 後の確認が失敗 | error | SNS → Discord ＋ メール |
| 予算 80% / 100% | Budgets（実績・予測） | warn / error | `alerts` → Discord ＋ メール |
| 起動完了 / 手動停止 / 自動停止 | スクリプトとワークフローからのイベント | info | SNS → Discord のみ（メールはフィルタで除外） |

- アラーム名は、識別子チェックに当たらない固定の名前にします。アラームの説明には runbook（operation フェーズで作成）の節名を入れます。

### 通知の経路と severity の決め方

| 送り手 | トピック | severity の決め方 | Discord | メール |
|---|---|---|---|---|
| ホスト上のスクリプト、watchdog、start / stop / restore / deploy ワークフロー | `events` | 送り手がメッセージ属性 `severity` を付ける（info / warn / error） | 全件 | warn / error のみ（購読フィルタで絞る） |
| CloudWatch アラーム | `alerts` | notifier がアラーム名から決める（`mc-backup-failed` は error、`mc-disk-high` と `mc-backup-bucket-large` は warn）。`OK` への復旧は info | 全件 | 全件（フィルタなし） |
| AWS Budgets | `alerts` | notifier が閾値から決める（80% は warn、100% は error） | 全件 | 全件（フィルタなし） |

- notifier は、メッセージの形（独自 JSON、CloudWatch アラームの JSON、Budgets のテキスト）を判定して処理を分けます。形が判別できないメッセージは、そのまま warn として送ります（落とさない）。この判定は pytest で検証します。

## SLIs / SLOs

| SLI | SLO target | Measurement window |
|---|---|---|
| start ワークフローの成功率（成功 / 実行） | 95% 以上（目安。計測の仕組みは作らず、Actions の履歴で確認する） | 30 日 |
| 起動所要時間（start の開始から接続可能になるまで） | 実行の 100% で 10 分以内（超えたら失敗として扱う） | 実行ごと |
| データ損失の上限（RPO） | 稼働中の障害で失う時間は最大 1 時間（毎時バックアップの成功で担保。失敗はアラーム） | 稼働中 |

- 常時稼働の可用性 SLO は設けません（NFR9.1）。

## Logs & Tracing

| ロググループ | 送信元 | 保持 | 備考 |
|---|---|---|---|
| `/minecraft/prod/server` | compose の `logging.driver: awslogs` | 14 日 | プレイヤー名を含むため、保持期間を短くする（NFR7.16） |
| `/minecraft/prod/scripts` | journald から CloudWatch Agent で送信 | 14 日 | `key=value` 形式、`session_id` 付き |
| `/aws/lambda/<watchdog>` / `/aws/lambda/<notifier>` | Lambda | 14 日 | 関数名は変数で決め、ロググループも Terraform で先に作る |

- 分散トレーシングは使いません（構成要素が少なく、`session_id` で 1 回の稼働を追えるため）。
- ダッシュボードは作りません（observability-design.md §5）。

## Sources

- `nfr-design/observability-design.md` §1〜§5、`reliability-design.md` §4〜§5、`scalability-design.md`

## Assumptions & Open Questions

- [assumption] アラームの評価期間と回数は上表のとおりとする。

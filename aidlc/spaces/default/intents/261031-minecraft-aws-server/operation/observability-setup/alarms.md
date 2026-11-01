# アラームと通知

閾値と通知先は `../../construction/infrastructure-design/monitoring-design.md` のとおりで、Terraform の `modules/monitoring/`、`modules/notifier/`、`modules/watchdog/` に実装済みです。本番へのデプロイで作成済みで、今回の段階でインフラは変更していません。

## CloudWatch アラーム

実際の名前は `<prefix>-<種類>` です。欠測は正常として扱います（停止中はメトリクスが届かないため）。

| 種類 | 条件 | 重大度 | 通知先 |
|---|---|---|---|
| `backup-failed` | `BackupFailures` の合計が 1 以上（5 分、1 回） | error | `alerts` → Discord とメール |
| `disk-high` | `disk_used_percent` が 80 以上（5 分、3 回連続） | warn | `alerts` → Discord とメール |
| `backup-bucket-large` | `BackupBucketBytes` が 80 GiB 以上（1 時間、1 回） | warn | `alerts` → Discord とメール |

## その他の通知

| 通知 | 条件 | 重大度 | 通知先 |
|---|---|---|---|
| 予算 | AWS Budgets の実績と予測が 80% / 100% を超える | warn / error | `alerts` → Discord とメール |
| 強制停止 | watchdog が無応答、ホストの異常、12 時間超を検知する | error | `events` → Discord とメール |
| 起動の失敗、MOD の失敗、スモークテストの失敗 | スクリプトや workflow が失敗する | error | `events` → Discord とメール |
| 起動完了、手動停止、自動停止 | 正常なイベント | info | `events` → Discord のみ |

エスカレーション先は本人だけです（1 名体制）。対応手順は `../deployment-pipeline/rollback-runbook.md` を使います。閾値は、容量や予算の上限に達する前に気づけるよう、80% に設定しています。

## 実動作の確認（2026-11-01）

| 確認項目 | 方法 | 結果 |
|---|---|---|
| アラーム通知（ALARM / OK） | 13:01:33Z に `disk-high` を手動で ALARM にし、13:02:18Z に自動で OK へ戻った | **本人が Discord とメールの両方で受信を確認**（Q3） |
| 無人 30 分の自動停止 | 本人のログアウト後、13:29:40Z に `event=auto_stop reason=idle` を記録 | **成功**。13:31:08Z までに EC2 が `stopped` |
| 停止時のバックアップ | S3 の `stop/` を確認 | **成功**。13:29:39Z に 1 件保存、約 126 MiB |
| 毎時バックアップ | S3 の `hourly/` を確認 | **成功**。13:00:22Z に 1 件保存、約 126 MiB |
| 自動停止の通知 | notifier の実行ログを確認 | 13:29:42Z に実行され、エラーログは 0 件。本人が承認時に Discord での受信も問題なしと回答 |
| アラームの状態 | 確認の後に取得 | 3 件すべて `OK` |

## 確認していないこと

Q1 の範囲外としたものです。いずれも実害が出るまで動作の裏付けがありません。

- Restore workflow による復元
- watchdog の強制停止
- AWS Budgets の通知
- 起動失敗やスモークテスト失敗の通知

## 設計との差異

動作に問題はありませんが、`../../construction/` の設計書は実装と異なります。

| 項目 | 設計書 | 実装 |
|---|---|---|
| カスタムメトリクスのディメンション | `Server=prod` など（`observability-design.md` §1） | ディメンションなし。`disk_used_percent` だけ `path` と `fstype` |
| ロググループ名 | `/minecraft/prod/...`、`/aws/lambda/...` | `/<prefix>/server`、`scripts`、`notifier`、`watchdog` |
| アラーム名 | `mc-` で始まる固定の名前 | `<prefix>-<種類>` |

## セキュリティ

通知本文とログの扱いは `../../construction/nfr-design/security-design.md` §4 のとおりです。識別子やプレイヤー名を公開の場に出しません。今回の変更で IAM、ネットワーク、暗号化の設定は変えていません。

## Sources

- `../../construction/infrastructure-design/monitoring-design.md` Alerts
- `../../construction/infrastructure-design/infrastructure-specification.md`
- `../../construction/nfr-design/observability-design.md` §1、§2
- `../../construction/nfr-design/reliability-design.md` §4、§5
- `../../construction/nfr-design/performance-design.md`
- `../../construction/nfr-design/security-design.md` §4
- `../deployment-execution/health-check-report.md`
- `observability-setup-questions.md`（Q1、Q3、Q4）
- `modules/monitoring/main.tf`

## Assumptions & Open Questions

- notifier と watchdog の Lambda 自体には、エラー率のアラームがありません。phases/operation.md の「すべてのコンポーネントにヘルス指標とエラー率の指標を持たせる」を満たしていないおそれがあり、対応するかは本人の判断待ちです。notifier が止まると、その失敗を通知する経路もない点に注意が必要です。

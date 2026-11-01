# ヘルスチェック報告

確認日時は 2026-11-01 の 12:46 から 12:50Z ごろです。`personal` プロファイルからの読み取りで確認しました。識別子の値は記録していません。

| 対象 | 確認内容 | 結果 |
|---|---|---|
| EC2 | インスタンスの状態、インスタンスとシステムのステータス | `running` / `ok` / `ok` |
| Elastic IP | インスタンスのパブリック IP との一致 | 一致 |
| SSM | エージェントの接続状態 | `Online` |
| CloudWatch アラーム | `backup-failed`、`disk-high`、`backup-bucket-large` | すべて `OK` |
| SNS のメール購読 | 確認待ちの有無 | 2 件とも確認待ちなし |
| Lambda | `notifier` と `watchdog` の存在 | 2 関数あり |
| 運用ロック | ロックの有無 | なし（404） |
| bootstrap | Q15 適用後の再 plan | 差分 0 件 |
| prod | apply 後の plan | 差分 0 件 |

## 未確認の項目

- Discord への通知が実際に届くこと
- メール通知が実際に届くこと
- バックアップが S3 へ保存され、そこから復元できること
- watchdog が条件どおりに停止すること

これらは今回のデプロイの完了条件には含めていません。監視の確認は、後続の Observability Setup で扱うのがよいと考えます。

## コスト

確認時点でインスタンスは稼働中です。使わないときは Stop workflow で停止します。停止を忘れても、プレイヤーが 0 人の状態が 30 分続けばホスト側で自動停止し、起動から 12 時間を超えれば watchdog が停止します。

## Sources

- `../environment-provisioning/environment-inventory.md`
- `../deployment-pipeline/rollback-runbook.md`
- `lambda/watchdog/`
- `modules/monitoring/main.tf`

## Assumptions & Open Questions

- 上記の未確認項目の確認時期は、本人の判断待ちです。

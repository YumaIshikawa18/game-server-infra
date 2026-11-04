# Health Check Report

確認日時: 2026-11-04T07:50Z 頃（4 回目の Start の後）

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/construction/build-and-test/test-results.md`

| 項目 | 結果 |
|---|---|
| インスタンスの状態 | `running` |
| EC2 のステータスチェック | インスタンス `ok`、システム `ok` |
| `ALARM` 状態の CloudWatch アラーム | 0 件 |
| `scripts` のログの `level=error`（2026-11-04T07:39Z 以降） | 0 件 |
| `scripts` のログの `start_failed`（2026-11-03T14:10Z 以降） | 0 件 |
| Start workflow | 4 回すべて成功 |
| Stop workflow | 3 回すべて成功 |
| Deploy workflow | 成功 |
| 2026-11-04T07:45Z の Stop のバックアップ | `backup_ok=true` |
| 起動の種類 | `boot_mode mode=normal` |
| クライアントからの接続とワールド | ご本人が確認 |

## 確認していないこと

- 2026-11-04T07:38Z 頃と 2026-11-03 の Stop の `backup_ok` は、ログを見ていません。どちらの Stop の workflow も成功です。
- バックアップからの実際の復元は行っていません。
- SLO は定めていません。Observability Setup はこのプランの対象外で、既存のアラームのままです。

# ダッシュボード

**CloudWatch ダッシュボードは作りません。** `../../construction/nfr-design/observability-design.md` §5 の決定どおりです。

## 理由

- 利用者は本人だけで、常時監視する運用ではありません。
- サーバーは使うときだけ起動するので、停止中はグラフのほとんどが欠測になります。
- 異常は Discord とメールに通知されます（`alarms.md`）。

## 代わりに見る場所

| 知りたいこと | 見る場所 |
|---|---|
| 起動、停止、異常の履歴 | Discord の通知チャンネル |
| 起動やデプロイの結果 | GitHub Actions の実行履歴と Job Summary |
| プレイヤー数、稼働状況 | CloudWatch メトリクス `Minecraft/PlayersOnline`、`Minecraft/ServerUp` |
| ディスクとバックアップの容量 | CloudWatch メトリクス `Minecraft/disk_used_percent`、`Minecraft/BackupBucketBytes` |
| 詳しい調査 | CloudWatch Logs Insights（`log-queries.md`） |
| 月のコスト | AWS Budgets |

## 見直す条件

複数人で運用するようになったときや、調査で毎回同じグラフを見るようになったときに、作成を検討します。

## Sources

- `../../construction/nfr-design/observability-design.md` §1、§5
- `../../construction/nfr-design/performance-design.md`
- `../../construction/nfr-design/security-design.md`
- `../../construction/nfr-design/reliability-design.md`
- `../../construction/infrastructure-design/monitoring-design.md`
- `../../construction/infrastructure-design/infrastructure-specification.md`
- `observability-setup-questions.md`

## Assumptions & Open Questions

None.

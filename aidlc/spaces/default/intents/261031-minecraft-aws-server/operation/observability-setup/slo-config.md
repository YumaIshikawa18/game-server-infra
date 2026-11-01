# SLO の設定

`../../construction/infrastructure-design/monitoring-design.md` の SLI / SLO を、運用で使う形にまとめます。計測の仕組みは新しく作らず、既存の履歴とメトリクスで確認します。

## SLO

| SLI | 目標 | 期間 | 確認方法 | 超えたときの扱い |
|---|---|---|---|---|
| Start workflow の成功率 | 95% 以上 | 直近 30 日 | GitHub Actions の実行履歴 | 失敗の原因を調べ、再発防止を検討する |
| 起動所要時間 | 実行の 100% で 10 分以内 | 実行ごと | Start workflow の Job Summary | 10 分を超えた実行は失敗として扱い、エラーとして通知する |
| データ損失の上限（RPO） | 稼働中の障害で失うのは最大 1 時間 | 稼働中 | `Minecraft/BackupFailures` | 失敗 1 回で `backup-failed` が発報する |

常時稼働の可用性 SLO は設けません（NFR9.1）。サーバーは使うときだけ起動するためです。

## SLO を守るためのしくみ

| SLO | 手前で気づくためのしくみ |
|---|---|
| 成功率、起動所要時間 | 起動の待機が 10 分を超えると workflow が失敗し、通知します（`../../construction/nfr-design/performance-design.md`） |
| RPO | バックアップが 1 回失敗した時点でアラームが発報します。次の毎時バックアップで失敗が続く前に対応できます（`../../construction/nfr-design/reliability-design.md` §3） |

## エラーバジェット

成功率 95% は、起動 20 回のうち 1 回までの失敗を許容する目安です。個人利用で実行回数が少ないため、バーンレートのアラートは設けません。

## Sources

- `../../construction/infrastructure-design/monitoring-design.md` SLIs / SLOs
- `../../construction/infrastructure-design/infrastructure-specification.md`
- `../../construction/nfr-design/performance-design.md`
- `../../construction/nfr-design/reliability-design.md` §3
- `../../construction/nfr-design/security-design.md` §4
- `observability-setup-questions.md`

## Assumptions & Open Questions

- [assumption] 成功率 95% は目安とし、Actions の履歴を必要なときに確認します（`monitoring-design.md` の決定どおり）。

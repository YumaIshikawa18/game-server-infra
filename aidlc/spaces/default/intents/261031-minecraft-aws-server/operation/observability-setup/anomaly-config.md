# 異常検知の設定

**CloudWatch の異常検知（Anomaly Detection）は使いません。** 固定の閾値で十分と判断しました。

## 理由

- 使うときだけ起動するので、学習の元になる連続したデータが貯まりません。
- 見張りたいのは、容量 80%、バックアップの失敗、予算のように、判断基準がはっきりした値です。
- 個人利用で通知を受けるのは本人だけなので、誤検知のコストに対して得られるものが小さいです。

## 代わりのしくみ

| 異常 | 検知方法 | 詳細 |
|---|---|---|
| ディスクの逼迫 | `disk-high`（80% 以上が 15 分） | `alarms.md` |
| バックアップ容量の増加 | `backup-bucket-large`（80 GiB 以上） | `alarms.md` |
| コストの増加 | AWS Budgets（実績と予測の 80% / 100%） | `alarms.md` |
| 長時間の稼働 | watchdog（起動から 12 時間） | `../../construction/nfr-design/reliability-design.md` §5 |

## 見直す条件

毎日稼働するようになり、固定の閾値では気づけない異常が実際に起きたときに検討します。

## Sources

- `../../construction/infrastructure-design/monitoring-design.md` Metrics & KPIs、Alerts
- `../../construction/infrastructure-design/infrastructure-specification.md`
- `../../construction/nfr-design/reliability-design.md` §5
- `../../construction/nfr-design/performance-design.md`
- `../../construction/nfr-design/security-design.md`
- `observability-setup-questions.md`

## Assumptions & Open Questions

- [assumption] 使わない判断は、ダッシュボードなどと同じく固定の閾値で足りるという判断によるものです。設計書に明記された決定ではないため、サマリー確認で本人に確認しました。

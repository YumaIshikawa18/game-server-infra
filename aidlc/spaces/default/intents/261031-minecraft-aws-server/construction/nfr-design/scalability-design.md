# Scalability Design

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-requirements/scalability-requirements.md`（NFR1.1, NFR2.6〜NFR2.9）、`performance-requirements.md`。

## 縦のスケール（NFR2.6）

- `instance_type` を変える PR を作り、承認付きで apply します。インスタンスは置き換えまたは停止後の変更になり、置き換え前の保存・バックアップ・停止は reliability-design.md の「置き換え時の保護」で行います。
- ワールドは別の EBS（`/srv/minecraft`）に置いているので、置き換え後にそのまま付け直されます。

## 人数（NFR2.7）

- `max-players` は `config/server.properties` で管理し、既定値は 10 です。

## ワールドとバックアップの容量（NFR2.8, NFR2.9）

- ワールド用 EBS は `world_volume_size_gb` 変数（既定 30）で指定します。拡張は PR で値を上げて apply します。gp3 はオンラインで拡張できるので、起動時のスクリプトで `xfs_growfs` を実行します。
- CloudWatch Agent でディスク使用率を送り、80% を超えたら警告します（observability-design.md）。
- バックアップバケットのサイズは、S3 Storage Lens ではなく、バックアップスクリプトが取得後に `ListObjectVersions` で合計して `BackupBucketBytes` として送ります。80 GB を超えたら警告します。

## コスト上限（NFR1.1）

| 対策 | 内容 |
|---|---|
| 稼働時間の抑制 | 無人で 30 分たつと自動停止、無応答が 60 分続くと強制停止、連続稼働 12 時間で watchdog が停止 |
| 固定費の把握 | Elastic IP と EBS は停止中も課金される。見積もりは scalability-requirements.md を参照 |
| 実績の監視 | Budgets の月 3,000 円（80% / 100%、予測含む）を SNS 経由で Discord とメールに通知 |
| NAT を使わない | NAT ゲートウェイ（月 5,000 円以上）を置かず、パブリックサブネットだけで構成する（[Q2]） |

## Sources

- `nfr-requirements/scalability-requirements.md`
- `nfr-design-questions.md` [Q2]

## Assumptions & Open Questions

- [assumption] バックアップバケットのサイズは、スクリプトで集計してカスタムメトリクスとして送る。

# Observability Setup — 質問

上流: `../../construction/nfr-design/performance-design.md`、`../../construction/nfr-design/security-design.md`、`../../construction/nfr-design/reliability-design.md`、`../../construction/infrastructure-design/monitoring-design.md`、`../../construction/infrastructure-design/infrastructure-specification.md`、`../deployment-execution/health-check-report.md`。

## 設計で決定済みのため質問しないこと

- ダッシュボードは作らない（`observability-design.md` §5）。
- 分散トレーシングは使わない（`monitoring-design.md`）。
- 常時稼働の可用性 SLO は設けない（NFR9.1）。
- ログの保持は 14 日。アラームの閾値と通知先は `monitoring-design.md` のとおり。

## Q1. [運用担当] 通知、バックアップ、自動停止の実動作をどこまで確認するか

デプロイの完了確認では、これらの実動作を確認していない。無人 30 分の自動停止が近いうちに起きる見込みなので、Discord への通知と停止時のバックアップはそれで確認できる。メールには warn / error だけが届くため、自動停止では確認できない。アラームを一時的に ALARM 状態にすれば確認でき、次の評価で元に戻る。

A. 自動停止を待って確認し、アラームを一時的に ALARM にしてメールと Discord も確認する（推奨）
B. 自動停止だけ確認する
C. A に加えて、Restore workflow による復元も試す
X. Other (please specify)

[Answer]: A. 自動停止を待って確認し、アラームを一時的に ALARM にしてメールと Discord も確認する（本人の回答、message 5c83adbf）。

## Q2. [運用担当] CloudWatch Logs Insights のクエリをどこに置くか

調査用のクエリ（1 回の稼働の追跡、バックアップの失敗、起動の失敗、強制停止）を用意する。

A. `log-queries.md` に記載するだけにする（推奨: インフラの変更とデプロイが不要）
B. Terraform で保存済みクエリとしても定義する（AWS コンソールからすぐ使える。PR とデプロイが必要）
X. Other (please specify)

[Answer]: A. `log-queries.md` に記載するだけにする（本人の回答、message 5c83adbf）。

## Consolidated Summary Confirmation

Does this all look correct before I generate the artifact?

- 自動停止を待って、停止、Discord 通知、停止時の S3 バックアップを確認する。
- アラームを一時的に ALARM にして、メールと Discord への通知を確認する。Restore による復元は試さない。
- Logs Insights のクエリは `log-queries.md` に記載するだけで、インフラは変更しない。
- ダッシュボード、分散トレーシング、異常検知、常時稼働の可用性 SLO は採用しない。
- アラームの閾値、通知先、ログの保持は `monitoring-design.md` のとおりとする。

- Looks correct
- Request changes

[Answer]: Looks correct

## Q3. [運用担当] テスト通知の到着確認

2026-11-01T13:01:33Z に `disk-high` アラームを手動で ALARM にし、13:02:18Z に OK へ戻った。notifier は 2 回とも実行され、SNS の配信失敗は 0 件。Discord とメールに実際に届いたかは本人にしか確認できない。

A. Discord とメールの両方に届いた
B. 片方、または両方に届いていない
X. Other (please specify)

[Answer]: A. Discord とメールの両方に届いた（本人の回答、message d5fc8f81）。

## Q4. [運用担当] 自動停止の確認

`PlayersOnline` が 1 のため、無人 30 分のカウントが始まっていない。本人がログアウトしてから約 30 分後に自動停止する。

A. ログアウトした
B. まだプレイを続ける
X. Other (please specify)

[Answer]: A. ログアウトした（本人の回答、message d5fc8f81）。

## Q5. [運用担当] FR3.5（クライアント向け MOD 手順書）の扱い

Observability Setup の途中で、本人の質問をきっかけに FR3.5 の未実装を確認した。手順書と、MOD 一覧との食い違いを検出する CI チェックがなく、要件定義より後の記録にも FR3.5 が出てこない。

A. 今の作業の続きで対応する（Observability Setup の承認後に別の PR で対応し、他の要件の漏れも確認する）
B. 別の作業として後で対応する
X. Other (please specify)

[Answer]: A. 今の作業の続きで対応する（本人の回答、message fe511779）。

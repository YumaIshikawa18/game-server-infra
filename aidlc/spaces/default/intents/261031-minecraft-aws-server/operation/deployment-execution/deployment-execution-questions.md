# Deployment Execution — 質問

上流: `../deployment-pipeline/cd-config.md`、`../deployment-pipeline/deployment-strategy.md`、`../deployment-pipeline/rollback-runbook.md`、`../environment-provisioning/environment-inventory.md`。infra スコープのため Build and Test の結果はなく、検証は Environment Provisioning の必須チェック 11 件と実環境の plan で代える。

## デプロイ前の確認（2026-11-01、読み取りのみ）

| 項目 | 状態 |
|---|---|
| AWS の認証（personal、東京） | 成功。アカウント `********1714` |
| PR #3 の必須チェック 11 件（最新コミット `83cca79`） | すべて成功 |
| bootstrap と実環境の差分 | 0 件 |
| GitHub の Secrets 9 件・Variables 2 件・Environments `prod` / `ops` | 設定済み |
| master の Branch protection の必須チェック | **未登録**（0 件） |
| master の承認ルール | 承認 1 件と Code Owner のレビューが必須。管理者には適用しない（バイパス可） |
| SSM の whitelist | **未登録** |
| SSM の Discord Webhook | 未登録 |
| データベースの移行 | なし（RDB を使わない） |
| 依存サービス | AWS のマネージドサービスだけ（初回なので、既存の稼働中サービスはない） |

## Q1. [リリースエンジニア] master の保護とセルフマージの方法

team.md では「必須チェックがすべて成功していれば、自分の PR をセルフマージしてよい」としている。今の master は承認 1 件と Code Owner のレビューが必須で、Code Owner は本人だけなので、自分では承認できない。管理者のバイパスでマージはできるが、バイパスは必須チェックも含めてすべてのルールを飛ばすため、チェックの強制にならない。

A. 承認数を 0 にして Code Owner のレビューを外し、必須チェック 11 件を登録して「管理者にも適用」をオンにする（推奨: team.md の取り決めどおり、チェックの成功だけがマージの条件になり、本人も飛ばせない）
B. 承認のルールは残し、必須チェック 11 件を登録して、マージは管理者のバイパスで行う（今の設定に近いが、バイパス時はチェックも強制されない）
X. Other (please specify)

[Answer]: X. 自分が管理者なので、セルフマージできる理解。（本人の言葉）→ 承認のルールは変えず、管理者のバイパスでセルフマージする。バイパスでは必須チェックも強制されないため、マージ前にチェックの全成功を目で確認する。必須チェック 11 件は結果を表示するために登録する

## Q2. [リリースエンジニア] Discord への通知

通知はメール（events の warn / error、alerts のすべて）と Discord の 2 経路の設計。Discord の Webhook が未登録のままだと、通知のたびに notifier Lambda が失敗する（メールには届く）。

A. apply の前に Discord の Webhook を SSM に登録する（推奨: 設計どおり両方に届く）
B. 当面はメールだけにする。Webhook が未登録のときは、notifier を失敗させずに「Discord は未設定」と記録して終わるよう、マージ前に変更する
X. Other (please specify)

[Answer]: A. apply の前に Discord の Webhook を SSM に登録する

## Q3. [リリースエンジニア] prod を承認するタイミング

apply すると EC2 がすぐに起動する。誰も接続しないまま 30 分たつと自動で停止する（バックアップ付き）。walking skeleton の完了条件は、Minecraft クライアントから接続できること。

A. マージ後、30 分以内にクライアントから接続できるときに prod を承認する（推奨: 起動したまま接続を確認でき、確認後は自動停止に任せられる）
B. 都合のよいときに承認する。自動停止したあとで、接続できるときに start ワークフローで起動して確認する
X. Other (please specify)

[Answer]: A. マージ後、30 分以内にクライアントから接続できるときに prod を承認する

## Q4. [リリースエンジニア] Codex のレビューとマージの順序

PR #3 には、push のたびに Codex のレビューが付き、これまでに 11 件の指摘を確認・修正した。最新コミット `83cca79` へのレビューは、まだ確認していない。

A. 最新コミットへの Codex のレビューを確認し、指摘があれば同じように確かめて直してからマージする（推奨: これまでの指摘の多くは実際の不具合だった）
B. 必須チェックが成功しているので、レビューを待たずにマージする
X. Other (please specify)

[Answer]: A. 最新コミットへの Codex のレビューを確認し、指摘があれば直してからマージする

## Sources

- `../deployment-pipeline/cd-config.md`、`deployment-strategy.md`、`rollback-runbook.md`
- `../environment-provisioning/environment-inventory.md`、`validation-report.md`
- team.md の Way of Working（セルフマージの条件）と Walking Skeleton（完了条件）
- GitHub API の読み取り（Branch protection、Secrets と Variables の名前のみ）、SSM の読み取り（パラメータの有無のみ）
- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches

## Consolidated Summary Confirmation

- master の承認ルールは変えず、管理者としてセルフマージする。マージ前に PR の必須チェック 11 件の全成功を確認する（バイパスはチェックも飛ばすため）。必須チェック 11 件は Branch protection に登録する。（Q1）
- apply の前に、whitelist と Discord の Webhook を SSM SecureString に登録する。（Q2）
- 最新コミットへの Codex のレビューを確認し、指摘があれば確かめて直してからマージする。（Q4）
- マージ後に deploy.yml の plan サマリーを確認し、30 分以内にクライアントから接続できるときに prod を承認する。（Q3）
- apply 後に、スモークテスト（mc-health-check）、メール購読の確認、クライアントからの接続（walking skeleton の完了条件）を確認する。失敗したら rollback-runbook.md に従う。
- データベースの移行はない。

この内容でデプロイを進めてよいですか？

- Looks correct
- Request changes

[Answer]: Looks correct

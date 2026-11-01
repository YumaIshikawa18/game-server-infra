# Environment Inventory

上流: `../../construction/infrastructure-design/infrastructure-specification.md`（構成・サービス・コスト）、`../deployment-pipeline/cd-config.md`（GitHub 側の設定、CD とホストの契約）。回答は `environment-provisioning-questions.md` の Q1〜Q8 と Consolidated Summary Confirmation。

この段階は、環境の準備と検証（PR #3 の必須チェック 11 件と、実環境に対する plan の通過）までで区切る（Q8）。`envs/prod` の apply、whitelist の登録、クライアントからの接続確認は Deployment Execution で行う。

識別子（アカウント ID、ロール ARN、バケット名、prefix、IP アドレス）はこの記録に書かない。値の置き場所だけを示す。

## 1. 環境の状態

| 環境 | 状態 | 管理 |
|---|---|---|
| `bootstrap`（state・CI 用 ID 基盤・ログ） | **構築済み**。本人の承認を得て、手元から personal で 3 回適用した。各回の適用後に再 plan して差分 0 件を確認 | 手元の local state（gitignore 済み） |
| `prod`（`envs/prod`） | **未構築**。実環境に対する plan は、手元（personal）と CI（ci-plan ロール）の両方で 追加 81 / 変更 0 / 削除 0 | S3 の remote state（ネイティブロック）。適用は deploy.yml から |
| GitHub | **設定済み**。Secrets 9 件、Variables 2 件、Environments `prod` / `ops` | 本人が設定（Secrets は値を表示しないスクリプトで登録） |

## 2. bootstrap で構築したリソース

| リソース | 内容 |
|---|---|
| state バケット | BPA、SSE-S3、バージョニング、TLS 必須、state キーの読み書きは本人と ci-plan / ci-apply だけ、`control/` の運用ロックの旧版は 7 日、`prevent_destroy`。アクセスログをログバケットの `state/` へ |
| ログバケット（Q3 で追加） | BPA、SSE-S3、ACL 無効、TLS 必須、保存 90 日。書き込みは S3 のログ配信（`state/`・`backup/`）と VPC フローログの配信（`flow/AWSLogs/<自アカウント>/`）だけ、いずれも自アカウントに限る |
| GitHub OIDC プロバイダー | 既存のものを変更せずに参照（`sts.amazonaws.com` の audience を postcondition で確認） |
| CI ロール 3 つ（`<prefix>-ci-plan` / `-ci-apply` / `-ci-ops`） | `aud` と `sub` を `StringEquals` で指定。`sub` は GitHub の immutable subject（owner と repo の ID 付き）で、plan は PR と master、apply は `environment:prod`、ops は `environment:ops`。セッション 1 時間 |
| apply 用の管理ポリシー 5 つ（state / compute / identity / storage / services） | `Project` タグ・リソース名の接頭辞・boundary 必須で絞る。`<prefix>-ci-*` への `iam:*` は Deny |
| permissions boundary（`<prefix>-ci-boundary`） | app ロールすべてに必須 |

## 3. prod で作るリソース（plan の 81 件）

| モジュール | 主なリソース | 件数 |
|---|---|---|
| `network` | VPC（/24）、公開サブネット、IGW、ルート、SG（25565/TCP のみ）、VPC フローログ（Q5） | 10 |
| `world_backup` | バックアップ・配布バケット（BPA、SSE-S3、バージョニング、TLS 必須、旧版 7 日、`prevent_destroy`、アクセスログを `backup/` へ） | 8 |
| `minecraft_server` | EC2（m7g.xlarge、IMDSv2、キーペアなし）、主 ENI と EIP（`prevent_destroy`）、ワールド EBS 30 GB（暗号化、`prevent_destroy`）、ホスト用ロール（boundary 付き）、SSM 文書 3 つ、ロググループ 2 つ（14 日）、配布ファイル 23 件 | 38 |
| `notifier` | SNS トピック 2 つ（events / alerts）、メール購読 2 つ、notifier Lambda と購読・権限、ロール、ロググループ | 14 |
| `watchdog` | watchdog Lambda、EventBridge Scheduler（5 分ごと）、ロール 2 つ（watchdog / scheduler、Q2）、ロググループ | 7 |
| `monitoring` | アラーム 3 つ（backup-failed / disk-high / backup-bucket-large）、月の予算（20 USD、Q6） | 4 |

- IAM ロールは、bootstrap の CI ロール 3 つと、prod の app ロール 4 つ（app-server / app-notifier / app-watchdog / app-scheduler）の合計 7 つ（Q2 で app-scheduler が加わり 6 → 7）。
- ゲームの設定（Minecraft 26.3、vanilla、MOD なし、server.properties 相当）は `envs/prod/main.tf` の `local.minecraft` にあり、PR で変更する（Q4、FR2.1）。イメージは `docker/compose.yml` で digest 固定。

## 4. ホスト上の構成

| 場所 | 内容 |
|---|---|
| `/srv/minecraft` | ワールド EBS（xfs、`nofail`）。Docker の data-root、`data/`、`mods-cache/`、ロック、RCON パスワード |
| `/opt/minecraft` | 起動ごとに S3 の `deploy/` から同期（スクリプト 9 本、systemd ユニット 7 つ、compose、設定、MOD 一覧、CloudWatch Agent 設定） |
| `/etc/minecraft` | `host.env`（0600）、起動前に作る `secrets.env`（0600。whitelist と RCON パスワード） |
| systemd | `mc-deploy-sync` → `boot-mode` → `mod-sync` → `minecraft`、`health.timer`（1 分）、`backup-hourly.timer`。docker とワールドを使うユニットはすべて `RequiresMountsFor=/srv/minecraft` |

## 5. 秘匿値と非公開の値の置き場所

| 値 | 置き場所 | 状態 |
|---|---|---|
| アカウント ID、prefix、バケット名、OIDC の subject | `bootstrap/*.auto.tfvars*`、`envs/prod/*.auto.tfvars.json`、`envs/prod/backend.hcl`（すべて gitignore 済み） | 用意済み |
| メールアドレス、EULA への同意、予算 | `envs/prod/private.auto.tfvars.json`（本人が作成、gitignore 済み、未追跡を確認） | 用意済み（Q7） |
| CI 用の値（ロール ARN、state、入力、ロック、通知先） | GitHub Secrets 9 件（`.ci-private/github-secrets.json` から gh の標準入力で登録） | 登録済み |
| whitelist | SSM SecureString `/<prefix>/minecraft/whitelist`（`aws/ssm`） | **未登録**。apply の前に本人が登録する |
| Discord の Webhook URL | SSM SecureString `/<prefix>/minecraft/discord-webhook` | 任意。未登録でもメールには届く |
| RCON パスワード | ホストが初回に生成し、ワールド EBS に 0600 で保存 | 起動時に生成 |

## 6. GitHub の設定

| 設定 | 値 |
|---|---|
| Environment `prod` | Required reviewers は本人、Prevent self-review はオフ、デプロイできるのは保護ブランチ（保護するのは `master` だけの方針と本人が確認） |
| Environment `ops` | 承認なし、保護ブランチだけ |
| Variables | `AWS_REGION`、`OPERATOR_LOGIN` |
| Branch protection の必須チェック | 11 件（fmt、validate、tflint、checkov、terraform-test、pytest、shellcheck、bats、identifier-check、gitleaks、plan）。本人が登録する |

## 7. 月額コスト（変更なし）

`infrastructure-specification.md` の見積もり（約 2,542〜2,817 円）に、この段階で次が加わる。どれも実質 0 円の見込み（要確認）。

- アクセスログ: 配信は無料、保存は月 0.02 円程度（Q3）
- VPC フローログ: 取り込み約 $0.25/GB（東京の単価は要確認）、数 MB / 月で 1 円未満（Q5）

## Sources

- `../../construction/infrastructure-design/infrastructure-specification.md`
- `../deployment-pipeline/cd-config.md`
- `environment-provisioning-questions.md` Q1〜Q8、Consolidated Summary Confirmation
- PR #3 の CI（11 件成功）と、手元・CI の plan のサマリー（件数とアドレスのみ）

## Assumptions & Open Questions

- [assumption] 東京リージョンの AZ は `ap-northeast-1a` を既定にする。m7g.xlarge が a / c / d で提供されていることは前回の読み取りで確認済み。
- [assumption] AL2023 の AWS CLI v2 が `--checksum-algorithm CRC64NVME` に対応している（2025 年以降の版で対応。要確認。Deployment Execution の初回バックアップで確認する）。

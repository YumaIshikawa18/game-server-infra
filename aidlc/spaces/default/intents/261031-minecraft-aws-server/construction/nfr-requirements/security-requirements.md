# Security Requirements

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/inception/requirements-analysis/requirements.md`（NFR5, NFR6, FR1.4, FR3.2, FR3.3, FR7.x, FR8.x, FR9.2）、`team-practices.md`（Deployment / Code Style）、`nfr-requirements-questions.md`。

## 1. 守る対象と脅威

| 守る対象 | 想定する脅威 | 主な対策（ID） |
|---|---|---|
| AWS アカウント（personal） | GitHub Actions 経由の不正操作。特に public リポジトリへの fork PR から仕掛けられるもの | NFR5.1, NFR5.2, NFR5.3 |
| Minecraft サーバー（EC2） | 不正参加、ポートスキャン、RCON 乗っ取り、SSH 総当たり | NFR5.4, NFR5.5, NFR5.6, NFR5.7, NFR5.8 |
| ワールドデータ / バックアップ | 誤削除、外部公開、改ざん | NFR5.9, NFR5.10 |
| Terraform state | 外部公開（state には識別子が平文で入る）、破損 | NFR5.11 |
| 秘匿値（Webhook URL、whitelist、RCON パスワード、メールアドレス） | リポジトリ・ログ・通知への漏洩 | NFR6.1〜NFR6.5 |
| サプライチェーン（コンテナイメージ、MOD、Actions） | 改ざんされたイメージや jar、タグのすり替え | NFR5.12, NFR5.13, NFR5.14 |

## 2. 認証と認可

| ID | 要件 | 合否基準 | 出典 |
|---|---|---|---|
| NFR5.1 | GitHub Actions から AWS への認証は OIDC だけで行う。長期アクセスキーは作らず、使わない | IAM ユーザーとアクセスキーが Terraform コードに存在しない（Checkov と grep で確認） | NFR5, team-practices |
| NFR5.2 | GitHub Actions 用の IAM ロールは 3 つに分ける（下の「ロールとワークフローの対応」）。<br>・どのロールも `aud` は `sts.amazonaws.com` に固定する<br>・`sub` はロールごとに `StringEquals` で 1 つに限定する<br>・`<owner>/<repo>` は変数で渡し、コードには書かない | `terraform test` で、3 つのロールの trust policy の `aud` / `sub` 条件を検証する | NFR5, NFR6 |
| NFR5.2a | plan 用ロール（`sub` = `repo:<owner>/<repo>:pull_request`）に許可するのは次の 3 つだけとする。<br>・state の読み取り（`s3:GetObject` / `s3:ListBucket`）<br>・ロックファイル `*.tflock` の `s3:PutObject` / `s3:DeleteObject`<br>・plan に必要な読み取り専用の Describe / Get / List 系<br>state 本体への書き込みは許可しない | `terraform test` で、state キーへの `PutObject` が `*.tflock` に限られていることを検証する | NFR5 |
| NFR5.2b | apply 用ロール（`sub` = `repo:<owner>/<repo>:environment:prod`。GitHub Environment `prod` で手動承認あり）は次のとおりとする。<br>・操作できるサービスは、このシステムで使うもの（EC2、EBS、VPC、S3、IAM、SSM、CloudWatch、Logs、SNS、Lambda、EventBridge、Budgets）に限る<br>・IAM の作成・変更は、名前プレフィックス（変数）の付いたロールとポリシーに限る<br>・作成するロールには permissions boundary の付与を必須とする（`iam:PermissionsBoundary` 条件）<br>・命名規則: bootstrap で作るもの（OIDC 用 3 ロールと boundary）のプレフィックスは `${prefix}-ci-`、envs/prod で作るもの（EC2 / Lambda の実行ロール）のプレフィックスは `${prefix}-app-` とする。apply 用ロールが作成・変更できるのは `${prefix}-app-*` だけで、`${prefix}-ci-*` には触れられない<br>・`iam:PassRole` の対象は、同じプレフィックスのロールに限り、渡し先は `ec2.amazonaws.com` / `lambda.amazonaws.com` に限る | `terraform test`（bootstrap）で、boundary 条件と PassRole の条件を検証する。Checkov の IAM 系チェックに通る | NFR5 |
| NFR5.2c | 運用操作用ロール（start / stop / restore。`sub` = `repo:<owner>/<repo>:environment:ops`。GitHub Environment `ops` は承認なしで、`master` ブランチからの実行だけに制限する。さらに各ワークフローのジョブに `if: github.actor == vars.OPERATOR_LOGIN` を付け、実行者を本人だけに限定する。ユーザー名は Variables から渡し、コードには書かない）に許可するのは次の 2 つだけとする。<br>・タグで限定した対象インスタンスの `ec2:StartInstances` / `ec2:StopInstances` / `ec2:DescribeInstances`<br>・対象インスタンスへの、指定ドキュメントだけの `ssm:SendCommand` と `ssm:GetCommandInvocation`<br>Terraform の state には触れない | `terraform test`（bootstrap）で、Action とタグ条件を検証する | NFR5, FR4, FR6.5 |
| NFR5.2d | OIDC プロバイダーと上記 3 つのロール、permissions boundary は `bootstrap/` で作る（手元で `--profile personal` を使って 1 回だけ apply）。CI（`envs/prod`）からは変更できないこと。apply 用ロールに、これら bootstrap のリソースを変更する権限を与えない | `terraform test`（bootstrap）で次の 2 点を検証する。<br>・apply 用ロールの IAM 許可の Resource が `${prefix}-app-*` だけであること<br>・`${prefix}-ci-*` への `iam:*` が明示的に Deny されていること | NFR5, FR7.4 |
| NFR5.3 | fork からの PR では AWS 認証を行わない（GitHub の仕様で fork PR には `id-token` が発行されないことを前提にする）。workflow の `permissions` は既定を `contents: read` とし、必要なジョブだけに `id-token: write` / `pull-requests: write` を付ける | workflow ファイルのトップレベルに最小の `permissions` がある。`pull_request_target` は使わない | NFR5（public リポジトリの補強） |
| NFR5.4 | 各 IAM ロールとインスタンスプロファイルは最小権限にする。<br>・EC2 には「バックアップ用 S3 プレフィックスへの読み書き」「自分の SSM パラメータの読み取り」「CloudWatch へのメトリクス・ログ送信」「自分自身の停止（自動停止用）」だけを与える<br>・ワイルドカード `*` の Action / Resource を使わない（AWS が対応していないものを除き、理由をコメントで書く） | Checkov（IAM 系チェック）に通る。`terraform test` で主要な Action を検証する | NFR5 |
| NFR5.4a | Lambda の実行ロールも最小権限にする。<br>・watchdog: `ec2:DescribeInstances` / `ec2:DescribeInstanceStatus`、タグ `mc:managed=true` の付いた対象インスタンスだけへの `ec2:StopInstances`、`cloudwatch:GetMetricData`、通知用 SNS トピックだけへの `sns:Publish`、自分のロググループへの書き込み<br>・通知: Webhook URL の SSM パラメータだけへの `ssm:GetParameter`、`kms:Decrypt`（AWS マネージド鍵 `aws/ssm`。`kms:ViaService = ssm.<region>.amazonaws.com` の条件付き）、自分のロググループへの書き込み | `terraform test` で、Action・リソース・タグ条件・`kms:ViaService` 条件を検証する。Checkov に通る | NFR5, NFR7.9a, FR8.2 |
| NFR5.4b | 停止処理中の印（EC2 タグ `mc:stopping`）は、サーバー側の停止スクリプトが付け外しする（手動停止・自動停止の両方）。<br>EC2 インスタンスプロファイルに許可するのは、自分自身のインスタンス（`ec2:ResourceTag/mc:managed = true` かつ自インスタンス ID）に対する `ec2:CreateTags` / `ec2:DeleteTags` だけとする。対象のタグキーは `mc:stopping` だけ（`aws:TagKeys` 条件）にする | `terraform test` で、Action・`aws:TagKeys` 条件・リソース条件を検証する | NFR5, NFR7.9a |

### ロールとワークフローの対応

| ワークフロー | トリガー | GitHub Environment | 使うロール | 承認 |
|---|---|---|---|---|
| plan（PR チェック） | `pull_request`（fork PR には OIDC トークンが発行されない） | なし | plan 用 | なし |
| deploy（apply） | `master` への push | `prod` | apply 用 | 本人による手動承認 |
| start / stop / restore | `workflow_dispatch`（`master` のみ、実行者は本人に限定） | `ops` | 運用操作用 | なし |
| bootstrap | 手元から実行（CI の対象外） | — | 本人のプロファイル（`personal`） | — |

start には承認が入らないため、NFR3.1 の起動時間には承認待ちの時間が含まれません。

## 3. ネットワークとホスト

| ID | 要件 | 合否基準 | 出典 |
|---|---|---|---|
| NFR5.5 | セキュリティグループの受信は 25565/TCP（0.0.0.0/0 と ::/0）だけにする。22/TCP と RCON のポートは開けない | `terraform test` で ingress ルールが 25565 の 1 種類だけであることを検証する | NFR5 |
| NFR5.6 | 管理用の接続は SSM Session Manager で行い、SSH キーペアは作らない | `key_name` が未設定。SSM 用のマネージドポリシー（`AmazonSSMManagedInstanceCore`）だけを付与する | NFR5 |
| NFR5.7 | IMDSv2 を必須（`http_tokens = "required"`）にし、ホップ制限は 2（コンテナから使うため）にする | Checkov の IMDS チェックに通る | NFR5 |
| NFR5.8 | `online-mode=true` と whitelist（`enforce-whitelist=true`）を必須にする。RCON は有効にする場合でもコンテナ内の localhost だけで待ち受け、パスワードは SSM から注入する | `terraform test` / 設定ファイルのテストで値を検証する（FR1.4, FR8.3） | NFR5, FR1.4, FR8.3 |

## 4. データ保護

| ID | 要件 | 合否基準 | 出典 |
|---|---|---|---|
| NFR5.9 | EBS（ルートとワールド）は暗号化する（AWS マネージドキーで可） | Checkov の EBS 暗号化チェックに通る | NFR5 |
| NFR5.10 | バックアップ用 S3 バケットは次のとおりにする。<br>・Block Public Access を 4 項目すべて有効にする<br>・SSE を有効にする<br>・TLS 以外のアクセスを拒否するバケットポリシーを付ける<br>・バージョニングを有効にし、旧バージョン（noncurrent）はライフサイクルで 7 日後に削除する。期限切れの削除マーカーも削除する<br>・`prevent_destroy` を付ける | Checkov の S3 系チェックに通る。`terraform test` で `noncurrent_days = 7` を検証する | NFR5, FR6 |
| NFR5.11 | state 用 S3 バケット（bootstrap）は次のとおりにする。<br>・Block Public Access、SSE、バージョニング、TLS 強制、`prevent_destroy` を有効にする<br>・state へのアクセスは 2 つの IAM ロールと本人だけに絞る | bootstrap の `terraform test` で設定を検証する | NFR5, NFR6 |

## 5. サプライチェーン

| ID | 要件 | 合否基準 | 出典 |
|---|---|---|---|
| NFR5.12 | コンテナイメージ `itzg/minecraft-server` は digest（`@sha256:...`）で固定する。更新は PR で digest を変えて行う | 設定にタグだけの指定（`:latest` 等）がない（テストで検証する） | FR2.1, [Q4] |
| NFR5.13 | MOD の jar はチェックサムを検証してから配置する（FR3.2） | AC3.2.2 | FR3.2 |
| NFR5.14 | GitHub Actions のサードパーティ action はコミット SHA で固定する | workflow 内の `uses:` がすべて 40 桁の SHA で指定されている（CI の lint で確認する） | NFR5（補強） |

## 6. 秘匿性（public リポジトリ）

| ID | 要件 | 合否基準 | 出典 |
|---|---|---|---|
| NFR6.1 | 次の値はコードに書かない。<br>アカウント ID、IAM ロール名・ARN、state バケット名、バックアップバケット名、Elastic IP、`<owner>/<repo>`、whitelist、Discord Webhook URL、通知先メールアドレス、RCON パスワード | CI の必須チェック「識別子チェック」で自動検査する。このチェックは、追跡対象の全ファイルに次のパターンがあれば失敗する。<br>・アカウント ID を含む ARN（`arn:aws:<service>:<region>:<12 桁>:`）<br>・単独の 12 桁の数字（アカウント ID の形）<br>・グローバル IPv4 アドレス<br>・`discord.com/api/webhooks/`<br>・メールアドレス<br>許可リスト（失敗にしないもの）は次のとおり。<br>・AWS 管理ポリシーの ARN（`arn:aws:iam::aws:policy/`）<br>・`data.aws_partition` / `data.aws_caller_identity` を使った参照式<br>・`0.0.0.0/0` と `::/0`<br>・RFC1918 のプライベート CIDR（10/8、172.16/12、192.168/16）<br>・`noreply@` で始まるアドレス<br>・ドキュメント用の例示値（`123456789012`、`192.0.2.0/24` など）<br>テストとして、許可リストに当たるサンプルは通り、本物の形の値は失敗するフィクスチャを用意する。あわせて gitleaks（一般的なシークレットの検出）も必須チェックにする（NFR8.2） | NFR6, project.md Forbidden |
| NFR6.2 | CI で使う識別子は GitHub Secrets から `TF_VAR_*` と `-backend-config` で渡す。ローカルでは gitignore 済みの `*.auto.tfvars` / `backend.hcl` に置く | `.gitignore` に `*.auto.tfvars` と `backend.hcl` が含まれている | NFR6, team-practices |
| NFR6.3 | 実行時の秘匿値（Webhook URL、whitelist、RCON パスワード）は SSM Parameter Store の SecureString に置く（暗号化は AWS マネージド鍵 `aws/ssm`）。値は Terraform では作らず（state に平文で残るため）、本人が手動か CLI で登録する。Terraform はパラメータ名の参照と、その名前への読み取り権限だけを扱う | `terraform show` / state に秘匿値の平文がない | NFR6, FR8.4 |
| NFR6.4 | Actions のログと PR コメントには plan のサマリーだけを出す。<br>・識別子は `::add-mask::` でマスクする<br>・`terraform plan` の全文は artifact にもアップロードしない<br>・Terraform 側は秘匿性のある出力に `sensitive = true` を付ける | AC7.1.3。出力の `sensitive` をテストで検証する | NFR6, FR7.1 |
| NFR6.5 | Discord の通知本文に、Elastic IP、アカウント ID、ARN、インスタンス ID を含めない | AC8.2.4（Lambda の単体テストで、本文にこれらの形式の文字列がないことを検証する） | NFR6, FR8.2 |

## 7. 検証方法

- PR ごとの Checkov（NFR8）を、上記のうち静的に検査できる項目の合否基準にします。
- 例外として Checkov のチェックを抑止する場合は、該当リソースに `#checkov:skip=<ID>:<理由>` を書きます。抑止の一覧は tech-stack-decisions.md で管理します。

## Sources

- `requirements.md` NFR5, NFR6, FR1.4, FR3.2, FR3.3, FR7.1, FR8.2〜FR8.4
- `team-practices.md` Deployment / Code Style、`aidlc/spaces/default/memory/project.md` の Forbidden / Mandated
- `nfr-requirements-questions.md` [Q4]

## Assumptions & Open Questions

- [assumption] fork PR では OIDC トークンが発行されない（GitHub の既定動作）。リポジトリ設定で「fork PR の workflow 実行に承認を必須にする」ことも推奨する。
- [assumption] EBS と S3 の暗号化は AWS マネージドキーで十分とする（コストを抑えるため、カスタマー管理 KMS キーは使わない）。
- 識別子チェックと gitleaks は、pytest と合わせて必須チェックに加える。必須チェックは計 9 つになる（承認前の確認で本人が決定。NFR6.1, NFR8.2）。`team.md` の必須チェック一覧の更新は、次に Practices Discovery を見直すときに行う。
- 運用操作用の GitHub Environment `ops` は承認なしとし、`master` ブランチからの実行だけを許可する。あわせて、実行者を本人に限定する（承認前の確認で本人が決定。NFR5.2c）。

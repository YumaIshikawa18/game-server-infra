# Team-Level Rules

> This team's affirmed practices and corrections. Loaded after `org.md` as
> strict-additive guidance; contradictions with broader policy are rejected.
> Populated by the practices-discovery affirmation gate. Edit at the gate,
> not directly.

## Way of Working

- 私たちは 1 名体制（CODEOWNERS は `@YumaIshikawa18` のみ）で、トランクベース開発を採用します。トランク（既定ブランチ）は保護された `master` です。org.md の既定にある `main` は、本リポジトリでは `master` に読み替えます。
- 変更はすべて短命な作業ブランチ（例: `feature/<topic>`）で行い、Pull Request を経て `master` に **squash merge** します。`master` への直接 push は行いません。[Q1]
- Construction で AI-DLC が作る worktree も同じ方針で、base `master` / target `master`、マージ方式は squash とします。
- squash 後のコミットメッセージは PR タイトルをそのまま使います。PR タイトル・コミットメッセージは英語で、先頭を大文字にし、conventional commit prefix（`feat:` など）を付けず、50 文字以内の 1 文で書きます。`Co-Authored-By:` / `Claude-Session:` などの attribution は、コミットメッセージにも PR 本文にも入れません。
- 必須ステータスチェック（`terraform fmt -check`、`terraform validate`、tflint、Checkov、`terraform test`、`terraform plan`）がすべて成功していれば、自分の PR をセルフマージしてよいものとします。必須チェックは Branch protection の required status checks に登録します。[Q2]
- 本リポジトリは public です。AWS アカウント ID、IAM ロール名・ARN、state バケット名などの識別子は、コード・ログ・PR コメントのいずれにも出しません（詳細は `## Deployment` と `## Code Style`）。

## Walking Skeleton

- 私たちは最初に walking skeleton（端から端まで動く最小構成）を作ります。最初のスライスは「ネットワーク → EC2 上の Minecraft サーバー → 手元の Minecraft クライアントから接続」で、これを GitHub Actions のパイプライン（PR での plan → マージ後の承認付き apply）経由で通します。[Q3]
- 完了条件は「Minecraft クライアントからサーバーに接続できること」です。ポートへの TCP 接続成功だけでは完了とみなしません。
- skeleton の完了後に、MOD 対応・ワールドバックアップ・監視などを順に積み上げます。
- 補足: `infra` スコープは `skeleton: on` ですが、units-generation / code-generation が SKIP のため Unit DAG が作られない場合、org.md の規定どおり skeleton チェックポイントの儀式は発生しません。その場合も、上記の「最初に通し構成を作る」順序は実務上の慣行として守ります。

## Testing Posture

- **Methodology**: test-after
- **Methodology evidence**: 本人が Q5 で「plan モードの `terraform test` を全モジュールに最低 1 つ + 静的チェック・スキャンすべて通過」（A）を選び、テスト先行の方法論は求めていません。Terraform 中心のリポジトリで、モジュールを書いてから plan モードのテストで期待値を確認する流れが自然なため、test-after とします。
- **Ordering**: 各 Terraform モジュール（または環境のルートモジュール）を実装した後に、そのモジュールの plan モード `terraform test` を書いて実行し、あわせて fmt / validate / tflint / Checkov を通してから PR に出します。
- PR ごとに GitHub Actions で次のチェックを実行し、1 つでも失敗したらマージをブロックします。[Q4]
  - `terraform fmt -check`
  - `terraform validate`
  - tflint（AWS ルールセット付き）
  - Checkov（IaC セキュリティスキャン）
  - Trivy は採用しません。
- org.md の `infra` スコープ既定である「80% line-coverage floor」は、Terraform には行カバレッジがそのまま当てはまらないため、次の基準に **置き換え** ます（緩和ではありません）。[Q5]
  - すべてのモジュールに、plan モード（実リソースを作らない）の `terraform test` が最低 1 つあること
  - 上記の必須チェックがすべて通過していること
  - これらを CI で実行し、マージ前に成功していること
- 実 apply を伴う統合テストは行いません。実環境での確認は、デプロイ後のスモークテスト（`## Deployment`）で担保します。
- Build and Test では、この置き換え基準を弱めてステップを通すことはしません。

## Guard Policy

<!-- Affirmed by the team. Mode: strict, relaxed, or off. Strict here holds for every intent, whatever one person asks in chat; relaxed or off here applies to every intent whose policy came from its scope, unless project.md or the person sets another; changing this line changes it. A section under the retired Change Control heading, written by an earlier release, is still read. -->

## Deployment

- 環境は本番（`prod`）1 つです。デプロイ先は `aws login --profile personal` で利用する個人 AWS アカウントです。[Q6]
- PR では `terraform plan` を実行し、結果を PR に投稿します。ただし public リポジトリのため、plan の全文はそのまま PR コメントやログに出しません。投稿するのは追加・変更・削除の件数と対象リソースのアドレスなどの **サマリーのみ** とし、識別子を含む値は `::add-mask::` でマスクします。plan に含まれる派生 ARN は GitHub の Secrets マスクで自動的に隠されないことを前提に扱います。
- `master` へのマージ後、GitHub Environments（`prod`）の手動承認（承認者は本人）を経て `terraform apply` を実行します。マージだけで自動 apply はしません。org.md 既定の「tech lead + product owner 承認」は、1 名体制のため本人による承認に読み替えます。
- GitHub Actions から AWS への認証は OIDC + IAM ロールで行い、長期アクセスキーは使いません。[Q7]
- Terraform の state は S3 に置き、S3 ネイティブロック（`use_lockfile = true`）を使います。DynamoDB によるロックは使いません。
- state バケットなどを作る `bootstrap/` は、手元から `--profile personal` で 1 回だけ apply します。bootstrap は CI の対象外です。
- AWS アカウント ID、IAM ロール ARN、state バケット名などの値は次のように扱います。
  - CI: GitHub Secrets に保存し、実行時に `TF_VAR_*` 環境変数と `-backend-config`（partial backend configuration）で渡します。
  - ローカル: gitignore 済みの `*.auto.tfvars` / `backend.hcl` に置きます。
  - コミットするコード、Actions のログ、PR コメントには出しません。
- すべてのデプロイ手順にはロールバック手順を用意します（例: 直前のコミットを revert する PR をマージし、承認付き apply で戻す。必要に応じて EBS スナップショット等からワールドを復元する）。具体的な手順は operation フェーズで定義します。
- デプロイ後のスモークテストは必須です。apply 後にサーバーポートへの接続確認を自動で行い、最終的には Minecraft クライアントからの接続で完了を確認します。

## Code Style

- `.editorconfig` に従います（UTF-8、LF、インデント 2 スペース、末尾改行あり、行末空白の除去）。
- Terraform のフォーマットは `terraform fmt` に従い、CI の `terraform fmt -check` で差分があれば PR をブロックします。
- リソース名・変数名・出力名・モジュール名は snake_case とします。
- リポジトリ構成は次のとおりです。[Q8]
  - `bootstrap/` — state バックエンド（S3 バケット等）を作るルートモジュール。手元で 1 回だけ apply
  - `envs/prod/` — 本番環境のルートモジュール
  - `modules/<name>/` — 再利用モジュール
- `.terraform.lock.hcl` はコミットします。現在 `.gitignore` で除外されているため、Construction で除外設定を外します。
- Terraform 本体と AWS provider のバージョンは `~>` で固定します（例: `required_version = "~> 1.x"`、`version = "~> 6.x"` の形でマイナーまで固定。具体的なバージョンは Construction で決めます）。
- public リポジトリのため、AWS アカウント ID、IAM ロール名・ARN、state バケット名などの識別子をコードにハードコードしません。IAM ロール名などのリソース名も変数でパラメータ化し、値は GitHub Secrets（CI）または gitignore 済みのローカルファイル（`*.auto.tfvars` / `backend.hcl`）から渡します。
- 以前に別リポジトリで構築したコードはコピー・流用せず、本リポジトリでゼロから作成します。
## Forbidden

<!-- Team-specific forbidden patterns -->

## Mandated

<!-- Team-specific mandates -->

## Corrections

<!-- Self-learning loop appends here. -->
- ALWAYS レビューで出た懸念は、承認の判断を求める前に、選択肢付きの質問にして本人に聞く (learned 2026-10-31) <!-- cid:261031-minecraft-aws-server:requirements-analysis:76d3d43a1dc8a369eb5788a19b4e16b2f1c092a53a31a542b88dd413e991b7ab -->

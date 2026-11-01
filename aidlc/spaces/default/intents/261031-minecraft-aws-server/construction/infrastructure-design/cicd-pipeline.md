# CI/CD Pipeline

上流: `aidlc/spaces/default/intents/261031-minecraft-aws-server/construction/nfr-design/security-design.md`（§1, §2, §4, §5）、`reliability-design.md`（§2, §6, §7, §8）、`performance-design.md`（起動経路）、`logical-components.md`（LC11）、`team-practices.md`。

## 1. ワークフロー一覧

| ファイル | トリガー | Environment | ロール | 目的 |
|---|---|---|---|---|
| `pr.yml` | `pull_request`（`master` 向け） | なし | `${prefix}-ci-plan`（plan ジョブのみ） | 必須チェック 11 種と plan サマリー |
| `deploy.yml` | `push`（`master`）、`workflow_dispatch` | plan ジョブ: なし／apply ジョブ: `prod`（本人の承認が必須） | plan ジョブ: `${prefix}-ci-plan`／apply ジョブ: `${prefix}-ci-apply` | plan（承認前にサマリーを表示）→ 承認 → 再 plan と照合 → 置き換えの保護 → apply → スモークテスト |
| `start.yml` / `stop.yml` / `restore.yml` | `workflow_dispatch`（`master` のみ） | `ops`（承認なし、`master` のみ） | `${prefix}-ci-ops` | 運用操作。各ジョブに `if: github.actor == vars.OPERATOR_LOGIN` を付ける |

- `bootstrap/` は CI の対象外です。手元で `terraform -chdir=bootstrap apply` を実行します（README に手順を書きます）。

## 2. 共通の方針

- **権限**: ワークフローの先頭で `permissions: contents: read` を指定し、必要なジョブだけに `id-token: write`（OIDC）と `pull-requests: write`（コメント）を足します。`pull_request_target` は使いません。
- **action の固定**: すべての `uses:` を 40 桁の SHA で固定し、バージョンはコメントで書きます。Dependabot（`github-actions`）が更新 PR を作ります。
- **ランナー**: `ubuntu-24.04` に固定します（`-latest` は使いません）。
- **ツールのバージョン**: Terraform、tflint、Checkov、ShellCheck、bats、gitleaks、Python のバージョンは、リポジトリの `.tool-versions` で固定します。CI はそれを読んで導入します。
- **排他**: グループを 2 つに分けます（承認前の確認で本人が決定）。
  - `minecraft-ops`: start / stop / restore の各ジョブ
  - `minecraft-prod`: deploy の apply ジョブ
  - どちらも `cancel-in-progress: false` です。
  - GitHub がジョブの concurrency を環境承認の前後どちらで取得するかに関係なく、stop（課金を止める手段）が承認待ちの deploy に待たされることはありません。
  - apply と運用操作が同時に走った場合でも、apply 側は「置き換えの保護」（§4 手順 4）で直前のインスタンス状態を確認してから進みます。stop.sh は `flock` で排他するので、ホスト上の処理は重なりません。
  - GitHub の concurrency は「実行中 1 件と待機 1 件」までしか保持しません。3 件目を起動すると、待機中の run は取り消されます。この挙動と「取り消されたら再実行する」手順を README に書きます。
- **マスク**: AWS を使うジョブの最初のステップで、`TF_VAR_*` に入る識別子と `aws sts get-caller-identity` の結果を `::add-mask::` に登録します。
- **秘匿値の受け渡し**: 必要な値は次のとおりです。
  - Secrets: `AWS_PLAN_ROLE_ARN`、`AWS_APPLY_ROLE_ARN`、`AWS_OPS_ROLE_ARN`、`TF_STATE_BUCKET`、`TF_VAR_*`（アカウント ID、prefix、バックアップバケット名、通知先メール、予算額など）
  - Variables: `OPERATOR_LOGIN`、`AWS_REGION`

## 3. `pr.yml` のステージと必須チェック

| 順 | ジョブ（Branch protection の required check 名） | 内容 | 失敗時 |
|---|---|---|---|
| 1 | `fmt` | `terraform fmt -check -recursive` | マージ不可 |
| 2 | `validate` | 各ルートモジュールとモジュールで `terraform init -backend=false` と `validate` | マージ不可 |
| 3 | `tflint` | `tflint --recursive`（`tflint-ruleset-aws`） | マージ不可 |
| 4 | `checkov` | `checkov -d . --framework terraform,github_actions`。抑止は `#checkov:skip` に理由を付ける | マージ不可 |
| 5 | `terraform-test` | `bootstrap/`、`envs/prod/`、`modules/*` で `terraform test`（plan モード、モック provider） | マージ不可 |
| 6 | `pytest` | Lambda（watchdog / notifier）の単体テスト | マージ不可 |
| 7 | `shellcheck` | `shellcheck -S style` を `modules/minecraft_server/files/bin/*.sh` に実行 | マージ不可 |
| 8 | `bats` | スクリプトのテスト（外部コマンドはスタブ） | マージ不可 |
| 9 | `identifier-check` | 識別子パターンの検査（security-requirements の NFR6.1 の許可リスト付き）。フィクスチャのテストも同じジョブで実行 | マージ不可 |
| 10 | `gitleaks` | `gitleaks detect --redact` | マージ不可 |
| 11 | `plan` | OIDC（`ci-plan`）で `envs/prod` を `terraform plan -lock-timeout=5m -out` で実行し、`show -json` から件数とアドレスだけを要約する。PR コメント（同じコメントを更新）と Job Summary に出す。fork PR では OIDC が使えないため、`skipped` にして理由を表示する | マージ不可（fork PR の場合は、本人がブランチを取り込んで再実行する） |

- ジョブ 1〜10 は AWS 認証なしで動き、並列に実行します。11 は 1〜3 の成功後に実行します。

## 4. `deploy.yml`（apply の流れ）

1. **plan ジョブ（承認前）**: OIDC（`ci-plan`）で認証してマスクを登録し、`terraform plan` を実行します。
   - Job Summary には、件数とアドレスのサマリーを出します。EC2 の置き換えやリソースの削除があれば、目立つ警告として先頭に書きます。
   - `resource_changes` の（アドレス、actions）の組を正規化して sha256 を計算し、ジョブの出力 `plan_digest` にします。
   - plan ファイルは artifact としてアップロードしません。public リポジトリでは artifact を誰でもダウンロードでき、plan ファイルには値が平文で入るためです。
   - `ci-plan` の trust に、`sub` = `repo:<repo>:ref:refs/heads/master` を加えます（`StringEquals` の候補を 2 つにする。security-design.md §2 への追加）。
2. **apply ジョブ**: `environment: prod`（本人の承認待ち）とします。承認者は、手順 1 の Job Summary を見て判断します。承認後に OIDC（`ci-apply`）で認証し、マスクを登録します。
3. 同じコミットで `terraform plan -out=tfplan` を再実行し、`plan_digest` を計算し直します。手順 1 の値と一致しなければ、apply せずに失敗させます（承認した内容と違う変更は適用しない）。
4. **置き換えの保護**: plan JSON に `aws_instance.minecraft` の `delete` があり、インスタンスが `running` なら、SSM で `mc-stop`（理由: replace）を実行して `stopped` になるまで待ちます。
   - これに使うのは ci-apply の EC2 Describe と SSM の権限です。`mc-stop` ドキュメントへの `ssm:SendCommand` を ci-apply にも追加します。
5. `terraform apply tfplan` を実行します。
6. **スモークテスト**: インスタンスが `running` なら、SSM で `mc-health-check` を最大 10 分、15 秒ごとに実行します。停止中なら「停止中のため確認を省略」と Job Summary に出します。
7. 失敗した場合は、`always()` のステップで SNS（`events`）に失敗を送ります。

## 5. 運用ワークフロー

| ワークフロー | 処理 | 失敗時 |
|---|---|---|
| `start.yml` | ①`mc:mode` タグがないことを確認 → ②`StartInstances` → ③SSM の応答を待つ（3 分）→ ④`mc-health-check` を 15 秒ごと、最大 10 分 → ⑤所要時間を Job Summary に出す | ③で失敗したら `StopInstances` で直接停止。④で失敗したら `mc-stop`（理由: start-failed）。どちらも SNS に送る |
| `stop.yml` | `mc-stop`（理由: manual）→ `stopped` を待つ | SSM が応答しない場合は `StopInstances` で直接停止し、SNS に「バックアップなしで停止」と送る |
| `restore.yml` | 入力でキーを受け取る → `stopped` を確認 → タグ `mc:mode=restore` → Start → `mc-restore-apply <key>` → タグを外す → Stop | `always()` でタグを外して停止。SNS に送る |

## 6. ロールバック

| 対象 | 手順 |
|---|---|
| インフラ変更 | 該当 PR を revert する PR を作る → 必須チェック → マージ → `prod` の承認 → apply |
| Minecraft / ローダー / MOD の更新 | 上記の revert を apply した後、更新前の `stop/` バックアップを restore.yml で復元 → start.yml |
| state の破損 | state バケットのバージョニングから直前の版を復元する（手元で実行。手順は README / runbook に書く） |

## 7. 依存の更新（Dependabot）

- `.github/dependabot.yml` の対象は次の 4 つです。
  - `github-actions`（`/`）
  - `terraform`（`/bootstrap`、`/envs/prod`、`/modules/*`）
  - `pip`（`/lambda/*`）
  - `docker-compose`（`/docker`）
- 頻度は週 1 回で、ecosystem ごとにグループ化します。itzg イメージの更新 PR では、本文で「ワールドを更新前にバックアップ済みか」を確認するよう促します（PR テンプレート）。
- Minecraft 本体・ローダー・MOD のバージョンは、Dependabot の対象外です。手動の PR で更新します。

## 8. 環境の昇格

- 環境は `prod` の 1 つだけです。PR の plan と、承認付きの apply が昇格の代わりになります。

## Sources

- `nfr-design/security-design.md` §1〜§5、`reliability-design.md` §2・§6〜§8、`performance-design.md`、`logical-components.md` LC11
- `infrastructure-design-questions.md` [Q1]〜[Q3]

## Assumptions & Open Questions

- [assumption] ツールのバージョンは `.tool-versions` で固定する。
- [assumption] ci-apply には、置き換え保護とスモークテストのために、`mc-stop` と `mc-health-check` ドキュメントへの `ssm:SendCommand` と `GetCommandInvocation` を加える（security-design.md §2 への追加）。
- [assumption] `ci-plan` の trust に `master` ブランチ（push）の sub を加える。plan 用の読み取り権限は PR と同じとする（security-design.md §2 への追加）。
- SNS トピックは暗号化しない（infrastructure-specification.md の SNS の暗号化の行。承認前の確認で本人が決定）。

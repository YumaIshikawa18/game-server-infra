# Project-Level Rules

> Project-specific specialisation and corrections. Loaded after `org.md` and
> `team.md` as strict-additive guidance; contradictions with broader policy
> are rejected. Populated by practices-discovery and the self-learning loop.
>
> Use sparingly: most teams don't need a project layer. Reach for it
> only when this specific project needs stable, durable guidance beyond the
> team practice (for example, package-specific release checks or an additional
> regression suite for a legacy component).

## Way of Working

<!-- Project-specific specialisation. Example: -->
<!-- This monorepo requires package-scoped branch names and a package owner -->
<!-- review in addition to the team's normal merge policy. -->

## Walking Skeleton

<!-- Project-specific specialisation. Example: -->
<!-- The walking skeleton must exercise the legacy service adapter as well -->
<!-- as the new service boundary. -->

## Testing Posture

<!-- Project-specific specialisation. -->

## Guard Policy

<!-- Project-specific. Mode: strict, relaxed, or off. Strict here holds for every intent, whatever one person asks in chat; relaxed or off here applies to every intent whose policy came from its scope, unless the person sets another; changing this line changes it. A section under the retired Change Control heading, written by an earlier release, is still read. -->

## Deployment

<!-- Project-specific specialisation. -->

## Code Style

<!-- Project-specific specialisation. -->

## Tech Stack

<!-- Technology choices locked for this project. -->

## Decided

<!-- Decisions made in earlier stages that should not be re-asked. -->
<!-- Format: DECIDED: [decision] (Stage [slug], [date]) -->

## Scope Overrides

<!-- Custom scope rules for this project. -->

## Forbidden

<!-- Populated by practices-discovery affirmation gate. -->
<!-- Format: NEVER [behavior] (affirmed [date]) -->
<!-- Example: NEVER throw exceptions across service layer boundaries (affirmed 2026-05-17) -->

- NEVER `master` ブランチへ直接 push する（出典: [desc]「masterブランチは保護しているので、PRによる形をとる。」） (affirmed 2026-10-31)

- NEVER 以前に別リポジトリで構築したコードをコピー・流用する（出典: [desc]「ただ新規でゼロから作りたい。」） (affirmed 2026-10-31)

- NEVER コミットメッセージや PR 本文に `Co-Authored-By:` / `Claude-Session:` などの attribution トレーラー・表記を入れる（出典: グローバル設定） (affirmed 2026-10-31)

- NEVER AWS アカウント ID、IAM ロール名・ARN、state バケット名をコミット・ログ出力・PR コメント投稿する。public リポジトリのため、plan の全文をそのまま PR コメントやログに出すことも含む（出典: サマリー確認時の発言「publicリポジトリなので、アカウントIDは勿論のこと、IAMロール名なども極力出したくない。」） (affirmed 2026-10-31)

## Mandated

<!-- Populated by practices-discovery affirmation gate. -->
<!-- Format: ALWAYS [behavior] (affirmed [date]) -->
<!-- Example: ALWAYS use Result<T,E> for fallible operations in service layer (affirmed 2026-05-17) -->

- ALWAYS `master` ブランチへの変更は Pull Request を通じて取り込む（出典: [desc]「masterブランチは保護しているので、PRによる形をとる。」、[Q1] A） (affirmed 2026-10-31)

- ALWAYS インフラは Terraform でコードとして定義・構築する（出典: [desc]「terraformで構築したい。」） (affirmed 2026-10-31)

- ALWAYS CI/CD は GitHub Actions で実装する（出典: [desc]「GitHub ActionsによるCICDでやりたい。」） (affirmed 2026-10-31)

- ALWAYS デプロイ先は `aws login --profile personal` で利用する AWS アカウントとする（出典: [desc]「環境先はaws login --profile personalの方のアカウント。」） (affirmed 2026-10-31)

- ALWAYS 本リポジトリでゼロから新規にコードを作成する（出典: [desc]「ただ新規でゼロから作りたい。」） (affirmed 2026-10-31)

- ALWAYS コミットメッセージと PR タイトルは英語で、先頭を大文字にし、conventional commit prefix を付けず、50 文字以内の 1 文で書く（出典: グローバル設定） (affirmed 2026-10-31)

- ALWAYS AWS アカウント ID、IAM ロール名・ARN、state バケット名などの識別子は、CI では GitHub Secrets に、ローカルでは gitignore 済みのファイル（`*.auto.tfvars` / `backend.hcl` 等）に置き、実行時に渡す（出典: サマリー確認時の発言「ローカルで置くべき値については、CICDで実際はGitHubのSecretsにしまう等にして対応が良いかなと思うけどどうかな。」） (affirmed 2026-10-31)

## Corrections

<!-- Project-specific corrections from human feedback. -->
<!-- Format: NEVER/ALWAYS [behavior] (learned [date]) -->

# Discovered Rules

> 本人が明言したハードな制約のみを記載しています。org.md の既定値や推論に由来する慣行は `team-practices.md` に置いています。
> 出典の表記: `[desc]` = 依頼文、`[Q<n>]` = `practices-discovery-questions.md` の回答、「サマリー確認時の発言」= Consolidated Summary Confirmation で本人が追加した発言、「グローバル設定」= 本人の `~/.claude/CLAUDE.md`。

## Mandated

- ALWAYS `master` ブランチへの変更は Pull Request を通じて取り込む（出典: [desc]「masterブランチは保護しているので、PRによる形をとる。」、[Q1] A）
- ALWAYS インフラは Terraform でコードとして定義・構築する（出典: [desc]「terraformで構築したい。」）
- ALWAYS CI/CD は GitHub Actions で実装する（出典: [desc]「GitHub ActionsによるCICDでやりたい。」）
- ALWAYS デプロイ先は `aws login --profile personal` で利用する AWS アカウントとする（出典: [desc]「環境先はaws login --profile personalの方のアカウント。」）
- ALWAYS 本リポジトリでゼロから新規にコードを作成する（出典: [desc]「ただ新規でゼロから作りたい。」）
- ALWAYS コミットメッセージと PR タイトルは英語で、先頭を大文字にし、conventional commit prefix を付けず、50 文字以内の 1 文で書く（出典: グローバル設定）
- ALWAYS AWS アカウント ID、IAM ロール名・ARN、state バケット名などの識別子は、CI では GitHub Secrets に、ローカルでは gitignore 済みのファイル（`*.auto.tfvars` / `backend.hcl` 等）に置き、実行時に渡す（出典: サマリー確認時の発言「ローカルで置くべき値については、CICDで実際はGitHubのSecretsにしまう等にして対応が良いかなと思うけどどうかな。」）

## Forbidden

- NEVER `master` ブランチへ直接 push する（出典: [desc]「masterブランチは保護しているので、PRによる形をとる。」）
- NEVER 以前に別リポジトリで構築したコードをコピー・流用する（出典: [desc]「ただ新規でゼロから作りたい。」）
- NEVER コミットメッセージや PR 本文に `Co-Authored-By:` / `Claude-Session:` などの attribution トレーラー・表記を入れる（出典: グローバル設定）
- NEVER AWS アカウント ID、IAM ロール名・ARN、state バケット名をコミット・ログ出力・PR コメント投稿する。public リポジトリのため、plan の全文をそのまま PR コメントやログに出すことも含む（出典: サマリー確認時の発言「publicリポジトリなので、アカウントIDは勿論のこと、IAMロール名なども極力出したくない。」）

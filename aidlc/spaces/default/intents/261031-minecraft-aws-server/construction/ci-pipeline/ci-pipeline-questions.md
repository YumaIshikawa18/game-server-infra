# CI Pipeline — 質問

既決事項は infrastructure-design/cicd-pipeline.md と過去の質問への回答を引き継ぐ。GitHub Actions、master 向け PR、squash merge、11 種類の必須チェック、OIDC、公開する plan は件数とリソースアドレスのみ、plan ファイルは公開 artifact に保存しない。

## Q1. [リリースエンジニア] fork PR の plan 未実行をマージ条件にどう反映するか

上流設計は「fork PR の plan は skipped、マージ不可」としているが、GitHub は skipped ジョブを成功扱いにするため、そのままではマージを止められない。fork PR では Secrets も渡されない。AWS に接続せず、plan が未実行であることを必須チェックで失敗として扱う方法を選ぶ。

A. plan チェックを明示的に失敗させる。本人が内容を確認して同一リポジトリの作業ブランチに取り込み、PR を作り直して全チェックを通す（推奨）
B. fork PR は自動でマージ対象外とし、静的チェックの結果だけを提供する。取り込みは本人が別の作業ブランチと PR で行う
X. Other (please specify)

[Answer]: A. plan を失敗にする (Recommended)

## Q2. [品質エンジニア] bootstrap の「CI 対象外」の範囲

チーム方針は bootstrap を CI 対象外とする一方、上流の CI 表には bootstrap でも validate と terraform test を実行すると書かれている。apply と実環境への plan は手元だけで実行するという決定は維持する。

A. bootstrap の fmt / validate / tflint / Checkov / モックによる plan モードの terraform test は CI に含め、実環境への plan / apply のみ手元に限定する（推奨: state と認証の設定にも品質チェックをかける）
B. bootstrap は静的チェックとテストも含めて CI 対象外とし、同じチェックを手元で実行する手順を用意する
X. Other (please specify)

[Answer]: A. 検査とテストを含める

## Q3. [リリースエンジニア] 文書のみの PR でのチェック

必須 workflow をパス条件で省略すると、必須チェックが Pending のままになる場合がある。小規模なリポジトリなので、まず確実なマージ条件を優先できる。

A. 文書のみでも master 向けの全 PR で全チェックを実行する（推奨: 判定が単純で、チェックの未実行を防げる）
B. workflow は全 PR で起動し、文書のみの場合は常時動く判定ジョブが変更対象を確認して成功を返す。インフラ変更時は 11 種類すべての成功を必須にする
X. Other (please specify)

[Answer]: A. 全チェックを実行

## Sources

- ../infrastructure-design/cicd-pipeline.md §1、§3
- ../../../../memory/team.md の Testing Posture と Deployment
- https://docs.github.com/en/pull-requests/reference/status-checks
- https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- https://docs.github.com/en/code-security/reference/secret-security/secret-types

## Consolidated Summary Confirmation

- GitHub Actions、master 向け PR、squash merge、11 種類の必須チェックを既決の設計から引き継ぐ。
- 外部の fork PR では AWS に接続せず、必須の plan チェックを明示的に失敗させる。本人が確認して同一リポジトリのブランチに取り込んだ別 PR で全チェックを通す。ローカルへのダウンロードは必須ではない。
- bootstrap の静的検査とモックによる plan モードの terraform test を CI に含める。bootstrap の実環境への plan / apply は手元だけで実行する。
- 文書のみの変更も含め、master 向けの全 PR で全チェックを実行する。
- AWS 識別子は Secrets から渡し、公開する plan は件数とリソースアドレスだけとする。plan ファイルは公開 artifact に保存しない。

この内容で CI の設定と品質基準を作成してよいですか？

- Looks correct
- Request changes

[Answer]: Looks correct

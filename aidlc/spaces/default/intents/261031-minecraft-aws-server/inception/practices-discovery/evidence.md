# Evidence

> リード（`aidlc-pipeline-deploy-agent`）が単独で作成・統合しました。Collaborators は off のため、サポートエージェントの contribution ファイルはありません。

## 1. 調査した情報源

| 情報源 | 確認内容 | 得られた事実 |
|---|---|---|
| `aidlc-state.md` | プロジェクト種別・スコープ | Greenfield、scope `infra`、depth Standard、test strategy Standard。code-generation / build-and-test / units-generation は SKIP |
| `project-description.json`（state の `**Project**` プレビュー） | 本人の依頼文 | 下記「2. 本人の明言」参照 |
| `.claude/scopes/aidlc-infra.md` | スコープ設定 | `skeleton: on`、`guard_policy: off`、`collaborators: off` |
| `aidlc/spaces/default/memory/org.md` | 5 セクションの既定値 | 提案の出発点として使用 |
| `aidlc/spaces/default/memory/team.md` / `project.md` | 既存の確定慣行 | いずれも空（ベースラインなし） |
| `git log` | 履歴 | コミット 2 件（`b8153b5 Initial commit`、`a97b410 Add CODEOWNERS file and enhance .gitignore rules (#2)`）。PR 番号付きマージがあり、PR 運用の実績と整合 |
| `git status` | 作業ツリー | `.gitignore` に未コミット変更（AI-DLC ブロック追加）。`.claude/`、`.mcp.json`、`aidlc/` が未追跡 |
| `.github/CODEOWNERS` | レビュー体制 | `* @YumaIshikawa18` のみ（1 名体制） |
| `.editorconfig` | 書式 | UTF-8、LF、indent 2 spaces、末尾改行、行末空白除去 |
| `.gitignore` | 慣行の痕跡 | Terraform 標準の除外（`**/.terraform/*`、`*.tfstate`、`*.auto.tfvars`、`*tfplan*`）、`.terraform.lock.hcl` の除外、Checkov 出力（`checkov-output`、`results.sarif`）の除外 |
| `bootstrap/`、`envs/prod/`（いずれも gitignore 対象） | 以前のローカル作業の痕跡 | `.tf` ソースはなく、`.terraform/`（AWS provider `6.70.0`）、`local.auto.tfvars`、`bootstrap/tfplan` のみ残存。`envs/prod/.terraform/modules/modules.json` に `../../modules/{iam,minecraft_server,network,security_group,ssm_parameters,world_backup}` の参照あり（`modules/` 自体は存在しない）。`local.auto.tfvars` は機密情報を含む可能性があるため内容は読んでいません |
| `practices-discovery-questions.md` | インタビュー回答 | 下記「3. インタビューの決定事項」参照 |

## 2. 本人の明言（原文のまま）

### 依頼文

「マイクラのサーバーをAWS上に建てたい。前に使っていたアカウントがありそれを使う予定。別リポジトリで既に構築はしていたことがあったので、GitHub ActionsによるCICDでやりたい。ただ新規でゼロから作りたい。terraformで構築したい。masterブランチは保護しているので、PRによる形をとる。環境先はaws login --profile personalの方のアカウント。MODにも対応したい。」

「MODにも対応したい」は機能要件のため本ステージでは扱わず、requirements-analysis に引き継ぎます。

### サマリー確認時の追加発言

「この回答で成果物は作成していい。ローカルで置くべき値については、CICDで実際はGitHubのSecretsにしまう等にして対応が良いかなと思うけどどうかな。publicリポジトリなので、アカウントIDは勿論のこと、IAMロール名なども極力出したくない。」

これに対し conductor が次の方針を提案し、成果物に反映しました。

- アカウント ID、IAM ロール ARN、state バケット名などは GitHub Secrets に置き、CI 実行時に `TF_VAR_*` と `-backend-config`（partial backend configuration）で渡す
- ローカルでは同じ値を gitignore 済みの `*.auto.tfvars` / `backend.hcl` に置く
- public リポジトリでは Actions のログと PR コメントが公開され、plan 出力に含まれる派生 ARN は自動マスクされないため、plan の全文は PR コメント・ログに出さない（サマリーのみ投稿し、必要に応じて `::add-mask::` でマスク）
- IAM ロール名などのリソース名はコードにハードコードせず、変数でパラメータ化する

この発言は `discovered-rules.md` の Mandated / Forbidden に 1 件ずつのハード制約として記録しています。

## 3. インタビューの決定事項

| 質問 | 選択 | 決定内容 | 反映先 |
|---|---|---|---|
| Q1 作業ブランチとマージ方式 | A | 短命ブランチ → PR → `master` へ squash merge | Way of Working |
| Q2 PR のマージ条件 | A | 必須 CI（fmt / validate / lint / スキャン / plan）がすべて成功すればセルフマージ可 | Way of Working |
| Q3 最初に通し構成を作るか | A | walking skeleton を作る。完了条件は Minecraft クライアントから接続できること | Walking Skeleton |
| Q4 PR の静的チェック・スキャン | A, B, C | `terraform fmt -check` + `terraform validate`、tflint（AWS ルールセット）、Checkov。Trivy は不採用 | Testing Posture |
| Q5 テストと品質基準 | A | 全モジュールに plan モードの `terraform test` を最低 1 つ + Q4 のチェックすべて通過。80% line-coverage の置き換え | Testing Posture |
| Q6 環境と apply のタイミング | A | 本番 1 環境。PR で plan を投稿、`master` マージ後に GitHub Environments の手動承認（本人）を経て apply | Deployment |
| Q7 認証と state | A | OIDC + IAM ロール（長期キーなし）、state は S3 ネイティブロック（`use_lockfile`）、bootstrap は手元で 1 回 apply | Deployment |
| Q8 構成とバージョン固定 | A | `bootstrap/` + `envs/prod/` + `modules/<name>/`、`.terraform.lock.hcl` をコミット、Terraform と AWS provider を `~>` で固定 | Code Style |
| Consolidated Summary Confirmation | Looks correct | 上記一式で確定。あわせて「2. サマリー確認時の追加発言」のとおり秘匿方針を追加 | 全体 |

## 4. org.md 既定値との差分と扱い

| 項目 | org.md の既定 | 本プロジェクトの確定内容 | 扱い |
|---|---|---|---|
| トランク名 | `main` | `master`（保護済み） | `master` に読み替え |
| Bolt の squash コミット名 | Bolt slug をコミット名にする | PR タイトル（英語・先頭大文字・50 文字以内・prefix なし）をそのまま使う | 本人のコミット規約を優先 |
| Testing Posture | `infra` は 80% line-coverage floor | 全モジュールに plan モードの `terraform test` + 必須チェック全通過 | Terraform に適した基準への置き換え（緩和ではない） |
| Deployment | staging 自動 + production 手動承認（tech lead + PO） | 本番 1 環境、本人による GitHub Environments 手動承認 | 1 名体制に合わせた読み替え。production の手動承認ゲートは維持 |

## 5. 推論（インタビューで確定済みのもの）

- 残存する `envs/prod/` と `bootstrap/` の痕跡から、本番 1 環境 + bootstrap 分離の構成を提案し、Q6 / Q7 / Q8 で確定しました。
- `.gitignore` の Checkov 出力除外から Checkov を候補に挙げ、Q4 で採用が確定しました。
- `.terraform.lock.hcl` の除外は HashiCorp の推奨と異なるため確認し、Q8 でコミットする方針に変更が確定しました（`.gitignore` の修正は Construction で実施）。

## 6. 未解決の論点（後続ステージへ引き継ぎ）

- **リージョン**: 未決定です。requirements-analysis で決めます。
- **インスタンスサイズ・コスト上限・起動停止スケジュール**: 未決定です。requirements-analysis / nfr-requirements で決めます。
- **MOD ローダー**（Forge / Fabric / NeoForge 等）と MOD の配布方法: 未決定です。requirements-analysis で決めます。
- **ワールドのバックアップ要件**（頻度・保持期間・復元手順）: 未決定です。requirements-analysis / nfr-requirements で決めます。
- **OIDC の信頼ポリシー・ロール ARN をログに出さない具体策**: 方針（GitHub Secrets に置く、plan はサマリーのみ、`::add-mask::`）は確定していますが、`aws-actions/configure-aws-credentials` の出力や Terraform のエラーメッセージに ARN やアカウント ID が出る可能性への具体的な対処（例: アカウント ID のマスク、`terraform plan -no-color` 出力の整形方法、失敗時ログの扱い）は未検証です。CI パイプライン設計時に確認が必要です（要確認）。
- **plan サマリーの投稿方式**: 件数とリソースアドレスのみを投稿する想定ですが、リソースアドレス自体に識別子が含まれないよう命名する必要があります。投稿方法（PR コメント / Job Summary）は CI 設計時に決めます。
- **ロールバック手順の具体化**: 「revert PR + 承認付き apply」を基本としますが、ワールドデータの復元を含む詳細は operation フェーズで定義します。
- **Terraform / AWS provider の具体的なバージョン**: `~>` で固定する方針のみ確定しています。具体値は Construction で決めます。
- **作業ブランチの命名規則**: Q1 では例として `feature/<topic>` を示しましたが、厳密な規則は定めていません（短命ブランチであれば命名は自由と解釈しています）。
- **未コミットの AI-DLC 一式**（`.claude/`、`aidlc/`、`.mcp.json`、`.gitignore` 変更）をどの PR でコミットするか: 本ステージでは決めていません。本人の判断に委ねます。

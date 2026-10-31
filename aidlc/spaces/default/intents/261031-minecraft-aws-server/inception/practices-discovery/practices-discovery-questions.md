# Practices Discovery — 質問

このリポジトリでの開発の進め方を決めるための質問です。各 `[Answer]:` にお答えください。
提案のたたき台は `team-practices.md` と `evidence.md` にあります。

## Q1. [リリースエンジニア] 作業ブランチとマージ方式

`master` は保護されていて PR 経由で取り込む前提です。作業ブランチの切り方と PR のマージ方式をどうしますか？（squash の場合、PR タイトル＝英語・先頭大文字・50 文字以内がそのまま `master` のコミットメッセージになります）

A. 短命ブランチ（`feature/<topic>` 等）→ PR → squash merge（推奨: 履歴が 1 PR = 1 コミットで追いやすい）
B. 短命ブランチ → PR → merge commit（ブランチ上のコミットをそのまま残す）
C. 短命ブランチ → PR → rebase merge
X. Other (please specify)

[Answer]: A

## Q2. [リリースエンジニア] PR のマージ条件

1 名体制なので、自分の PR を自分でマージする形になります。マージ前に何を必須にしますか？

A. GitHub Actions の CI（fmt / validate / lint / スキャン / plan）がすべて成功していればセルフマージ可（推奨）
B. CI 成功に加えて、plan の結果を PR 上で目視確認してからマージ（ルールではなく運用で）
C. 必須チェックは設けない（CI は参考情報）
X. Other (please specify)

[Answer]: A

## Q3. [リリースエンジニア] 最初に通し構成を作るか

最初に最小限の通し構成を作りますか？ walking skeleton とは、全体が端から端まで動く最小版を最初に作り、本格的な機能を入れる前に各部品がつながることを確認するやり方です。今回なら「ネットワーク → EC2 上で Minecraft サーバー起動 → 手元のクライアントから接続できる」までを GitHub Actions 経由で通し、その後 MOD・バックアップ・監視などを足していく形です。

A. はい。完了条件は「Minecraft クライアントからサーバーに接続できること」（推奨）
B. はい。完了条件は「サーバーのポート（25565）に TCP 接続できること」までで十分
C. いいえ。最初から MOD 対応・バックアップ込みで作る
X. Other (please specify)

[Answer]: A

## Q4. [品質エンジニア] PR で実行する静的チェック・セキュリティスキャン（select all that apply）

PR ごとに GitHub Actions で実行し、失敗したらマージをブロックするチェックを選んでください。

A. `terraform fmt -check` と `terraform validate`
B. tflint（Terraform のリンター、AWS ルールセット付き）
C. Checkov（IaC セキュリティスキャン。以前の `.gitignore` に出力除外の跡があります）
D. Trivy（旧 tfsec。IaC の設定ミス検出）
X. Other (please specify)

[Answer]: A, B, C

## Q5. [品質エンジニア] テストと品質基準

Terraform には「80% 行カバレッジ」がそのまま当てはまらないため、代わりの基準を決めたいです。どこまでやりますか？（基準を下げるのではなく、Terraform に合った基準への置き換えです）

A. `terraform test`（plan モードのみ、実リソースは作らない）を全モジュールに最低 1 つ + Q4 のスキャンすべて通過（推奨）
B. A に加えて、実際に apply して検証し破棄する統合テストも行う（コストと時間がかかります）
C. `terraform test` は使わず、Q4 のチェック + PR 上の plan 確認 + apply 後のスモークテスト（接続確認）で担保する
X. Other (please specify)

[Answer]: A

## Q6. [リリースエンジニア] 環境と apply のタイミング

環境の数と、`terraform apply` をいつ・どう実行するかを決めます。

A. 環境は本番 1 つ。PR で plan を PR コメントに出し、`master` マージ後に GitHub Environments の手動承認（自分で承認）を経て apply（推奨）
B. 環境は本番 1 つ。`master` マージで自動 apply（承認なし）
C. dev と prod の 2 環境。dev はマージで自動 apply、prod は手動承認
X. Other (please specify)

[Answer]: A

## Q7. [リリースエンジニア] GitHub Actions から AWS への認証と state の置き場所

GitHub Actions が personal アカウントに入る方法と、Terraform の state の保存先です。state 用の S3 バケット等は CI より先に必要なので、最初だけ手元（`--profile personal`）で作る形になります。

A. OIDC + IAM ロール（長期アクセスキーなし）、state は S3（S3 ネイティブロック）、bootstrap は手元で 1 回だけ apply（推奨）
B. OIDC + IAM ロール、state は S3 + DynamoDB ロック、bootstrap は手元で apply
C. IAM ユーザーのアクセスキーを GitHub Secrets に保存、state は S3
X. Other (please specify)

[Answer]: A

## Q8. [開発者] リポジトリ構成とバージョン固定

Terraform コードの置き方とバージョン管理の方針です。

A. `bootstrap/` + `envs/prod/` + `modules/<name>/` の構成、`.terraform.lock.hcl` はコミットする（`.gitignore` から外す）、Terraform と AWS provider は `~>` でマイナーまで固定（推奨: HashiCorp はロックファイルのコミットを推奨）
B. A と同じ構成だが、`.terraform.lock.hcl` は今まで通りコミットしない
C. モジュール分割せず、1 つのルートモジュールにまとめる
X. Other (please specify)

[Answer]: A

## Consolidated Summary Confirmation

Does this all look correct before I generate the artifact?

- Looks correct
- Request changes

[Answer]: Looks correct

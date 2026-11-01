# Infrastructure Design — 質問

NFR Design で仕組みはほぼ決まりました。ここでは、インフラと CI/CD の具体化に必要で、まだ決まっていない点だけを聞きます。

## Q1. [リリースエンジニア] PR の plan サマリーの出し先

public リポジトリでは、PR コメントも Actions の Job Summary も誰でも見られます。出す中身は、どちらの場合も件数とリソースアドレスだけです。

A. PR コメント（同じコメントを更新し続ける）と Job Summary の両方（推奨: PR の画面で変更内容がすぐ分かる）
B. Job Summary のみ（PR には CI の成否だけが出る）
X. Other (please specify)

[Answer]: A

## Q2. [リリースエンジニア] GitHub 側の設定（Branch protection の必須チェック、Environments `prod` / `ops`、Variables / Secrets）の管理方法

A. 手動で設定し、手順を README に書く（推奨: GitHub 用の Terraform provider の認証に PAT が必要になり、その管理が増えるため）
B. Terraform の GitHub provider でコード化し、`bootstrap/` から手元で apply する（PAT は手元だけで使う）
X. Other (please specify)

[Answer]: A

## Q3. [開発者] 依存の更新（Actions の SHA、Terraform / provider のバージョン、itzg イメージの digest、Lambda のライブラリ）

A. Renovate を使い、更新 PR を自動で作る。マージは自分で判断する（推奨: digest や SHA で固定したものを追従しやすい）
B. Dependabot を使う（Actions と Terraform provider には対応。イメージの digest の更新には工夫が必要）
C. 自動化しない（手動で更新する）
X. Other (please specify)

[Answer]: X. Dependabot＋composeで（サマリー確認時に A から変更。itzg の digest はホストで使う `docker/compose.yml` に書き、Dependabot の docker-compose 対応で追従する。サーバーの起動は `docker compose` で行う）

## Consolidated Summary Confirmation

Does this all look correct before I generate the artifact?

- Looks correct
- Request changes

[Answer]: Looks correct

## Requested Changes Feedback

[Answer]: Dependabot＋composeで

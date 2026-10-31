# CI Configuration

## 作成したもの

| ファイル | 内容 |
|---|---|
| `.github/workflows/pr.yml` | master 向け全 PR の 10 並列チェックと必須 plan |
| `scripts/ci/check.py` | 各チェックの実行、入力ファイルの存在検証、識別子チェック |
| `scripts/ci/plan.py` | 秘匿値のマスク、OIDC 認証後の plan、許可項目だけの PR コメント更新 |
| `tests/ci/test_ci.py` | 識別子と plan サマリーの正常・異常・境界条件テスト |
| `.tool-versions` / `.tflint.hcl` | ツールと AWS ruleset の固定 |
| `.github/dependabot.yml` | GitHub Actions の週次更新 PR |
| `.gitignore` | lockfile をコミット対象に戻す。backend / 入力 / plan 一時ファイルは除外 |

上流の `../infrastructure-design/cicd-pipeline.md` を具体化した。code-generation と build-and-test は infra の実行計画では SKIP のため、code-summary / build-and-test-summary / test-results は存在しない。存在しないテスト結果を引き継いだとは扱わない。

## トリガーと権限

- `pull_request` の master 向け全 PR。文書のみでも実行する（Q3）。パスフィルターなし。
- `ubuntu-24.04`、各ジョブ 20 分。PR 番号ごとに古い実行を取り消す。本番の apply / ops の排他とは分離する。
- workflow 既定は `contents: read`。plan のみ `id-token: write` と `pull-requests: write`。checkout の資格情報は保持しない。
- `pull_request_target` は使用しない。fork での write token / Secrets の受け渡しも GitHub 設定で無効に保つ。
- fork PR は AWS 認証より前に plan を失敗にする（Q1）。確認済みの変更は同一リポジトリのブランチと別 PR に取り込む。ローカル取得は必須でない。
- Dependabot PR も資格情報が通常の Actions と異なるため、AWS plan は失敗にする。確認後に本人のブランチと PR でやり直す。自動マージはしない。
- `needs: checks` + `if: always()` の plan が、先行チェック失敗や fork を成功扱いの skipped にしない。

## チェックと対象

10 チェックの実行方法と必須名は `quality-gates.md` に記載した。静的ジョブには AWS や GitHub の Secrets を渡さず、Docker にもホストの AWS 環境変数を渡さない。

bootstrap は fmt / validate / tflint / Checkov / terraform test の対象とする。bootstrap の実環境への plan / apply は手元だけで行う（Q2）。上流の「CI 対象外」は、今回の回答によりこの範囲に具体化された。

各 Terraform ルートと再利用モジュールには、コミット済み lockfile と `tests/*.tftest.hcl` を用意する。テストの各 run は明示的に `command = plan` を書く。provider は mock_provider を使い、CI の terraform test はネットワークなしのコンテナで行う。

未作成のディレクトリ・テスト・lockfile を成功として省略しない。Lambda のテストは `lambda/*/tests/test_*.py`、依存はルートの `requirements-test.txt` に固定して用意する。Bats は `tests/**/*.bats`、サーバースクリプトは `modules/minecraft_server/files/bin/*.sh` に置く。

## バージョンと取得元

GitHub の公式 repository API でリリースとコミットを確認した。各 `uses:` はリリースタグの 40 桁 SHA。ツールの完全なバージョンは `.tool-versions` を読む。Terraform は 1.17.1、tflint は 0.65.0、AWS ruleset は 0.50.0、Checkov は 3.4.0、ShellCheck は 0.11.0、Bats は 1.14.0、gitleaks は 8.30.1。Python は Lambda と同じ 3.13 系のタグを調査し、3.13.18 に固定した。

静的ツールは対応する公式イメージのバージョンタグを使用する。Actions の SHA と異なりコンテナのタグは digest による不変固定ではない。サーバーの itzg イメージを digest 固定する決定は別途維持する。

初期は共有キャッシュを使用しない。PR 間のキャッシュ汚染と複雑さを避け、実測後に導入を検討する。ECR / CodeArtifact は使わず、CI から配布物も公開しない。

## Secrets / Variables の契約

| 種別 | 名前 | 用途 |
|---|---|---|
| Secret | `AWS_PLAN_ROLE_ARN` | bootstrap で作る plan 専用ロール |
| Secret | `TF_STATE_BUCKET` | S3 state バケット名 |
| Secret | `TF_STATE_KEY` | prod の state オブジェクトキー |
| Secret | `TF_INPUTS_JSON` | Terraform 入力変数の JSON object。実行時に `TF_VAR_<key>` に展開 |
| Variable | `AWS_REGION` | `ap-northeast-1` |

`TF_INPUTS_JSON` は空でない JSON object とし、キーは Terraform の snake_case 変数名にする。例示用にも実値をコミットしない。具体的なキーは Environment Provisioning の Terraform 変数宣言と一致させる。Webhook / whitelist / RCON パスワードは Terraform へ渡さず、既決の SSM SecureString を用いる。

GitHub 側の設定は前段の決定どおり本人が手動で行う。ここでは Secrets の登録、branch protection の変更、push、PR 作成、AWS への接続は行っていない。required status checks に指定する 11 名は `quality-gates.md` のとおり。

## plan と公開情報

- 認証前に設定値・ロール ARN のアカウント部分をマスクし、configure-aws-credentials でもアカウントをマスクする。
- backend は部分設定を一時ファイルで渡す。state の S3 ネイティブロックを有効にし、plan は `-lock-timeout=5m`。
- Terraform の stdout / stderr を捕捉し、失敗時も生の診断を公開しない。調査は手元で行い、ログ全文を PR に貼らない。
- `show -json` から managed resource の actions と address だけを抽出する。値・outputs・state は公開しない。文字列 index は伏せ、設定された秘匿値も address から除く。未知の action、未完了 plan、不正な address は失敗。
- 件数と address のサマリーを Job Summary と PR コメントに出す。bot が作成した同じ marker のコメントを更新する。コメントのページングにも対応。
- plan、backend 設定は所有者のみアクセス可能な `.ci-private/` に一時保存し、成功・失敗のどちらも削除する。artifact へアップロードしない。

## 後続への引き継ぎと実行状況

CI 自体の単体テスト 15 件、Python / YAML / Bash 構文、workflow のマトリクスと権限・トリガー構成、既存追跡ファイルの識別子検査はローカルで検証した。

Terraform / Lambda / サーバースクリプト / Bats の本体とテスト、bootstrap、AWS Secrets はまだない。11 ジョブの実 CI 成功や AWS plan 成功は未検証であり、この時点でマージ可能とは扱わない。fmt 等も必要なモジュールがない場合は失敗にする。

Deployment Pipeline では deploy / start / stop / restore を実装する。Environment Provisioning ではアプリケーションの IaC とテストを作り、ここで定めた CI を実行できる状態にする。provider は Terraform `~> 1.17.0` と互換性を確認した AWS provider のマイナー制約を定義し、lockfile を生成する。Dependabot の terraform / pip / docker-compose 対象は、それぞれの実ファイルが作成された時点で追加する。

## Sources

- `ci-pipeline-questions.md` Q1〜Q3 と Consolidated Summary Confirmation
- `../infrastructure-design/cicd-pipeline.md`、`infrastructure-specification.md`
- `../nfr-requirements/security-requirements.md` NFR5.1〜NFR5.3、NFR5.14、NFR6.1〜NFR6.4
- https://docs.github.com/en/pull-requests/reference/status-checks
- https://docs.github.com/en/actions/reference/security/secure-use
- https://developer.hashicorp.com/terraform/cli/commands/plan
- https://api.github.com/repos/hashicorp/terraform/releases/latest
- https://api.github.com/repos/terraform-linters/tflint/releases/latest
- https://api.github.com/repos/bridgecrewio/checkov/releases/latest
- https://api.github.com/repos/python/cpython/git/matching-refs/tags/v3.13.
- https://api.github.com/repos/actions/checkout/commits/v7.0.1
- https://api.github.com/repos/hashicorp/setup-terraform/commits/v4.0.1
- https://api.github.com/repos/aws-actions/configure-aws-credentials/commits/v6.3.0

## Assumptions & Open Questions

None.

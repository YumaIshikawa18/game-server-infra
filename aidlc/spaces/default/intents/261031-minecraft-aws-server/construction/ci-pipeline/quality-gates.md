# Quality Gates

## 必須ステータスチェック

GitHub の master の required status checks に次の表示名を登録する。1 つでも失敗・未実行ならマージしない。

| チェック名 | 実行内容 | 合格基準 |
|---|---|---|
| `fmt` | Terraform fmt -check -recursive | 差分なし。対象モジュールが存在する |
| `validate` | bootstrap / envs/prod / modules/* を init -backend=false、validate | 全モジュール成功、lockfile あり |
| `tflint` | 同じ全モジュール、AWS ruleset | エラーなし |
| `checkov` | bootstrap / envs / modules / .github の Terraform と Actions | 全検査成功。抑止はリソースに理由を記載 |
| `terraform-test` | 全モジュールの terraform test、ネットワークなし | 各モジュール最低 1 テスト、各 run は plan、mock provider で全件成功 |
| `pytest` | Lambda 配下のテスト | watchdog / notifier の正常・異常・境界条件が全件成功 |
| `shellcheck` | サーバー Bash スクリプト、style レベル | 指摘なし |
| `bats` | tests 配下の Bats、AWS / Docker 等はスタブ | 正常系・少なくとも 2 種類の異常または境界条件が成功 |
| `identifier-check` | 追跡全ファイルの識別子スキャンと CI 単体テスト | 禁止識別子なし。誤検知と検出漏れのフィクスチャ成功 |
| `gitleaks` | 全 checkout 履歴を --redact で検査 | 秘密情報なし |
| `plan` | 全静的チェック成功後、envs/prod の実 plan とサマリー公開 | 同一リポジトリの本人管理 PR、認証・plan・コメント更新すべて成功 |

plan は fork / Dependabot / 先行チェック失敗を明示的に失敗とする。単なるジョブ skip をマージ許可に利用しない。

## テスト基準

上流 `../infrastructure-design/cicd-pipeline.md` の 11 チェックを維持し、bootstrap の静的検査とテストは今回の Q2 で明示的に対象に含めた。`../nfr-requirements/security-requirements.md` の NFR6.1 の許可例を保つ。

識別子検査は独立した 12 桁の数値、Webhook の実 URL、メール、グローバル IPv4 を対象にする。AWS 管理ポリシー ARN、式による参照、RFC1918、文書用アカウント・IPv4、noreply アドレスは許可する。SHA 内の数字や SSH clone URL をアカウント ID / メールと誤認しない。スキャン失敗時は値や該当行をログへ出さない。

Terraform の 80% 行カバレッジの代わりは、既に合意した「全モジュール最低 1 つの plan モードテスト + 全静的検査成功」。この基準を弱めない。今回追加した CI ヘルパーの 15 テストはサーバー本体のテストを代替しない。

## 実施した検証

| 検証 | 結果 |
|---|---|
| `python3 -m unittest discover -s tests/ci -v` | 15 件成功 |
| `python3 scripts/ci/check.py identifier-check` | 既存追跡ファイルで成功。CI では新規ファイルも checkout の追跡対象になる |
| Python AST、YAML、Bash 構文、workflow 構成 | 成功 |
| `git diff --check` | 成功 |
| Terraform / Lambda / Bash / Bats 本体の実チェック | 本体未作成のため未実行 |
| AWS OIDC / S3 backend / 実 plan / PR コメント | GitHub と AWS の設定前のため未実行 |

## 初回有効化の順序

- Environment Provisioning で本体・テスト・lockfile を用意し、AWS 認証なしの 10 チェックを通す。
- personal プロファイルの手元 bootstrap でバックエンドと最小権限 OIDC ロールを作る。
- GitHub の Secrets / Variables を登録し、同一リポジトリの PR で plan とコメントを確認する。
- 11 チェックの名前が実際に現れたことを確認し、本人が branch protection に登録する。
- fork の拒否、先行失敗から plan が失敗すること、plan のログ・コメントに識別子がないことを確認する。
- 全成功後に PR をマージする。本番 apply は Deployment Pipeline の prod 承認を経る。

## Sources

- `ci-config.md`、`ci-pipeline-questions.md`
- `../infrastructure-design/cicd-pipeline.md` §2〜§3
- `../nfr-requirements/security-requirements.md` NFR5.3、NFR5.14、NFR6.1、NFR6.4
- `aidlc/spaces/default/memory/team.md` Testing Posture

## Assumptions & Open Questions

None.

# Deployment Pipeline — 質問

prod 1 環境、master マージ後の本人承認、OIDC の plan / apply / ops の分離、Minecraft の事前保存・停止、失敗時通知、revert PR によるロールバックは既決として引き継ぐ。未決の点と実装時に判明した安全上の不足だけを確認する。

## Q1. [リリースエンジニア] 承認前後の plan の一致をどう保証するか

上流設計ではリソースアドレスと create / update / delete の組だけを比較する。その方法では、例えば同じ EC2 の update でも、変更先のサイズが違うことを検知できない。公開サマリーは従来どおり件数とアドレスだけに限定し、値そのものは公開しない。

A. 承認前後で再 plan し、変更前後の値・未確定値・outputs の変更も含めた正規化データのハッシュを内部で比較する。不一致なら apply せず、再実行と再承認を求める（推奨: plan の外部保存を増やさない）
B. 承認前の plan ファイルを非公開 S3 の専用領域に暗号化して一時保存し、承認後はその同じファイルを apply する。保存領域の権限と削除手順を追加する
X. Other (please specify)

[Answer]: A. 値も含めて比較（本人の回答: Aで良い。）

## Q2. [リリースエンジニア] apply と start / stop / restore の同時実行

既決の 2 つの concurrency グループは、承認待ちの deploy が stop を待たせないために維持する。ただし別グループなので、本当に apply が走り始めた後は restore 等と重なり得る。ホスト上の flock だけでは Terraform と運用 workflow 全体の競合は防げない。

A. 承認後の実処理だけ、共通の S3 ロックで直列化する。承認待ち中はロックしない。実 apply 中の運用操作は待機し、時間切れなら失敗と再実行案内。中断でロックが残った場合の確認・解除手順も用意する（推奨）
B. 追加ロックは使わず、apply 中には start / stop / restore を本人が実行しないという運用にする。同時に実行すると競合する制約を手順に明記する
X. Other (please specify)

[Answer]: A. S3ロックを追加 (Recommended)

## Q3. [セキュリティエンジニア] 上流で仮置きされた OIDC と SSM の権限

上流は次を assumption としている。① plan ロールの trust に同一リポジトリの master の sub を追加する。② apply ロールに、対象インスタンスと mc-stop / mc-health-check だけの SSM 実行権限、および結果確認の権限を追加する。目的は承認前の plan、置き換え前の保存・停止、適用後の確認である。

A. 上記の用途に限定して採用する。Q2 で S3 ロックを選んだ場合も、apply / ops に専用ロックキーだけの権限を追加し、ops には Terraform state 本体を触らせない（推奨）
B. 権限の詳細を確認してから決める。追加する操作とアクセス対象を先に説明する
X. Other (please specify)

[Answer]: A. 用途を限定して採用 (Recommended)

## Sources

- ../../construction/infrastructure-design/cicd-pipeline.md §2、§4 と Assumptions & Open Questions
- ../../construction/nfr-design/reliability-design.md §6〜§8
- ../../construction/ci-pipeline/ci-config.md と quality-gates.md
- https://developer.hashicorp.com/terraform/internals/json-format
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html

## Consolidated Summary Confirmation

- 本番は prod のみ。master マージ後、plan サマリーを確認して本人が承認し、その後 apply する。
- 承認前後で再 plan し、変更対象・操作だけでなく、変更前後の値・未確定値・outputs の変更も含めて内部でハッシュ比較する。不一致なら apply せず、再実行と再承認を求める。
- 公開する plan サマリーは件数とリソースアドレスだけ。設定値や plan ファイルは公開しない。plan ファイルの非公開 S3 保存も追加しない。
- deploy と運用操作の実行グループは分けたまま、実処理だけ共通の S3 ロックで直列化する。deploy の承認待ち中はロックせず、stop を妨げない。実 apply 中は運用操作が待機し、時間切れ時は失敗と再実行案内を出す。中断時のロック確認・解除手順を用意する。
- plan ロールの trust に同一リポジトリの master を追加する。apply ロールには対象インスタンスと mc-stop / mc-health-check に限定した SSM 実行・結果確認権限を追加する。S3 ロック用権限は専用キーだけに限定し、ops には Terraform state 本体への権限を与えない。
- 起動・停止・復元は master から本人だけが実行する。置き換え時は事前保存・バックアップ・停止を行い、適用後は既決のヘルスチェックを実行する。失敗は SNS に通知する。
- ロールバックは revert PR、必須チェック、マージ、prod 承認、apply の順。ワールドの復元が必要なら更新前のバックアップを復元する。

この内容でデプロイ設定とロールバック手順を作成してよいですか？

- Looks correct
- Request changes

[Answer]: Looks correct

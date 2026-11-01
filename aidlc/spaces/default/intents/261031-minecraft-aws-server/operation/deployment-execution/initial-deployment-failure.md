# 初回デプロイの失敗と修正

## 上流と実行

- `../deployment-pipeline/cd-config.md` の承認前後の比較と共通 S3 ロックに従う初回 Deploy。
- `../deployment-pipeline/deployment-strategy.md` の本人承認付き apply。
- `../environment-provisioning/environment-inventory.md` の prod 未構築からの初回適用。
- マージコミット `2fcb847`、Deploy run `41295324864`。本人が prod の plan を確認して承認したが、apply ジョブは失敗した。

## 原因の検証

| 問題 | 証拠 | 修正 |
|---|---|---|
| plan の比較が一覧の列挙順に依存 | 同じ入力・資格情報で prod の plan を連続生成すると、差分は `relevant_attributes` の順序だけで、修正前の digest は不一致。入力 JSON とローカルの変数は一致、比較対象にセッション依存 ARN はなし | 参照元の一覧を JSON の正規形で並べ替える。属性パス内の順序・内容、リソース値・変更操作の比較は維持 |
| ETag を指定したロック解除に必要な読み取り権限がない | AWS 公式仕様は `s3:DeleteObject` と `s3:GetObject` の両方を要求。既存の共通ロック権限には GetObject がなく、失敗 run の後もロックが残存 | apply と ops に専用のロックオブジェクト 1 キーだけの GetObject を追加。DeleteObject の If-Match 条件は維持 |
| 最初の失敗が後始末の失敗に隠れる | 公開ログには従来の汎用エラーだけが出るため、直接の失敗とロック解除失敗を区別できない | 失敗箇所の固定ラベル・エラー種別・検査済み AWS エラーコードを出す。例外本文や引数・識別子は出さない。例外の連鎖も最大 4 件まで追う |

修正後に同じ prod plan を再度 2 回生成し、参照元の一覧順が変わっても digest が一致することを確認した。古い CI の digest と一致しないのは、古い並び順を含む比較方式によるものなので、その承認を新しいコードで使い回さない。

## 検証結果

- CD の Python テスト 38 件成功。参照一覧の並び替えを同じと判定し、参照内容・属性パス内の順序の変更は拒否する回帰テストを追加。
- エラー連鎖を表示しても例外本文を含めず、想定外のラベルやコードを表示しないテストを追加。
- bootstrap の mock provider / plan モードのテスト 9 件成功。apply / ops の GetObject が専用ロックだけに限定され、条件付き削除が維持されることを確認。
- CI 用 Python テスト 15 件と識別子検査が成功。
- bootstrap の実環境 plan は追加 0 / 変更 2 / 削除 0。対象は apply の state 用管理ポリシーと ops の inline policy。
- AWS Access Analyzer でポリシー文書 9 件を検証し、エラーなし。既存の If-None-Match の文字列比較に関する警告 2 件は維持。

## 状態と復旧

- 管理対象の EC2 は未作成。prod の Terraform state オブジェクトも未作成であることを確認。
- 運用ロックは残っている。失敗 run の終了、進行中の別処理の不在、対象ロックの所有者を再確認してから、`../deployment-pipeline/rollback-runbook.md` の条件付き解除を行う。無条件削除や時間だけでの解除はしない。
- bootstrap の追加変更は未適用。本人がレビュー済み plan をローカルから適用する。
- 修正を PR 経由で master に取り込み、新しい Deploy の plan を改めて本人が確認・承認する。

## セキュリティとロールバック

追加権限は共通運用ロック 1 オブジェクトの読み取りだけ。ops の state 本体へのアクセスは許可しない。OIDC の trust、permissions boundary、ネットワーク、暗号化の設定は変更しない。承認前後の比較を無効化せず、参照一覧という順序を持たない集合だけを正規化する。

戻す場合は修正 PR の revert と、本人による bootstrap の plan / apply で権限を戻す。新たなロックを無条件削除して rollback しない。

## Sources

- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41295324864
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-deletes.html
- https://developer.hashicorp.com/terraform/internals/json-format
- `scripts/cd/deploy.py`、`bootstrap/iam.tf`、`bootstrap/tests/security.tftest.hcl`、`tests/cd/test_cd.py`

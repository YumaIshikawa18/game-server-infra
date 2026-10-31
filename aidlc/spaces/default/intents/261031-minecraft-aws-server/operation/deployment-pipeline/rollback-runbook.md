# Rollback Runbook

## 判断と担当

担当・承認者・エスカレーション先は本人（GitHub Variable の OPERATOR_LOGIN）。本人が GitHub Actions、AWS Console、SNS のメール / Discord 通知で状況を確認する。個人のメールやログイン名は public な手順に書かず、GitHub 設定と非公開の連絡先を使う。

起動・復元・apply・通知失敗、または適用後の Minecraft ヘルス失敗でこの手順を使う。state やワールドを推測で巻き戻さない。まず進行中の処理とバックアップを確認する。自動のインフラ rollback は行わない。

## インフラを戻す

- 直前に成功していたコミットと変更 PR を確認する。
- 対象 PR を revert する作業ブランチと PR を作る。
- fmt / validate / tflint / Checkov / terraform-test / pytest / shellcheck / bats / identifier-check / gitleaks / plan の全成功を確認する。
- master へ squash merge する。新しい deploy の plan サマリーと削除・置き換え警告を確認し、prod を本人が承認する。
- 再 plan の不一致なら、実行をやり直して新しいサマリーを確認・承認する。比較を無効にしない。
- apply と Minecraft ヘルスを確認する。停止中なら start を実行し、最後に Minecraft クライアントから接続する。

## Minecraft / ローダー / MOD とワールドを戻す

- インフラ・設定の revert PR を先に通す。バージョンの後退にワールド互換性があるかを確認する。
- stop workflow で停止する。
- 更新前の stop/ バックアップを選ぶ。最新版が更新前とは限らないため、作成時刻と対象更新を確認する。
- master の restore workflow にその .tar.zst キーを指定する。キーには識別子や秘密情報を含めない。
- 成功後もインスタンスは停止している。start workflow を実行してヘルスとクライアント接続を確認する。
- 復元に失敗したら、原本のバックアップと world.pre-restore/ を保持し、ホスト側の失敗内容を AWS の非公開画面で確認する。失敗した状態で起動を繰り返さない。

## 運用ロックが残ったとき

待機は最大 5 分。時間切れなら、別の処理が終わってから workflow を再実行する。ロックの経過時間だけを理由に解除しない。

解除が必要な場合は、本人が次をすべて確認する。

- 新しい apply / start / stop / restore を開始しないようにする。
- ロックの run_id / attempt と対応する GitHub Actions の実行を確認する。
- Terraform apply とホスト側 SSM コマンドが進行中でないことを AWS の非公開画面でも確認する。runner が終了していても AWS 操作が完了したとは限らない。
- EC2 の状態、復元用 mc:mode タグ、ワールドの退避、バックアップの有無を確認する。
- 復元途中なら停止を確認し、ワールドの整合性を確認してからタグを外す。状態が分からなければロックを保持する。

確認後、ローカルの personal プロファイルで専用ロックだけを条件付きで削除する。MC_LOCK_BUCKET / MC_LOCK_KEY は gitignore 済みの非公開設定から読み込み、端末で set -x を使わない。次のコマンドは公開 CI で実行しない。

```bash
lock_etag=$(aws --profile personal s3api head-object \
  --bucket "$MC_LOCK_BUCKET" --key "$MC_LOCK_KEY" \
  --query ETag --output text)
aws --profile personal s3api delete-object \
  --bucket "$MC_LOCK_BUCKET" --key "$MC_LOCK_KEY" \
  --if-match "$lock_etag"
```

ETag が変わって拒否されたら、別の所有者になっている可能性があるため最初から確認する。無条件削除に切り替えない。Terraform の state / *.tflock はこの操作の対象にしない。運用ロックを解除しても、Terraform state ロックは解除されない。

解除後は既存の承認を使って途中から apply を再開せず、最新 master の新しい deploy で plan と本人承認をやり直す。

## 緊急に課金を止める

通常は stop workflow を使う。実 apply が進行中なら、まずその処理の状態を確認する。復旧手順で排他が確認でき、SSM が応答しない場合は、本人が personal プロファイルで対象の管理 EC2 を直接停止する。この場合は最終保存・バックアップを保証できない。次回起動前にワールドと必要なバックアップを確認する。

停止しただけで state ファイルを過去版に戻さない。Terraform の実リソースとの対応を失うため、最新 state から次の plan を確認する。

## state の破損

- すべての Terraform 実行を止める。
- S3 バージョニングで復元候補を確認し、現在版も保全する。
- 本人の personal プロファイルで対象の state キーだけを復元する。state の中身や識別子をログ・PR コメント・公開 artifact に出さない。
- 実リソースと復元 state の一致を plan で確認する。予期しない recreate / delete がある場合は apply しない。
- Terraform state の force-unlock は、対応する実行が終了したことを確認したときだけ検討する。S3 の運用ロック解除とは別の操作である。

## 通知が届かない

SNS Publish の失敗は GitHub Actions に汎用エラーを表示する。Discord が届かなくてもメールと Actions を確認する。認証失敗や runner 強制終了では SNS を送れない場合があるため、GitHub の workflow 失敗通知も有効にする。AWS の詳細ログは非公開のまま調べる。

## 復旧の完了条件

- 最新の意図した構成で plan / apply が成功する。
- 停止中なら起動し、SSM と server list ping が成功する。
- Minecraft クライアントで接続でき、必要なワールドと MOD を確認できる。
- ロックと復元タグの状態が正常で、通知が届く。
- データ損失があれば、復元したバックアップ時刻までの範囲を本人が把握する。

## Sources

- `cd-config.md`、`deployment-strategy.md`、`deployment-pipeline-questions.md`
- `../../construction/ci-pipeline/ci-config.md`、`quality-gates.md`
- `../../construction/infrastructure-design/infrastructure-specification.md`、`cicd-pipeline.md`
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-deletes.html
- https://developer.hashicorp.com/terraform/cli/commands/force-unlock

## Assumptions & Open Questions

None.

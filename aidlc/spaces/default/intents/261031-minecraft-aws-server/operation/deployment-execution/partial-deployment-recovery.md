# 部分適用後の復旧準備

## 対象と状態

`../deployment-pipeline/cd-config.md`、`../deployment-pipeline/deployment-strategy.md`、`../deployment-pipeline/rollback-runbook.md`、`../environment-provisioning/environment-inventory.md` を前提とする。infra では Build and Test が対象外のため、実装の検証は既存 CI と対象モジュールの plan モードテストで行う。

PR #4 はマージ済み（`909a373`）。本人が承認した Deploy run `41296893187` は plan 成功後、2026-11-01T10:20:45Z に apply が失敗した。失敗通知は成功した。Terraform state と一部リソースは作成済みで、運用ロックは保持されている。初回失敗 run 専用の解除スクリプトは今回に使わない。

## 原因と修正

| 原因 | 確認した根拠 | 修正 |
|---|---|---|
| EC2 の作成先と親リソースで認可条件が異なる | CloudTrail で CreateSubnet / CreateRouteTable / CreateSecurityGroup / CreateFlowLogs が AccessDenied。公式サービス認可情報でも既存 VPC の ResourceTag と新規対象の RequestTag は別 | 同じ Project の既存 VPC、ENI 作成先の subnet / SG だけに作成操作を許可。新規対象の RequestTag 条件も維持 |
| タグ付き S3 バケット作成の権限不足 | CloudTrail の CreateBucket が s3:TagResource の不足で拒否 | バックアップバケットだけに s3:TagResource を追加 |
| SNS 購読の認可対象が不適切 | GetSubscriptionAttributes が AccessDenied。公式サービス認可情報の対象は topic | plan / apply の購読操作を既定のプロジェクト topic パターンに修正 |
| SSM 文書の引数名が無効 | CreateDocument が InvalidDocumentContent: Parameter name require_backup is not alpha-numeric | 文書と CD の呼び出しを requireBackup に統一。バックアップ必須の動作と allowedValues は維持 |
| Lambda の予約同時実行数を確保できない | PutFunctionConcurrency が未予約枠の最低値 10 を下回るとして拒否。GetAccountSettings と Service Quotas の両方で東京の上限 10、未予約 10 を確認 | Q10で上限1,000への引き上げを申請したが、必要性を再検討し、Q12で本人が共有枠を使う構成を選択。2関数をreserved_concurrent_executions=-1に変更し、引き上げへの依存を解消。以前の申請はCASE_OPENEDのままで、取り下げは未実施 |
| 部分作成済みリソースのrefreshに必要な読み取り不足 | PR #5のCI run 41303713973のplanだけ失敗。CloudTrailでci-planのs3:ListTagsForResourceとlambda:ListVersionsByFunctionがAccessDenied | plan / applyの読み取りとバックアップバケットのrefreshに追加。バケットとプロジェクトのLambdaだけに限定 |
| Lambdaの署名設定の読み取り不足 | CI run 41304519371 attempt 2のCloudTrailでlambda:GetFunctionCodeSigningConfigがAccessDenied。provider 6.71.0のresourceFunctionFlattenは署名未使用でもzip関数の読み取り末尾でこのAPIを呼ぶ | plan / applyの共通読み取りに対象関数だけのGetFunctionCodeSigningConfigを追加。署名設定を変更する権限は追加しない |
| SGルール作成の認可不足（apply前の予防修正） | 現在のapplyロールで、ingress / egressルール作成時のCreateTagsがimplicitDenyになることをIAMシミュレーションで確認。公式のサービス認可情報でも親SGと新規ルール、CreateTagsを別々に認可する | 親SGのResourceTag条件を保ち、新しいルールはRequestTagで同じProjectに限定。CreateTagsはAuthorizeSecurityGroupIngress / Egressの作成時だけに限定 |
| Budgetsのタグ読み取り不足 | CI run 41306307597 attempt 2の診断はplan中のAccessDeniedException。米国東部のCloudTrailでci-planのbudgets:ListTagsForResourceが拒否されていた。東京側のCloudTrailだけでは確認できなかった | 共通読み取りに対象のプロジェクト予算だけのListTagsForResourceを追加。予算の値や通知設定は変更しない |

Lambda ロールの伝播待ちと S3 設定の競合も CloudTrail にあったが、その後の処理が進んでいる。恒久的な権限不足や上記の最終失敗とは分けて扱う。

## 検証

- bootstrap の plan モードテスト 10 件、minecraft_server の 8 件が成功。
- Python CI テスト 15 件、CD テスト 38 件が成功。
- 対象2モジュールの validate、全体の fmt -check、識別子検査、git diff --check が成功。
- 保存済み bootstrap plan に含まれるポリシーについて IAM シミュレーション 33 件が成功。同じ Project / 別 Project / タグなしの EC2、対象外 S3、対象外 SNS を検査。
- IAM Simulator は sns:GetSubscriptionAttributes の mixed-case 表記で、Resource が * の単独 Allow でも implicitDeny を返した。CloudTrail の認可要求に合わせた SNS: 表記で再検証した。ポリシー本文は変更していない。この結果だけで実際の apply 成功とはみなさない。
- Q12後: notifier / watchdogのplanモードテスト6件、bootstrapの11件が成功。Checkovのmodulesスキャンは103件成功・失敗0・スキップ28件（今回合意したCKV_AWS_115の2件を含む）。外部のガイドライン取得はネットワークを無効にしたローカル実行では不可だが、ローカルのチェック本体は実行した。
- 新しい読み取り2操作の対象外リソース拒否を加え、IAMシミュレーション43件が成功。Access Analyzerはポリシー文書9件にエラーなし。
- Access Analyzer はポリシー文書 9 件にエラーなし。既存の条件付き S3 書き込みに関する警告 2 件は維持。
- bootstrap の実環境 plan: **追加 0 / 変更 5 / 削除 0**。apply の compute / storage / services / reads と plan の inline policy が対象。Q11で本人が適用しExit code 0を確認。2026-11-01T11:50:17Zの再planは**追加0 / 変更0 / 削除0**。
- refresh読み取り追加分のbootstrap planは**追加0 / 変更3 / 削除0**。applyのreads / storageとplanのinline policyが対象。Q13で本人が適用済み。2026-11-01T12:05:44Zの再planは**追加0 / 変更0 / 削除0**。
- Lambdaの読み取り処理全体をprovider 6.71.0の実装で確認した。GetFunction、必要時のGetFunctionConcurrency、ListVersionsByFunction、最後のGetFunctionCodeSigningConfigをテストに含め、不足する修正前の失敗と修正後のbootstrap 11件成功を確認した。署名設定の追加2件はQ14で本人が適用し、その後のbootstrap planで差分0件を確認した。
- SGルール作成の予防修正はbootstrapテスト12件、IAMシミュレーション66件で検証。親SG・新規ルール・作成時タグの同じProject / 別Project / タグなしと、未所有ルールへの直接タグ付け拒否を含む。最新bootstrap planは**追加0 / 変更1 / 削除0**（applyのcompute）で未適用。Access Analyzerはエラー0・既存警告2件。
- CI run 41305162685 attempt 2ではplanが引き続き失敗し、CloudTrailに参照系のAccessDeniedは見つからなかった。生の診断を公開しないまま切り分けるため、処理名・既知の公開API名とエラー分類だけを表示する診断を追加した。Python CIテスト22件 / CD38件が成功。識別子や未知のラベルを例外に含めても表示しないことを検証した。
- 上記の東京側で見つからなかったエラーは、米国東部のBudgetsのタグ読み取りとして確認した。SGルールと合わせた最新bootstrap planは**追加0 / 変更3 / 削除0**（applyのcompute / reads、planのinline policy）。Terraformテスト12件、Python CI23件 / CD38件、IAMシミュレーション70件が成功。Access Analyzerはエラー0・既存警告2件。Q15で本人が適用（2026-11-01T12:35:33Z）。再planは**追加0 / 変更0 / 削除0**。CI run 41307007208のplanはattempt 2で成功し、PRのprod planは**追加23 / 変更0 / 削除4**。
- prod の読み取り plan: **追加 23 / 変更 0 / 削除 4**。削除4件は tainted な Lambda 2件とメール購読2件の再作成。初回の追加81件とは異なる。再作成後のメール購読確認が必要。Lambda 上限の解消と bootstrap 反映後、最新ソースで再 plan する。

## セキュリティと復旧順序

既存リソースへの追加権限は同じ Project の EC2、バックアップバケット、プロジェクトの SNS topic / Lambda に限定する。OIDC trust、permissions boundary、CI ロール編集の禁止、state の分離、ネットワークと暗号化は維持する。

Q12で本人が承認した変更により、Lambdaは各関数の予約同時実行数1を使わず共有枠を使う。現在のアカウント上限は10だがTerraformで10に固定するものではなく、以前の申請の承認等で共有枠は変わり得る。watchdogは5分間隔・最大30秒で、停止対象はIAMと管理タグで限定する。notifierは通知が並行し得るが、Discordの429を既存の再試行で扱う。通知の直列化や厳密な重複排除を保証しない。Checkov CKV_AWS_115だけを両関数のローカル注記で例外とし、他のチェックを維持する。設定を戻す場合は予約枠を確保できる上限を先に確認し、revert PRと本人承認付きapplyで戻す。

1. Q12の共有枠設定をPRに反映する。上限引き上げの承認をデプロイ条件にしない。以前の申請は未取り下げであることを本人に知らせる。
2. **完了**: 本人がレビュー済みbootstrap planをローカルから適用し、再planで差分0件を確認した。
   **完了**: 追加のrefresh読み取り3件もQ13で本人が適用し、再plan差分0件を確認した。
   **完了**: Lambda署名設定読み取りの追加2件もQ14で本人が適用し、再plan差分0件を確認した。
   **完了**: SGルール作成とBudgetsタグ読み取りをまとめた追加3件もQ15で本人が適用し、再plan差分0件を確認した。
3. **完了**: PR #5の最新HEAD f56f72aでCI 11件成功、Codexレビューの指摘なし、未解決スレッド0件を確認した。
4. **完了**: 今回専用の`.aidlc-engine/partial-deploy-unlock.py --release`をQ13で本人が実行し、成功した。失敗run終了、進行中の運用なし、管理EC2なし、ワールドEBS未接続、進行中SSMなし、部分stateあり、stateロックなし、所有者一致を再確認して同じETagの運用ロックだけを削除する。AWSをmockした3テスト（14種の拒否条件を含む）も成功。解除後のhead-objectは404で、運用ロック不在を確認した。stateは保持されている。
5. 本人がマージし、新しい Deploy の plan と再作成対象を確認して prod を承認する。
6. apply、SSM、Minecraft スモーク、通知、クライアントからの実接続を確認する。ここまで未完了なので、この段階を完了として扱わない。

戻す場合は `../deployment-pipeline/rollback-runbook.md` に従い、revert PR と新しい承認付き apply を使う。state を過去版に巻き戻したり、部分作成リソースを直接削除したりしない。bootstrap の権限変更を戻す場合も本人が plan を確認して適用する。

## Sources

- https://github.com/YumaIshikawa18/game-server-infra/actions/runs/41296893187
- https://servicereference.us-east-1.amazonaws.com/v1/ec2/ec2.json
- https://servicereference.us-east-1.amazonaws.com/v1/sns/sns.json
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-create-tag.html
- https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-syntax-data-elements-parameters.html
- https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html
- https://github.com/hashicorp/terraform-provider-aws/blob/v6.71.0/internal/service/lambda/function.go#L1906
- https://servicereference.us-east-1.amazonaws.com/v1/lambda/lambda.json
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/supported-iam-actions-tagging.html
- https://github.com/hashicorp/terraform-provider-aws/blob/v6.71.0/internal/service/budgets/tags_gen.go
- https://servicereference.us-east-1.amazonaws.com/v1/budgets/budgets.json
- `bootstrap/apply.tf`、`bootstrap/iam.tf`、`modules/minecraft_server/ssm.tf`、`scripts/cd/deploy.py`

## Assumptions & Open Questions

- 以前のLambda上限引き上げ申請の取り下げ。共有枠設定のデプロイに増枠の承認は不要。

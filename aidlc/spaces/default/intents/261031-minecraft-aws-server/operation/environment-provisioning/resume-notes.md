# 次回の再開メモ

## 現在地

Environment Provisioning の実装・検証途中で本人の希望により中断。Deployment Pipeline は承認済み。Environment Provisioning は未完了・未承認。

## 保存した実装

- deploy / start / stop / restore の workflow と共通制御、ロールバック手順。
- network モジュールとモックテスト。fmt / validate / terraform test 4 件が成功。
- bootstrap の state バケット、既存 OIDC 再利用、3 CI ロール、app 用 boundary と対象限定の権限。モックテスト 3 件が成功。
- 非公開入力を生成する scripts/local/prepare.py と、値を表示しない plan / apply 用 scripts/local/terraform.py。
- IAM の8文書を AWS Access Analyzer ValidatePolicy で検証し、エラーは修正した。S3 If-None-Match のリテラル * に関する警告が2件残る。
- プロジェクトとローカルのモデルプリセットを thorough に変更済み。ローカル設定は gitignore の対象。

## 2026-11-01 の進捗（bootstrap 完了）

- Checkov は bootstrap で failed 0 / 理由付き抑止 7。
  - CKV_AWS_393 は誤検知だった。Checkov が `local.ci_subjects[each.key]` と分割した locals の補間を評価できないため。for_each を subject の map にして `each.value` で渡し、`var.github_repository` を直接使う形に変更した。CI では `tests/checkov/<dir>.tfvars.json` のダミー値を `--var-file` で渡す。
  - CKV_AWS_355 / 290 は boundary の SSM エージェント文が原因。`ssm:UpdateInstanceInformation` をインスタンス ARN に限定し、`ssmmessages:*` は公式どおり `*` のまま（リソース制限非対応）。
  - S3 の 4 件は Q3 で本人が B を選択。ログ専用バケット（`logs.tf`、SSE-S3、保存 90 日）を追加し、state のアクセスログを `state/` に送る。残りはリソース限定の理由付き抑止。
- fmt / validate / terraform test 5 件 / tflint / 識別子チェックが成功。
- 本人の承認を得て bootstrap を personal で適用した（追加 30）。再 plan は 0 / 0 / 0。出力は `.ci-private/bootstrap-outputs.json`（gitignore 済み）。bootstrap の state は手元の `bootstrap/terraform.tfstate`（gitignore 済み）。

## 次に行うこと

- Q3 の追加分を含めたサマリーを、成果物の作成前に本人へ再確認する。
- envs/prod のバックアップバケットは、ログバケットの `backup/` にアクセスログを送る（バケットポリシーは bootstrap 側で許可済み）。ログバケット名は変数にして `TF_INPUTS_JSON` から渡す。
- plan ロールの S3 読み取り権限が、aws_s3_bucket の refresh に必要な Get 系 API を満たすか、envs/prod の plan で確認する。
- envs/prod と残りのモジュール（minecraft_server、backup、monitoring、Lambda）、ホスト処理、SSM 文書、GitHub 設定はまだ実装・構築が残っている。walking skeleton の順（ネットワーク → EC2 → クライアント接続）で進める。
- 本番適用は既決どおり PR → master → prod 承認。

## AWS の確認結果

personal の再認証を完了し、既存の allowed_account_ids と一致した。既存 VPC は2つ、予定の 10.20.0.0/24 と重複なし。管理タグ付きインスタンスは0台。GitHub OIDC プロバイダーは既存のものを再利用する。対象 SSM 文書は存在しなかった。m7g.xlarge は東京の a / c / d で提供されている。

AWS リソースの作成・変更は行っていない。実行したのは読み取り、Terraform plan、ポリシー検証のみ。次回は必要なら personal を再認証し、許可アカウントの一致を改めて確認する。

GitHub の prod / ops Environment と Secrets は未設定だった。設定の書き込みは行っていない。

## 非公開ファイル

既存の bootstrap/local.auto.tfvars と envs/prod/local.auto.tfvars を保持した。生成した bootstrap/generated.auto.tfvars.json と .ci-private/ 内の plan・診断・検証結果は gitignore 済みでありコミットしない。内容や実識別子をログ・PR に出さない。

## 確定した追加判断

- 初回ワールドは新規作成。
- watchdog の EventBridge Scheduler を維持し、専用 app-scheduler ロールを追加する。追加 PassRole は専用ロール ARN と scheduler.amazonaws.com の組だけ。全 app ロールに boundary を必須とする。
- 上記を含むサマリーは本人が Looks correct で確認済み。

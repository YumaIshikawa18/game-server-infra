# Environment Provisioning — 質問

## 引き継ぐ決定

- Terraform でゼロから実装する。bootstrap / envs/prod / modules の構成。
- prod 1 環境、東京、専用 VPC、ARM のオンデマンド EC2、既定 m7g.xlarge、独立した暗号化ワールド EBS。
- 最初に最小構成のクライアント接続を確認し、その後 MOD・バックアップ・監視を積み上げる。ローダーは設定で差し替えられるようにする。
- bootstrap の実 plan / apply は personal プロファイルで手元から実行。本番 apply は PR、master マージ、prod 承認付き workflow を通す。
- 識別子は GitHub Secrets または gitignore 済みのローカルファイルだけに置く。既存の local.auto.tfvars の allowed_account_ids は保持する。
- Deployment Pipeline で合意した plan の比較、S3 運用ロック、対象限定の SSM 権限を実装する。

## 現在の準備状況

- Terraform の実装ファイルはまだない。承認済みの設計と CI/CD 設定から実装を準備する。
- personal プロファイルは存在するが認証期限切れ。コード作成と AWS 不要のテストを先に進め、AWS の確認・適用の直前に再ログインする。
- GitHub の prod / ops Environment は未作成、登録済み Secrets は 0 件。既決どおり設定手順を用意する。
- AWS の実リソース一覧は認証前のため未確認。既存リソースがないとは断定しない。

## Q1. [プラットフォームエンジニア] 初回に使うワールド

コードをゼロから作る決定は引き継ぐ。ワールドデータも新規にするか、以前のサーバーのワールドだけ引き継ぐかは未確認なので、初回構築と復元の手順を決めたい。

A. 新しいワールドで始める（推奨: 最初の接続確認を単純にできる）
B. 以前のワールドを引き継ぐ。コードは新規実装し、ワールドデータだけを非公開のバックアップ経由で移行する
X. Other (please specify)

[Answer]: A. 新しいワールド (Recommended)

## Sources

- ../../construction/infrastructure-design/infrastructure-specification.md
- ../deployment-pipeline/cd-config.md
- ../../inception/practices-discovery/practices-discovery-questions.md Q3、Q6〜Q8
- ../../inception/requirements-analysis/requirements-analysis-questions.md
- 読み取り確認: Terraform ファイル一覧、personal の認証状態、GitHub の Environment と Secrets の有無。識別子・設定値は出力していない。

## Q2. [プラットフォームエンジニア] 定期監視用 Scheduler の実行ロール

実装時に上流設計の不整合を確認した。インフラ設計は watchdog Lambda を EventBridge Scheduler から 5 分ごとに呼ぶ一方、セキュリティ要件 NFR5.2b は iam:PassRole の渡し先を ec2.amazonaws.com / lambda.amazonaws.com だけに限定している。Scheduler には専用の実行ロールと scheduler.amazonaws.com への PassRole が必要で、このままでは作成できない。上流の IAM ロール計 6 つにも Scheduler のロールが含まれていない。

A. EventBridge Scheduler を維持し、watchdog 呼び出しだけの専用ロールを 1 つ追加する。追加の PassRole はそのロール ARN と scheduler.amazonaws.com の組み合わせだけを許可し、permissions boundary を必須にする（推奨: 既存の Scheduler 設計を維持できる）
B. Scheduler ではなく EventBridge の定期ルールから Lambda を呼ぶ。Lambda 側のリソースポリシーをルール ARN に限定し、Scheduler 用ロールと追加 PassRole を使わない
X. Other (please specify)

[Answer]: A. 専用ロールを追加 (Recommended)

根拠:
- ../../construction/nfr-requirements/security-requirements.md NFR5.2b
- ../../construction/infrastructure-design/infrastructure-specification.md の EventBridge Scheduler と AWS IAM
- https://docs.aws.amazon.com/lambda/latest/dg/with-eventbridge-scheduler.html
- https://docs.aws.amazon.com/scheduler/latest/UserGuide/security_iam_id-based-policy-examples.html
- https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html

## Consolidated Summary Confirmation

- 初回は新しいワールドで始める。以前のコードやワールドは移行しない。
- 承認済み設計を基に bootstrap / envs/prod / modules の Terraform とホスト側の処理を新規実装し、各モジュールの plan モード・モックテストと静的検査を用意する。
- 最初は最小構成でクライアント接続を確認する順序を守り、ローダー切り替え、バックアップ、監視を積み上げる。
- 東京、専用 VPC、既定 m7g.xlarge、暗号化した独立 EBS、S3 state とネイティブロック、OIDC の最小権限、S3 運用ロックを既決どおり実装する。
- EventBridge Scheduler を維持し、watchdog Lambda の呼び出しだけを許可した専用ロールを追加する。追加の PassRole はそのロール ARN と scheduler.amazonaws.com の組み合わせだけに限定し、permissions boundary を必須にする。IAM ロールは当初の 6 個から 7 個になる。
- allowed_account_ids を含む既存の非公開ローカル設定を保持し、AWS 識別子や秘匿値をコード・公開ログに出さない。
- AWS 不要のコード作成・検証を先に行う。実 AWS の確認・適用前に personal を再認証し、具体的な plan を確認できる状態にする。
- bootstrap の適用は手元で personal を使い、本番の適用は PR → master マージ → 本人の prod 承認を通す。GitHub の prod / ops と Secrets の設定手順も整える。

この内容で実装と構築準備を進めてよいですか？

- Looks correct
- Request changes

[Answer]: Looks correct

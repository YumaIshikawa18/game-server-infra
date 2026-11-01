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

## Q3. [プラットフォームエンジニア] S3 バケットに対する Checkov の残り 4 件

実装中の静的スキャンで、state バケットに 4 件の指摘が残った。どれも既決の構成（単一リージョン、SSE-S3、月 3,000 円の予算）と関係するため、扱いを決めたい。同じ方針をバックアップバケットにも適用する。

- CKV_AWS_144: 別リージョンへのレプリケーションがない（既決: 東京の単一リージョン）
- CKV_AWS_145: KMS による既定の暗号化ではない（既決: SSE-S3。運用ロックの IAM 条件も AES256 を前提にしている）
- CKV_AWS_18: サーバーアクセスログがない
- CKV2_AWS_62: イベント通知がない

A. 4 件とも、該当リソースだけに理由付きの抑止コメントを付ける。構成とコストは変えない（推奨: 既決の構成のままで、抑止の範囲と理由がコードに残る）
B. サーバーアクセスログ用のバケットを追加して CKV_AWS_18 は解消し、残り 3 件は理由付きで抑止する。ログの保存に少額の費用がかかり、ログバケット自身にも同じ指摘が出る
C. 暗号化を AWS 管理キー（`aws/s3`）の SSE-KMS に変えて CKV_AWS_145 も解消し、残りは A と同じく抑止する。運用ロックと CD 側の SSE 条件を合わせて変更する
X. Other (please specify)

[Answer]: B. アクセスログを追加し、残りは理由付きで抑止する。保存期間は 90 日。

確認した費用: ログ配信は無料で、保存料金のみ。推定は月約 1.5 MB、90 日で最大約 5 MB、月 0.02 円程度（10 倍ずれても 1 円未満。要確認）。

根拠（Q3）:
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/ServerLogs.html
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/enable-server-access-logging.html

## Q4. [プラットフォームエンジニア] 初回起動の Minecraft バージョン

要件 FR2.1 でバージョンは具体値で固定するが、値は未決定。walking skeleton はローダーなし（vanilla）で接続確認するため、最初に固定する版を決めたい。Java の版はバージョンに合わせて itzg イメージのタグで選び、digest で固定する。2026-11-01 時点の公開情報で確認した。

A. 26.3（2026-09-15 公開の最新リリース。Java 25 / itzg `2026.10.0-java25`）（推奨: 最新の安定版で、後から MOD に合わせて変更できる）
B. 1.21.11（2025-12-09 公開。Java 21 / itzg `2026.10.0-java21`。対応 MOD が多い旧系列）
X. Other (please specify)

[Answer]: A. 26.3（Java 25 / itzg `2026.10.0-java25`、digest 固定）

根拠（Q4）:
- https://piston-meta.mojang.com/mc/game/version_manifest_v2.json（各版の javaVersion）
- https://github.com/itzg/docker-minecraft-server/releases

## Q5. [プラットフォームエンジニア] ネットワークに対する Checkov の残り 2 件

envs/prod の実装中に、network モジュールで 2 件の指摘が残った（SG の関連付けの指摘はモジュール単体の検査による誤検知なので、理由付きで抑止する）。

- CKV2_AWS_11: VPC フローログ（どの IP からどのポートへ通信が来たか・拒否されたかの記録）がない。25565 を公開しているので、スキャンや不審な接続の調査に使える。S3 への配信は「vended logs」の料金（取り込み 1 GB あたり約 $0.25。東京の単価は要確認）と保存料金がかかる。稼働 40 時間 / 月なら数 MB 程度で、月 1 円未満の見込み。
- CKV2_AWS_12: VPC の既定セキュリティグループが通信を全面的に禁止していない。既定 SG はどのリソースにも使っていない。全面禁止にするには、既定 SG にタグを付けて変更できるよう、bootstrap の apply ロールの権限を少し広げて再適用する必要がある。

A. フローログを既存のログバケット（`flow/`、90 日）に送り、既定 SG は理由付きで抑止する（推奨: 調査に役立つ記録が実質 0 円で残り、IAM を広げずに済む）
B. フローログを送り、既定 SG も全面禁止にする（bootstrap の権限を広げて再適用する）
C. どちらも理由付きで抑止する（構成と費用は変えない）
X. Other (please specify)

[Answer]: A. フローログを既存のログバケット（`flow/`、90 日）に送り、既定 SG は理由付きで抑止する。

根拠（Q5）:
- https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-s3.html
- https://aws.amazon.com/vpc/faqs/

## Q6. [プラットフォームエンジニア] 月の予算の USD 換算

FR9.1 の予算は月 3,000 円相当で、AWS Budgets は USD で設定する。換算は本人が決める（infrastructure-specification.md の AWS Budgets）。80% と 100% で通知する。

A. 20 USD（1 USD = 150 円。設計の見積もりと同じ換算）（推奨: 設計の前提とそろう）
B. 19 USD（円安に備えて少し低めにし、早めに通知を受ける）
X. Other (please specify)

[Answer]: A. 20 USD（1 USD = 150 円）

## Q7. [プラットフォームエンジニア] 本人の非公開入力（メールアドレスと EULA への同意）

メールアドレスと Minecraft EULA への同意は本人だけが決められるため、本人が `envs/prod/private.auto.tfvars.json`（gitignore 済み）を作成する。値はこの記録にも書かない。

A. 作成した
X. Other (please specify)

[Answer]: A. 作成した（gitignore 済み・未追跡を確認。値は確認していない）

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

## 次に行うこと

- bootstrap の Checkov 指摘を整理・修正する。最新スキャンは passed 58 / failed 9。
- CKV_AWS_393 が CI の3ロールで失敗する。sub はリポジトリと環境を限定しているが、for_each とローカルマップの静的評価を調査中。まだ誤検知と確定していない。実際の trust policy と全ロールのテストを確認してから対処する。
- boundary の CKV_AWS_355 / CKV_AWS_290 を調査し、リソース制限が可能な操作は分離・限定する。例外が必要なら API の制約を根拠に示す。
- S3 の CKV_AWS_144 / CKV_AWS_145 / CKV_AWS_18 / CKV2_AWS_62 は、採用済みの単一リージョン・SSE-S3 構成との関係を整理する。理由付きのリソース限定例外にするか構成を追加するかは、まだ本人に質問・決定していない。勝手に抑止しない。
- tflint は bootstrap で指摘なし。コンテナ間で plugin が失われる問題を直し、job 内の専用キャッシュを共有するよう CI ヘルパーを修正した。
- 修正後に fmt / validate / モックテスト / 静的スキャンを実行し、bootstrap plan を再作成する。保存済み plan はその後のコード変更で古くなっているため、そのまま apply しない。
- bootstrap の具体的な plan を本人に提示してから適用する。本番適用は既決どおり PR → master → prod 承認。
- envs/prod と残りのモジュール、Minecraft ホスト処理、バックアップ、監視、GitHub 設定はまだ実装・構築が残っている。全体がデプロイ可能とは扱わない。

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

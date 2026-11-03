# Constraint Register

対象の意図: `aidlc/spaces/default/intents/261103-discord-multi-server/ideation/intent-capture/intent-statement.md`（intent-statement）

## 技術的な制約

| ID | 制約 | 影響 | 出典 |
|---|---|---|---|
| C-T1 | 起動・停止・復元の操作は、アカウント内の管理対象サーバーが 1 台であることを前提にしています | 2 台目を作ると、今のサーバーの操作が失敗します。対象を接頭辞で絞る変更が先に必要です | `scripts/cd/common.py` の `instance_id()` |
| C-T2 | サーバーに送るコマンドの定義（SSM ドキュメント）の名前は固定です | 同じアカウントに 2 つ作れず、名前の変更が必要です。変更は今のサーバーにも及びます | `modules/minecraft_server/ssm.tf`、`bootstrap/iam.tf` |
| C-T3 | 一部のカスタムメトリクスとアラームに、サーバーを区別する情報がありません | 片方の異常がもう片方の通知に混ざります | `modules/minecraft_server/files/bin/common.sh`、`modules/monitoring/main.tf` |
| C-T4 | AWS Budgets の予算は、対象を絞らずアカウント全体を見ています | 今の月 3,000 円のままでは、2 台の合計で超過の通知が出ます | `modules/monitoring/main.tf` |
| C-T5 | GitHub Actions から AWS へのアクセスは、環境 `prod` と `ops` に固定されています | 新しいサーバー用の GitHub Environment と IAM の設定が必要です | `bootstrap/iam.tf` |
| C-T6 | CI、CD、手元のスクリプトは `envs/prod` を前提にしています | 2 つ目の環境を検査もデプロイもできません | `scripts/ci/`、`scripts/cd/`、`scripts/local/` |
| C-T7 | bootstrap の state は手元のファイル 1 つです | 新しいサーバー用の bootstrap をどう持つかを、設計で決める必要があります | `bootstrap/`、team.md の Deployment |
| C-T8 | オペレーターの一覧の取り消しは、イメージの既定の動作では反映されない可能性があります | 取り消しを確実に反映する設定と確認が必要です | [公式ドキュメント](https://docker-minecraft-server.readthedocs.io/en/latest/configuration/server-properties/)（推測を含みます） |

## 組織・運用の制約

| ID | 制約 | 影響 | 出典 |
|---|---|---|---|
| C-O1 | 運用はご本人だけで行います | 手順は 1 人で実行できる形にします | Intent Capture の Q2 |
| C-O2 | 予算は月 3,000 円です | 2 台の合計（約 4,450〜5,000 円）は超えるため、見直しが必要です | `envs/prod/variables.tf`、Q2 |
| C-O3 | `master` への変更は PR で行います | 変更はすべて PR を経由します | project.md の Mandated |
| C-O4 | デプロイ先は `personal` の AWS アカウントです | 別のアカウントを使う方式は見送ります | project.md の Mandated |
| C-O5 | bootstrap は手元から適用します | IAM の変更には、ご本人の手元での作業が発生します | team.md の Deployment |
| C-O6 | 今のサーバーの停止は、誰も遊んでいない時間に行います | デプロイと再起動の時間を選ぶ必要があります | Q4 |
| C-O7 | 新しいサーバーの webhook は、向こうの主催者や管理者に作ってもらいます | 作ってもらえるまで、通知の確認を完了できません | Q3 |
| C-O8 | 期限はありません | 順序を優先して進められます | Intent Capture の Q9 |

## 規制・規約の制約

| ID | 制約 | 影響 | 出典 |
|---|---|---|---|
| C-R1 | リポジトリは public で、アカウント ID や IAM ロール名などの識別子は出しません | 新しいサーバーの値も Secrets と gitignore 済みのファイルに置きます | project.md の Forbidden |
| C-R2 | オペレーターのユーザー名は公開しません | ホワイトリストと同じ秘匿パラメータに置きます | Q5 |
| C-R3 | Minecraft の EULA と利用規約に従います | 実費の分担が規約に沿うかの確認が必要です（未確認） | Q6、`raid-log.md` の I1 |

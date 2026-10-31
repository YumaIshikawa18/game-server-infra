# CD Configuration

## 上流と作成物

`../../construction/ci-pipeline/ci-config.md` と `quality-gates.md` の 11 チェックをマージ条件に保ち、`../../construction/infrastructure-design/infrastructure-specification.md` と `cicd-pipeline.md` の prod / OIDC / SSM 構成を具体化した。

| ファイル | 内容 |
|---|---|
| `.github/workflows/deploy.yml` | master の push / 手動実行、事前 plan、prod 承認、再比較、apply、スモークテスト |
| `.github/workflows/start.yml` | master から本人だけが起動、SSM 待ち、Minecraft 応答待ち |
| `.github/workflows/stop.yml` | 保存・バックアップ・停止。SSM 不通時は直接停止して警告 |
| `.github/workflows/restore.yml` | 停止中だけ復元し、最後も停止状態にする |
| `scripts/cd/common.py` | 応答を公開しない AWS 呼び出し、S3 ロック、SSM、通知 |
| `scripts/cd/deploy.py` | 値を含めた plan 比較、置き換え保護、apply |
| `scripts/cd/operations.py` | 入力検証と起動・停止・復元の後始末 |
| `tests/cd/test_cd.py` | AWS 呼び出しを mock した正常・異常・境界条件テスト |

CI の identifier-check に CD テストも追加した。共通の mask にはロール ARN だけでなく抽出したロール名も登録する。Python のインデントは `.editorconfig` の 2 スペースに合わせた。

## GitHub 側の設定

GitHub 設定の管理は既決どおり本人が手動で行う。

| 設定 | 値・条件 |
|---|---|
| `prod` Environment | Required reviewers は本人。本人による承認を可能にするため Prevent self-review は無効。deployment branch は master のみ |
| `ops` Environment | master のみ、承認なし |
| `OPERATOR_LOGIN` Variable | 本人の GitHub ログイン名。start / stop / restore の job と Python の両方で一致を要求 |
| `AWS_REGION` Variable | 東京リージョン |
| `AWS_PLAN_ROLE_ARN` Secret | 承認前 plan のロール |
| `AWS_APPLY_ROLE_ARN` Secret | prod 承認後 apply のロール |
| `AWS_OPS_ROLE_ARN` Secret | 起動・停止・復元だけのロール |
| `TF_STATE_BUCKET` / `TF_STATE_KEY` Secrets | Terraform state の場所 |
| `TF_INPUTS_JSON` Secret | CI と同じ入力 JSON。実行時に TF_VAR_* に展開 |
| `MC_LOCK_BUCKET` / `MC_LOCK_KEY` Secrets | 共通ロック。既存 state バケット内の専用 control/ キーを使い、state キーと *.tflock から分離する |
| `MC_EVENTS_TOPIC_ARN` Secret | 通知専用 SNS トピック |

インスタンス ID の Secret は使わない。通常の運用は `mc:managed=true` かつ terminated / shutting-down 以外のインスタンスを検出し、対象が 1 台でなければ拒否する。これにより EC2 置き換え後も古い ID に操作しない。apply 後の確認だけは Terraform の sensitive output `instance_id` から新 ID を内部取得する。

workflow 既定は contents: read。AWS を使う job だけ id-token: write。checkout の資格情報は保持しない。action は CI と同じ検証済み release SHA。runner は ubuntu-24.04、Terraform は .tool-versions の版を使う。Python と AWS CLI は runner の搭載版を使うため、Python 3.10 以降と S3 の If-None-Match / DeleteObject If-Match に対応した AWS CLI v2 が前提。Environment Provisioning の有効化時に runner 上の互換性を確認する。

## 承認前後の一致

Q1 の A を採用。承認前と同じコミットで再 plan し、次をキー順・リソースアドレス順に正規化して SHA-256 を比較する。

- Terraform バージョン、resource_changes の変更前後・未確定値を含む全項目
- output_changes、resource_drift、variables、configuration、planned_values、relevant_attributes

生成時刻だけは比較しない。未知形式・未完了 plan は拒否する。変更対象や update という操作が同じでも、サイズなどの値が違えば拒否する。データソース等の変動でも拒否する場合があるが、その場合は新しい plan を作って再承認する。

転送する job output はハッシュだけ。部分文字列マスクとの偶然の一致を避けるため文字間を区切って渡し、apply 側で復元する。生の plan は job 間で保存・転送しない。公開サマリーは CI と同じ件数とアドレスのみ。

実処理開始前と apply 直前に、対象コミットが現在の master と一致することを再確認する。古い承認待ち run は、最新 master に追いつくために別のコードを勝手に checkout せず、失敗にして再実行を求める。

## 排他とタイムアウト

- GitHub concurrency は既決の minecraft-prod と minecraft-ops に分け、どちらも cancel-in-progress: false。
- Q2 の A により、apply と運用処理の開始時だけ共通 S3 ロックを取る。prod の承認待ちでは取らない。
- S3 PutObject の If-None-Match: * で取得し、ランダムな所有者 ID、run ID、attempt を暗号化保存する。同じ ETag のオブジェクトだけ If-Match で解放する。
- 競合時は 10 秒ごと、最大 5 分待つ。権限エラーは待たずに失敗する。時間だけで他の処理のロックを奪わない。
- apply の変更開始後や復元の停止確認失敗ではロックを保持する。runner の強制終了でも残り得るため、解除は rollback-runbook.md に従い本人が確認して行う。
- S3 ロックは GitHub の apply / start / stop / restore を直列化する。ホストの自動停止・毎時バックアップは既決の flock と状態タグを使い、同じ S3 ロックの対象ではない。手元での AWS 直接操作もこのロックを通らない。
- GitHub job の上限は plan 20 分、apply 45 分、start 40 分、stop 30 分、restore 45 分。OIDC セッションは 1 時間。SSM 待ち 3 分、Minecraft 確認 10 分。ロック待ち時間は起動時間の目標に追加でかかる。

## IAM の追加とリスク

Q3 の A を採用。追加は用途に絞り、bootstrap のテストで検証する。

| ロール | 追加・検証する内容 | 制限 |
|---|---|---|
| plan | 既存 PR の sub に加えて、同一リポジトリの ref:refs/heads/master の sub | aud は sts.amazonaws.com、StringEquals の候補だけ。apply 権限なし |
| apply | mc-stop / mc-health-check の SendCommand、GetCommandInvocation、DescribeInstanceInformation | 対象管理インスタンスと指定文書に限定。DescribeInstanceInformation 等、リソース制限非対応の参照操作だけ * の理由を記載 |
| apply / ops | ロックキーの PutObject / DeleteObject | 専用 control/ オブジェクト 1 つだけ。TLS / SSE-S3、条件付き書き込みと解放。ops には state キーや Terraform の *.tflock の権限を与えない |
| ops | 既決の EC2 起動停止・参照、mc:mode のタグ操作、指定 SSM 文書、通知先だけの Publish | mc:managed タグと文書・キーの制限を保つ |

apply は既決の app ロール範囲と permissions boundary を維持し、bootstrap の ci ロールを編集できない。共有バケットでも prefix / キー単位に分けるため、ops に state の読み取り権限を広げる必要はない。

## ホスト側との契約

Environment Provisioning で次の SSM ドキュメントとスクリプトを作る。現在は本体がないため実環境の動作は未検証。

- mc-health-check: server list ping が成功した場合だけ成功終了する。実行を短時間で完了させる。
- mc-stop: reason を受け取る。置き換え用には require_backup=true も受け取り、バックアップと照合に失敗したら成功を返さず、置き換えを許さない。SSM の実行結果を受信でき、EC2 停止も確認できる契約とする。
- mc-restore-apply: key を受け取る。許可するのは stop/ または hourly/ の .tar.zst。チェックサム確認、展開先の逸脱・シンボリックリンク等の検証、既存ワールド退避、失敗時の原状保持を実装する。restore モードでは Minecraft を起動しない。
- Terraform output instance_id は sensitive とする。EC2 には mc:managed=true を付ける。
- バックアップのオブジェクトキーには、公開される手動 workflow 入力に載せられる日付等を使い、AWS 識別子や秘匿値を含めない。

## 失敗時

apply 失敗は SNS に通知する。起動失敗は保存・停止を試み、SSM 不通なら直接停止してバックアップなしの警告を送る。復元は成功・失敗によらず停止し、停止確認後にタグを外す。停止や後始末が失敗したらロックを保持する。

SNS 自体の失敗は GitHub Actions を失敗にして明示する。AWS 認証前の失敗、plan 専用ロールの失敗、runner の強制終了では SNS 通知を保証できないため、GitHub Actions の失敗通知も有効にする。インフラとワールドは自動で巻き戻さず、runbook に従って復旧する。

## 検証と有効化

CI 15 件と CD 30 件を AWS 呼び出しなしで実行する。YAML / Bash / Python 構文、action SHA、prod / ops の対応、識別子検査も確認する。

この段階では AWS への変更、GitHub 設定変更、push / merge / workflow 実行は行わない。Environment Provisioning で本体と権限を実装し、初回 plan / apply / SSM / ロック競合・中断復旧を実環境で検証する。

## Sources

- `deployment-pipeline-questions.md` Q1〜Q3、Consolidated Summary Confirmation
- `../../construction/ci-pipeline/ci-config.md`、`quality-gates.md`
- `../../construction/infrastructure-design/infrastructure-specification.md`、`cicd-pipeline.md`
- `../../construction/nfr-design/reliability-design.md` §6〜§8
- https://developer.hashicorp.com/terraform/internals/json-format
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-deletes.html
- https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments

## Assumptions & Open Questions

None.

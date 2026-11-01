# Validation Report

上流: `../../construction/infrastructure-design/infrastructure-specification.md` と `../deployment-pipeline/cd-config.md`。構築した内容は `environment-inventory.md`。

## 1. 結果の要約

| 観点 | 結果 |
|---|---|
| 必須チェック 11 件（PR #3、最新コミット） | すべて成功（fmt、validate、tflint、checkov、terraform-test、pytest、shellcheck、bats、identifier-check、gitleaks、plan） |
| 実環境に対する plan | 手元（personal）と CI（ci-plan ロール）の両方で 追加 81 / 変更 0 / 削除 0。PR に投稿したサマリーを識別子チェックにかけ、検出なし |
| bootstrap の適用 | 4 回（初回の構築、フローログと権限の追加、OIDC の subject の修正）。どれも本人が承認・実行し、適用後の再 plan は差分 0 件。4 回目（apply ロールへの読み取りの追加、レビュー #10）も同様に適用し、差分 0 件 |
| 未検証 | `envs/prod` の apply、CI の apply ロールの権限が十分か、ホスト上での実際の動作、クライアントからの接続（Deployment Execution で確認する） |

## 2. テスト

| 対象 | 件数 | 内容 |
|---|---|---|
| `terraform test`（plan モード、モック provider） | bootstrap 8、modules 6 つで計 24、envs/prod 3 | 正常系と、各モジュール 2 件以上の拒否ケース（不正な入力、別リポジトリの subject、浮動するバージョン、EULA 未同意、digest なしのイメージなど） |
| bats（ホスト上のスクリプト） | 42 | 世代削除の境界（24/25、7/8）、ロック、`save-on` の復帰、無人 29/30 分・無応答 59/60 分・起動直後の猶予、sha256 不一致の MOD を置かない、復元の検査（キー、復元モード、照合、シンボリックリンク）、マウントの確認、停止の中止・中断時の後始末 |
| pytest（Lambda） | 29 | notifier（形式の判定、severity、識別子の拒否、再試行、429）、watchdog（59/60 分、14/15 分、11:59/12:00、`mc:stopping`） |
| CD（unittest） | 33 | plan の比較、置き換えの保護、ロック、復元・停止の待ち時間、通知の形式 |

テストの方針は team.md の Testing Posture（test-after、全モジュールに plan モードのテスト、必須チェックの全通過）に沿う。行カバレッジの基準は、team.md のとおりこの基準に置き換えている。

## 3. セキュリティの検証

### IAM の変更とリスク評価

| 変更 | 広がる範囲 | 評価 |
|---|---|---|
| CI ロールの trust を immutable subject に変更 | なし（狭まる） | owner と repo の ID で縛るので、リポジトリの作り直しやユーザー名の再取得では受け付けない。`aud`、プロバイダー、Action は不変 |
| plan ロールに読み取りを追加 | 読み取りのみ | バックアップバケットの設定、配布ファイルのタグ、SSM 文書の共有設定（3 文書に限定）、フローログ |
| apply ロールにフローログの作成・削除を追加 | `Project` タグ付きに限定 | 既存の EC2 権限と同じ絞り方 |
| apply ロールに読み取りのポリシー（`reads`）を追加（レビュー #10） | 読み取りのみ | plan ロールと同じ読み取り（AMI の SSM パラメータ、app ロールの設定、Lambda・SNS・Scheduler・予算の設定など）。承認後に作り直す plan で必要。書き込みは増えない |
| apply ロールに `logs:CreateLogDelivery` / `DeleteLogDelivery` | `Resource = "*"`（リソース単位の制限に非対応） | 唯一の広がり。ログ配信の登録だけで、データは読めない。配信先が許可しない限り送れない。リスクは低い |
| boundary の SSM エージェントの権限 | 狭まる | `ssm:UpdateInstanceInformation` をインスタンスの ARN に限定。`ssmmessages:*` は公式どおり `*` |
| app ロール 4 つ | boundary 必須 | ホストが止められるのは自分自身だけ（`ec2:InstanceProfile` 条件）。watchdog は管理タグ付きだけ。Scheduler は watchdog の呼び出しだけ |

IAM の 8 文書を AWS Access Analyzer で検証し、エラーは 0 件。警告 2 件は、運用ロックで `If-None-Match: *` を文字どおりの `*` として照合している箇所で、意図どおり。

### Checkov の抑止（34 件、すべてリソース単位で理由付き）

| チェック | 件数 | 理由 |
|---|---|---|
| CKV_AWS_144（別リージョンへの複製） | 3 | 単一リージョンの方針（Q3） |
| CKV_AWS_145（S3 の KMS） | 3 | SSE-S3 の方針。aws/s3 鍵はポリシーを編集できない（Q3） |
| CKV2_AWS_62（S3 のイベント通知） | 3 | 通知は SNS に集約（Q3） |
| CKV_AWS_18（ログバケット自身のアクセスログ） | 1 | ログのログが循環する |
| CKV_AWS_158 / CKV_AWS_338（ロググループの KMS・保存期間） | 3 / 3 | 秘匿値を含めない設計。プレイヤー名を含むため 14 日 |
| CKV_AWS_116 / 117 / 272 / 173 / 50（Lambda） | 各 2 | DLQ・VPC・コード署名・環境変数の KMS・トレーシングは、個人運用の小さな関数には不要 |
| CKV_AWS_26（SNS の暗号化） | 1 | 本人の判断で暗号化しない（infrastructure-specification.md） |
| CKV_AWS_189（EBS の CMK） | 1 | aws/ebs で暗号化。CMK は予算に見合わない（SNS と同じ判断） |
| CKV_AWS_297（Scheduler の KMS） | 1 | 入力は空の JSON だけ |
| CKV_AWS_126（EC2 の詳細モニタリング） | 1 | 死活は独自メトリクスで見る |
| CKV2_AWS_19 / CKV2_AWS_5（EIP・SG の関連付け） | 1 / 1 | ENI 経由の関連付けを検査が認識しない（誤検知） |
| CKV2_AWS_12（既定 SG） | 1 | どこにも使わない。IAM を広げない（Q5） |
| CKV_GHA_7（workflow_dispatch の入力） | 1 | 復元にはキーの入力が必須。形式は 2 か所で検査 |

誤検知と判明して、抑止せずにコードを直したもの: CKV_AWS_393（OIDC の subject。Checkov が map の添字参照を評価できない）、envs から各モジュールを再評価したときの IAM の指摘（ダミーの入力を与えて解消）。

### 公開リポジトリでの漏洩防止

- コミットした全ファイルを識別子チェックと gitleaks にかけ、検出なし（push の前に毎回実行）。
- plan の生の出力・plan ファイル・state はコミットも投稿もしない。手元の plan ファイルは、サマリーを出したあとに削除する。
- Secrets は gh の標準入力で登録し、値は画面にもコマンド履歴にも出していない。

## 4. レビューで見つかった問題と修正（Codex、PR #3、11 件）

| # | 優先度 | 問題 | 修正 |
|---|---|---|---|
| 1 | P1 | `if` の条件の中では `set -e` が効かず、圧縮の失敗でも不完全なバックアップを成功扱いにする | 各手順の失敗を明示的に判定。照合できないオブジェクトは削除 |
| 2 | P2 | 復元の待ち時間が SSM の上限より短い | 1920 秒にした。restore の job は 50 分 |
| 3 | P1 | 置き換えで RCON の保存に失敗してもバックアップを有効とみなす | 保存の失敗で置き換えを中止。通常の停止では古い世代を削除しない |
| 4 | P2 | ワークフローの通知に `source` がなく、error が warn になる | `source: workflow` を追加 |
| 5 | P1 | EBS のマウントが失敗すると、ルートディスク上でワールドを作り、それをバックアップする | `RequiresMountsFor` とバックアップ・復元時のマウントの確認 |
| 6 | P2 | 停止の待ち時間がホスト側の処理より短い（置き換え前の停止にも同じ問題があった） | ホスト側の上限と停止予約を超えるまで待つ。stop は 35 分、start は 50 分 |
| 7 | P2 | 停止を中止すると `mc:stopping` タグが残り、watchdog が止まる | EXIT trap で必ず外す。TERM / INT でも通る |
| 8 | P1 | 中断されると自動保存が止まったまま動き続ける | 後始末で `save-on` に戻す |
| 9 | P2 | 5 GB を超えるとバックアップできない | `aws s3 cp`（マルチパート）と CRC64NVME、SHA-256 をメタデータで照合 |

| 10 | P1 | 承認後に apply ロールで作り直す plan に必要な読み取り権限がなく、apply の前に失敗する | apply ロールに plan ロールと同じ読み取りのポリシーを追加。ポリシーの付け忘れを防ぐため、付与はポリシーの一覧から作る |
| 11 | P2 | #8 の修正で、ロックを取れずに終わった停止が、毎時バックアップの save-off を解除してしまう | save-off をこの停止処理が送ったときだけ save-on に戻す |

あわせて直したもの: OIDC の subject の形式の不一致（CI の plan が失敗して判明）、Lambda の zip がファイルの権限で変わり、承認前後の plan の比較が毎回失敗する問題（`output_file_mode = "0644"`）、毎時バックアップで `save-off` 自体の失敗を通知しない問題。

## 5. 設計との差分

| 設計 | 実装 | 理由 |
|---|---|---|
| 復元モードは `restore.target` | 各ユニットの `ConditionPathExists=!/run/minecraft/restore` | 同じ効果で、ユニットの切り替えが不要 |
| RCON パスワードは SSM SecureString | ホストで初回に生成し、ワールド EBS に 0600 で保存 | コンテナ内の localhost でだけ使う値で、人が扱う必要がない |
| MOD 一覧は `config/mods.yaml` | `config/mods.json`（Terraform の変数から生成） | ホストで jq を使い確実に検査するため |
| ロググループ名は `/minecraft/prod/...` | `/<prefix>/server`、`/<prefix>/scripts` など | boundary の対象（`log-group:/<prefix>/*`）に合わせる |
| バックアップの照合は S3 の SHA-256 | CRC64NVME（転送）と、メタデータの SHA-256（全体） | 5 GB を超えるマルチパートに対応するため（レビュー #9） |
| 停止・起動・復元の job の上限（30 / 40 / 45 分） | 35 / 50 / 50 分 | ホスト側の上限に待ち時間を合わせたため（レビュー #2・#6） |

## 6. ロールバック

| 対象 | 手順 |
|---|---|
| bootstrap の変更 | 該当のコミットを revert し、手元で `python3 -m scripts.local.terraform plan` → 本人が `apply`。バケットは `prevent_destroy` で誤削除を防ぐ |
| prod（Deployment Execution 以降） | `../deployment-pipeline/rollback-runbook.md` に従い、revert の PR → 必須チェック → マージ → prod 承認 → apply |
| GitHub の設定 | Secrets と Variables は `scripts/local/github_setup.py` で再登録できる。Environments は本人が画面で戻す |

## 7. Deployment Execution に引き継ぐこと

- Branch protection に必須チェック 11 件を登録する（本人）。
- whitelist を SSM に登録してから、PR #3 をマージし、`prod` を承認する（本人）。
- apply で CI の apply ロールの権限が足りるかを確認する。不足があれば、bootstrap の追加 plan を本人に示してから適用する。
- 起動の確認: mc-health-check、メールの購読確認（2 通）、クライアントからの接続（walking skeleton の完了条件）。
- 初回の停止で、バックアップ（CRC64NVME とメタデータの SHA-256）と停止の流れを確認する。

## Sources

- `../../construction/infrastructure-design/infrastructure-specification.md`
- `../deployment-pipeline/cd-config.md`、`../deployment-pipeline/rollback-runbook.md`
- `environment-provisioning-questions.md` Q1〜Q8
- PR #3 の CI の結果と Codex のレビュー（11 件）
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/upload-objects.html
- https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html
- https://www.freedesktop.org/software/systemd/man/latest/systemd.mount.html
- https://docs.github.com/en/actions/reference/security/oidc

## Assumptions & Open Questions

- [assumption] CI の apply ロールの権限は、plan に含まれるリソースの作成に十分である。plan ロールでの plan は成功したが、作成時の権限は Deployment Execution の初回 apply まで確認できない。
- [assumption] AL2023 のホストで、itzg イメージに含まれる `mc-monitor` と `rcon-cli` が、スクリプトの想定どおりに動く（要確認。初回の起動で確認する）。

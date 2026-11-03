# Infrastructure Specification

入力: `aidlc/spaces/default/intents/261103-discord-multi-server/inception/requirements-analysis/requirements.md`、`aidlc/spaces/default/codekb/game-server-infra/architecture.md`

Functional Design、NFR Design、Domain Design はこのプランの対象外です。構成は要件と既存コードの調査から導きます。

## 設計の要点

新しい AWS リソースは作りません。秘匿パラメータを 1 つ（ご本人が手元で登録）と、ホストの起動処理および配布設定の変更で実現します。

要件の OQ1、OQ2 は、イメージの動作を確認した結果、次のとおり解決しました。

## イメージの動作の確認結果

確認対象は、`docker/compose.yml` で固定している digest のイメージです。`mc-image-helper manage-users` を使い捨てのコンテナで実行し、起動スクリプト `start-setupRbac` はタグ `2026.10.0` のソースを読みました。実際のサーバー起動は未確認で、Deployment Execution で確認します。

| 条件 | 結果 | 確認方法 |
|---|---|---|
| `OPS` が未設定 | 同期が走らず、`ops.json` は残る | ソース（`[[ -v OPS ]]` の分岐） |
| `OPS` が空で設定済み、`SYNCHRONIZE` | `ops.json` は `[]` になる | 空の引数での実行。環境変数の扱いはソース |
| 新規の項目 | レベル 4 になる。`OP_PERMISSION_LEVEL` は使われない | 実行、ソース |
| 既存の項目（名前が一致、レベル 3） | レベル 3 を保持し、UUID が補われる | 実行 |
| 再度の同期 | レベル 3 を保持する | 実行 |
| 解決できない名前 | 終了コード 2 で失敗する（起動スクリプトは `set -e` のため中止） | 実行、ソース |

## 検討した方式（FR1.3、FR2.2）

| 方式 | 内容 | 評価 |
|---|---|---|
| A. 起動前に `ops.json` を種として書き、`OPS` で同期する | ホストが名前とレベル 3 だけの項目を書き、UUID の解決はイメージに任せる | **採用**。レベル 3 と 0 人を初回の起動から満たし、外部への問い合わせはイメージのホワイトリスト処理と同じ経路に保てます |
| B. `OPS` だけを使う | イメージの標準の動作に任せる | 不採用。新規の項目がレベル 4 になり、FR1.3 を満たせません |
| C. ホストが UUID も解決して `ops.json` を完成させる | `OPS` を使わない | 不採用。ホストから外部 API への依存が新たに増えます |
| D. 起動後に RCON で `/op` を実行する | `op-permission-level` の値で付与する | 不採用。起動処理の後段に依存し、失敗時の扱いが増えます |

方式 A の影響として、種の形式（`uuid` が空で名前が一致する項目を受け付ける動作）は、イメージの内部の動作に依存します。公式ドキュメントに記載があるのは既存の項目のレベルを保持することだけです。イメージを更新するときは、レベルの確認が必要です（`cicd-pipeline.md`）。CI では検知しません。digest の更新は手動で、影響は一覧にあるご本人に限られるため、手動の確認とすることをご本人が判断しました。

## Deployment

| Facet | Choice | Rationale |
|---|---|---|
| Compute model | 変更なし（EC2 上の 1 コンテナ） | FR、NFR ともに構成の変更を求めていません |
| Networking | 変更なし。名前の解決はコンテナから既存の経路で行う | NFR6 |
| Storage | `ops.json` はワールド EBS の `/srv/minecraft/data` に置く | コンテナの `/data` と同じ場所です |
| Environments | `prod` のみ | team.md の Deployment |
| IaC approach | `minecraft_server` モジュールの配布設定と、配布するスクリプトを変更する | 既存の方式です |
| Resource sizing | 変更なし | NFR6 |

## Infrastructure Services

| Service | Role | Configuration | Notes |
|---|---|---|---|
| SSM Parameter Store | オペレーターの一覧の置き場所 | `<param_prefix>/ops`、SecureString。Terraform では作らず、ご本人が手元で登録する。未登録は 0 人 | ホワイトリストと同じ扱いです（D-05）。値は state に入りません（NFR1） |
| IAM（ホスト用ロール） | パラメータの読み取りと復号 | 変更なし | `iam.tf` の `Secrets` と `DecryptSecrets` は `<param_prefix>/*` を対象にしているため、新しいパラメータも読めます（A-5 を確認済み） |
| S3（配布） | 変更したファイルの配布 | `deploy/bin/prepare-env.sh` と `deploy/minecraft.env` が更新される | 新しいリソースはありません（NFR6） |
| Minecraft コンテナ | `ops.json` の同期 | `EXISTING_OPS_FILE=SYNCHRONIZE`、`OP_PERMISSION_LEVEL=3` を `minecraft.env` に追加 | `OP_PERMISSION_LEVEL` はゲーム内の `/op` のレベルにだけ効きます |

## 起動処理の変更（`prepare-env.sh`）

処理の順序を次のとおりとします。手順 1〜6 のいずれかで失敗すると、`secrets.env` と `ops.json` を更新せずに起動を中止します。手順 7 の 2 回の `mv` の間で失敗すると片方だけが新しくなりますが、コンテナは起動せず、次の起動で両方が書き直されます。

| 順序 | 処理 | 失敗時 | 要件 |
|---|---|---|---|
| 1 | ホワイトリストを読み、検査する（既存） | `start_failed` | 既存 |
| 2 | `<param_prefix>/ops` を読む。`ParameterNotFound` だけを未登録（0 人）として扱う | 他のエラーは `start_failed` | FR1.1、FR3.1、FR3.2 |
| 3 | 空白を除き、形式を検査する | `start_failed` | FR1.2、FR3.3 |
| 4 | 各名前がホワイトリストにあることを、大文字と小文字を区別せずに検査する | 不一致が原因と分かる文面で `start_failed` | FR3.4、FR3.5 |
| 5 | `ops.json` の種（名前、空の UUID、レベル 3。0 人なら `[]`）を一時ファイルに書く。コンテナのユーザー（UID 1000）が読み書きできるようにする | `start_failed` | FR1.3、FR2.1、FR2.2、FR4.2 |
| 6 | `secrets.env` の内容を一時ファイルに書く。`OPS=<一覧>` を含め、0 人でも `OPS=` を必ず書く | `start_failed` | FR2.2、NFR2 |
| 7 | 手順 5 と 6 の一時ファイルを `mv` で置き換える | `start_failed` | NFR2 |
| 8 | ログに `players=` と `ops=` の人数を書く | なし | NFR1、NFR5 |

- 手順 7 で毎回置き換えるため、`/op` で付けた権限と、古いバックアップから戻った内容は次の起動で消えます。
- 手順 2 の `aws` のエラー出力には識別子が含まれる可能性があるため、ログと通知に出しません。
- 復元モードでは `prepare-env.sh` が走りません。復元後の通常の起動で手順 5 が走ります。

## 変更するファイル

| ファイル | 変更 | 要件 |
|---|---|---|
| `modules/minecraft_server/files/bin/prepare-env.sh` | 上の手順 | FR1〜FR4 |
| `modules/minecraft_server/deploy.tf` | `EXISTING_OPS_FILE`、`OP_PERMISSION_LEVEL` の追加 | FR1.3、FR2.1 |
| `envs/prod/outputs.tf` | `ops_parameter` の出力の追加 | FR5.1 |
| `docker/compose.yml` | コメントの更新のみ | なし |
| `tests/host/helpers.bash`、`tests/host/prepare_env.bats`（新規） | スタブとテスト | FR6.1、FR6.2 |
| `modules/minecraft_server/tests/minecraft_server.tftest.hcl` | 設定値と非混入の検査 | FR6.3 |
| `README.md` | 登録、変更、取り消し、確認、順序、ロールバック | FR5 |

## セキュリティへの影響

| 変更 | 影響 | 対応 |
|---|---|---|
| ゲーム内の権限の付与 | whitelist の内側の権限が広がります。IAM、ネットワーク、暗号化の設定は変更しません | レベル 3 に限定し（`/stop` は不可）、一覧をホワイトリスト内に限定します（FR3.4） |
| `ops.json` のバックアップ | 名前がバックアップに含まれます。`whitelist.json` と同じ扱いの非公開バケットです | 新しいリスクは増えません |
| サーバーログ | コンテナのログに名前が出る可能性があります（要確認）。プレイヤー名はすでに含まれ、保存は 14 日です | 既存の方針の範囲です |

## Shared Infrastructure

このプランに Unit はなく、共有リソースはありません。

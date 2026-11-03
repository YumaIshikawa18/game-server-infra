# game-server-infra

AWS 上で Minecraft サーバーを動かすための Terraform 一式です。インフラの変更は GitHub Actions を通して適用し、サーバーの起動・停止・復元も workflow から行います。

## 構成

![EC2 上の Minecraft サーバーと、デプロイ・バックアップ・通知・監視の流れ](docs/images/architecture.drawio.png)

画像には draw.io の図のデータが埋め込まれています。図を直すときは、PNG を draw.io で開いて編集し、同じファイルへ書き出してください。

## ディレクトリ

| パス | 役割 |
|---|---|
| `bootstrap/` | state バケット、ログバケット、CI 用の IAM ロールと OIDC。手元から適用します |
| `envs/prod/` | 本番環境のルートモジュール。Minecraft のバージョンや MOD は `minecraft.json` で設定します |
| `docs/client-setup.md` | 一緒に遊ぶ人向けのクライアントの準備手順。`minecraft.json` から生成します |
| `modules/` | `network`、`minecraft_server`、`world_backup`、`notifier`、`watchdog`、`monitoring` |
| `lambda/` | 通知（`notifier`）と強制停止（`watchdog`）の Lambda |
| `docker/` | Minecraft サーバーのコンテナ定義 |
| `scripts/` | CI（`ci/`）、デプロイと運用（`cd/`）、手元の準備（`local/`）のスクリプト |
| `tests/` | Python と bats のテスト、Checkov の入力 |
| `aidlc/` | 要件、設計、運用手順などの記録 |

## デプロイの流れ

1. 作業ブランチから `master` へ Pull Request を作ります。`master` へ直接 push はしません。
2. CI の必須チェック 11 件が通ることを確認します。plan の結果は、件数とリソースのアドレスだけを PR に投稿します。
3. squash merge すると Deploy が始まり、plan の後で `prod` の承認待ちになります。
4. 承認すると、plan が承認時と一致することを確かめてから apply し、Minecraft のヘルスチェックまで行います。

`master` への push のたびに Deploy が動きます。ドキュメントだけの変更でも同じです。

## 運用

いずれも GitHub Actions の画面から `master` で実行します。

| Workflow | 内容 |
|---|---|
| Start | サーバーを起動してヘルスチェックします |
| Stop | ワールドを保存してバックアップを取り、停止します |
| Restore | 停止中に、指定したバックアップ（`.tar.zst`）からワールドを復元します。完了後も停止したままです |

- プレイヤーが 0 人の状態が 30 分続くと、サーバーは自動で停止します。
- サーバーが無応答のときや、起動から 12 時間を超えたときも自動で停止します。
- 変更の戻し方、残った運用ロックの扱い、緊急停止は [Rollback Runbook](aidlc/spaces/default/intents/261031-minecraft-aws-server/operation/deployment-pipeline/rollback-runbook.md) にまとめています。

## Minecraft のバージョンや MOD を変える

1. `envs/prod/minecraft.json` を編集します。Forge などへ切り替えるときは `loader` と `loader_version` も指定します。MOD の項目は `name`、`version`、`url`、`sha256`、`side`（`server`、`client`、`both`）です。
2. `python3 scripts/ci/client_guide.py` で手順書を更新します。更新を忘れると CI が失敗します。
3. PR をマージして Deploy を承認し、次の起動から反映します。必要に応じて、一緒に遊ぶ人に [クライアントの準備](docs/client-setup.md) を案内します。

## オペレーター権限

SSM Parameter Store の SecureString に登録した名前に、ゲーム内のオペレーター権限（レベル 3）を付与します。レベル 3 では `/gamemode` と `/kick` を使えますが、`/stop` は使えません。一覧の値は起動のたびに読むため、変更に PR とデプロイは不要で、次の起動から反映されます。動作中のサーバーの権限は、次の起動まで変わりません。

パラメータ名は `envs/prod` の出力 `ops_parameter` で確認します。値は、Minecraft の名前をカンマで区切った形式で、すべてホワイトリストにある名前にします。名前やパラメータ名は、PR やログに貼らないでください。

### 登録と変更

```bash
aws ssm put-parameter --profile personal --region ap-northeast-1 --type SecureString --overwrite \
  --name "<ops_parameter の値>" --value "<プレイヤー名>,<プレイヤー名>"
```

### 取り消し

一覧から名前を外して上の手順で更新するか、全員を取り消すときはパラメータを削除します。削除すると、次の起動でオペレーターは 0 人になります。

```bash
aws ssm delete-parameter --profile personal --region ap-northeast-1 --name "<ops_parameter の値>"
```

ゲーム内の `/op` で付けた権限も、次の起動で消えます。

### 反映の確認

Stop と Start の workflow で起動し直してから、次を確認します。

1. CloudWatch Logs のロググループ `/<prefix>/scripts` で、最新の `event=env_prepared` の `ops=` が期待する人数であること。
2. 起動直後、`/op` を使う前に、Session Manager でホストに接続し、`sudo jq . /srv/minecraft/data/ops.json` の内容が一覧と同じで、`level` が 3 であること。
3. ゲーム内で、一覧にある人は `/gamemode` と `/kick` を実行でき、`/stop` は拒否されること。取り消した人は `/gamemode` が拒否されること。

### 起動が失敗するとき

一覧を読めない、形式が正しくない、ホワイトリストにない名前がある場合は、`start_failed` が通知され、起動を中止します。通知の文面に名前は含まれません。一覧を直すか、パラメータを削除して、もう一度 Start します。

オペレーターの名前をホワイトリストから外すときは、先にオペレーターの一覧から外します。順序が逆だと、次の起動が失敗します。

### ロールバック

この仕組みを外すときは、順序を守ります。先に外すと `OPS` が未設定になり、`ops.json` がそのまま残って権限も残ります。

1. パラメータを削除し、Stop と Start を行います。
2. `ops=0` で、`ops.json` が `[]` であることを確認します。
3. revert の PR をマージし、Deploy を承認します。

配布したスクリプトの問題で起動できず、先に revert したときは `ops.json` が残ります。次の手順で空にします。

1. revert を適用して Start します。
2. Session Manager でホストに接続し、コンテナを止めて `ops.json` を `[]` にします。

   ```bash
   sudo systemctl stop minecraft.service
   echo '[]' | sudo tee /srv/minecraft/data/ops.json
   ```

3. Stop と Start を行い、`ops.json` が `[]` のままであることを確認します。

### イメージの digest を更新するとき

`ops.json` の種の形式はイメージの内部の動作に依存し、CI では検知できません。`docker/compose.yml` の digest を更新したら、次の起動で `ops.json` の `level` が 3 のままであることを確認します。

## 自分の AWS アカウントに作る

### 前提

- AWS CLI、GitHub CLI（`gh`）、Docker、Python 3
- `personal` という名前の AWS プロファイル（スクリプトで固定しています）
- デプロイ先は東京リージョン（`ap-northeast-1`）です
- [Minecraft EULA](https://www.minecraft.net/eula) への同意

### 手順

1. `bootstrap/local.auto.tfvars` と `envs/prod/local.auto.tfvars` に、デプロイ先のアカウントを書きます。

   ```hcl
   allowed_account_ids = ["<your-account-id>"]
   ```

2. bootstrap の入力を生成し、plan を確認してから適用します。

   ```bash
   python3 -m scripts.local.prepare
   python3 -m scripts.local.terraform plan
   python3 -m scripts.local.terraform apply
   ```

3. `envs/prod/private.auto.tfvars.json` を作ります。

   ```json
   {
     "notification_email": "<your-email>",
     "accept_minecraft_eula": true,
     "monthly_budget_usd": 20
   }
   ```

4. もう一度入力を生成し、GitHub の Secrets と Variables を登録します。

   ```bash
   python3 -m scripts.local.prepare
   python3 -m scripts.local.github_setup
   ```

5. GitHub のリポジトリ設定を行います。
   - Environment `prod`: 承認者を設定し、デプロイ元を保護ブランチに限定します
   - Environment `ops`: デプロイ元を保護ブランチに限定します
   - `master` の Branch protection: 必須チェック `fmt`、`validate`、`tflint`、`checkov`、`terraform-test`、`pytest`、`shellcheck`、`bats`、`identifier-check`、`gitleaks`、`plan` を登録します
6. SSM Parameter Store に SecureString を 2 つ登録します。
   - `/<prefix>/minecraft/whitelist`: プレイヤー名（カンマ区切り）
   - `/<prefix>/minecraft/discord-webhook`: Discord の Webhook URL

   オペレーターの一覧（`/<prefix>/minecraft/ops`）は任意です。未登録ならオペレーターは 0 人です。登録の手順は [オペレーター権限](#オペレーター権限) にあります。
7. `master` へマージして Deploy を承認します。apply の後に届く SNS の確認メールを承認し、Minecraft クライアントから接続します。接続先のアドレスは、`envs/prod` の出力 `server_address` で確認できます。

`<prefix>` は `bootstrap/generated.auto.tfvars.json` の `prefix` の値です。これらの生成ファイルは gitignore 済みです。

## 開発

Terraform のチェックは Docker のコンテナで実行するため、手元に Terraform は不要です。

```bash
python3 scripts/ci/check.py <check>
```

`<check>` には必須チェックの名前（`plan` を除く）を指定します。`plan` は CI で実行します。ツールのバージョンは `.tool-versions` で固定しています。

## 公開リポジトリでの注意

AWS アカウント ID、IAM ロール名や ARN、バケット名、サーバーのアドレス、plan の全文は、コード、ログ、PR コメントのいずれにも出しません。値は GitHub Secrets か、gitignore 済みのローカルファイルに置きます。

## ライセンス

[MIT License](LICENSE)

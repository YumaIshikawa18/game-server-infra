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

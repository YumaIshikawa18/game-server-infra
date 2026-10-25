# prod の設定。CI/CD がこのファイルを読む。指定できる値は terraform.tfvars.example を参照。
#
# このリポジトリは public なので、ここには「公開されても困らない値」だけを書く。
#   - プレイヤー名などの個人情報・秘密情報 → SSM パラメータストア（SecureString）に手動で設定する
#       /mc/ops, /mc/whitelist（Terraform は dummy の値で作るだけ。README の「設定値と秘密情報の置き場所」参照）
#   - ワークフローが使う秘密情報（Discord webhook など） → GitHub Secrets
#   - AWS アカウント ID と、それを含む値（state バケット、ロール ARN） → GitHub Secrets
#       ローカルで allowed_account_ids を使う場合は local.auto.tfvars（.gitignore 済み）に書く

# EULA（https://aka.ms/MinecraftEULA）を読み、同意する場合のみ true にする。
# false のままだとサーバーは起動しない（インスタンスは自動停止タイマーで停止する）。
accept_eula = false

minecraft_version = "26.3"
instance_type     = "t4g.small"
jvm_memory_mb     = 1300

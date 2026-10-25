# prod の設定。秘密情報は含めないこと（CI/CD がこのファイルを読む）。
# 指定できる値は terraform.tfvars.example を参照。

# EULA（https://aka.ms/MinecraftEULA）を読み、同意する場合のみ true にする。
# false のままだとサーバーは起動しない（インスタンスは自動停止タイマーで停止する）。
accept_eula = false

minecraft_version = "26.3"
instance_type     = "t4g.small"
jvm_memory_mb     = 1300

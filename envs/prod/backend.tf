# bucket はアカウントごとに異なるため partial configuration とし、init 時に渡す。
#   terraform init -backend-config="bucket=<bootstrap の state_bucket_name>"
# ロックは S3 ネイティブロック（.tflock オブジェクト）を使い、DynamoDB は使わない。
terraform {
  backend "s3" {
    key          = "minecraft/prod/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

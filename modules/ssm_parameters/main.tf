# 値は秘密情報ではないため insecure_value を使い、plan で差分が見えるようにする
resource "aws_ssm_parameter" "ram" {
  name           = "${var.parameter_prefix}/ram"
  description    = "Minecraft JVM heap size in MB (-Xms/-Xmx)"
  type           = "String"
  tier           = "Standard"
  insecure_value = tostring(var.jvm_memory_mb)
}

resource "aws_ssm_parameter" "shutdown_timer" {
  name           = "${var.parameter_prefix}/shutdowntimer"
  description    = "Seconds to wait with no players before stopping the instance"
  type           = "String"
  tier           = "Standard"
  insecure_value = tostring(var.shutdown_timer_seconds)
}

################################################################################
# 個人情報・秘密情報（SecureString）
# Terraform はパラメータの「入れ物」だけを dummy の値で作り、本当の値は手動で設定する。
# value_wo（write-only）を使うので値は state に保存されず、value_wo_version を変えない限り
# apply しても手動で入れた値は上書きされない。
################################################################################

locals {
  secure_parameters = {
    ops       = "Comma-separated player names to op (set manually, 'dummy' = none)"
    whitelist = "Comma-separated player names to whitelist (set manually, 'dummy' = disabled)"
  }
}

resource "aws_ssm_parameter" "secure" {
  for_each = local.secure_parameters

  name             = "${var.parameter_prefix}/${each.key}"
  description      = each.value
  type             = "SecureString"
  tier             = "Standard"
  value_wo         = var.secure_parameter_dummy_value
  value_wo_version = 1
}

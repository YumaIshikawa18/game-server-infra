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

output "ram_parameter_name" {
  description = "JVM ヒープサイズのパラメータ名"
  value       = aws_ssm_parameter.ram.name
}

output "shutdown_timer_parameter_name" {
  description = "自動停止までの秒数のパラメータ名"
  value       = aws_ssm_parameter.shutdown_timer.name
}

output "ops_parameter_name" {
  description = "op を付けるプレイヤー名（SecureString、値は手動で設定）のパラメータ名"
  value       = aws_ssm_parameter.secure["ops"].name
}

output "whitelist_parameter_name" {
  description = "ホワイトリストに入れるプレイヤー名（SecureString、値は手動で設定）のパラメータ名"
  value       = aws_ssm_parameter.secure["whitelist"].name
}

output "secure_parameter_dummy_value" {
  description = "SecureString パラメータの初期値（サーバー側で未設定として扱う値）"
  value       = var.secure_parameter_dummy_value
}

output "parameter_arns" {
  description = "インスタンスが読み取るパラメータの ARN"
  value = concat(
    [aws_ssm_parameter.ram.arn, aws_ssm_parameter.shutdown_timer.arn],
    [for p in aws_ssm_parameter.secure : p.arn],
  )
}

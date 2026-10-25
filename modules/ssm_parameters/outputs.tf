output "ram_parameter_name" {
  description = "JVM ヒープサイズのパラメータ名"
  value       = aws_ssm_parameter.ram.name
}

output "shutdown_timer_parameter_name" {
  description = "自動停止までの秒数のパラメータ名"
  value       = aws_ssm_parameter.shutdown_timer.name
}

output "parameter_arns" {
  description = "作成したパラメータの ARN"
  value       = [aws_ssm_parameter.ram.arn, aws_ssm_parameter.shutdown_timer.arn]
}

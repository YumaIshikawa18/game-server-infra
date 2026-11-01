output "events_topic_arn" {
  description = "スクリプト・watchdog・ワークフローが送る events トピック。"
  value       = aws_sns_topic.this["events"].arn
  sensitive   = true
}

output "alerts_topic_arn" {
  description = "CloudWatch アラームと Budgets が送る alerts トピック。"
  value       = aws_sns_topic.this["alerts"].arn
  sensitive   = true
}

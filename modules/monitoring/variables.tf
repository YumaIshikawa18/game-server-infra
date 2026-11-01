variable "prefix" {
  description = "非公開設定から渡すリソース名の接頭辞。"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,23}$", var.prefix))
    error_message = "prefix は小文字で始まる 3〜24 文字の英小文字・数字・ハイフンにしてください。"
  }
}

variable "alerts_topic_arn" {
  description = "アラームと予算の通知先（alerts トピック）。"
  type        = string
  sensitive   = true
}

variable "monthly_budget_usd" {
  description = "月の予算（USD）。月 3,000 円相当を本人が換算して渡す（FR9.1）。"
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0 && var.monthly_budget_usd <= 100
    error_message = "月の予算は 0 より大きく 100 USD 以下にしてください。"
  }
}

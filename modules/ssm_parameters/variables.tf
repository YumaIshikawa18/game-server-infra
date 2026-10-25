variable "parameter_prefix" {
  description = "パラメータ名の接頭辞（ブログ / aws-samples と同じ /mc を既定とする）"
  type        = string
  default     = "/mc"

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", var.parameter_prefix))
    error_message = "parameter_prefix は /mc のように / で始まり末尾に / を付けない形式で指定してください。"
  }
}

variable "jvm_memory_mb" {
  description = "JVM ヒープサイズ（MB）"
  type        = number
}

variable "shutdown_timer_seconds" {
  description = "無人状態がこの秒数続いたら EC2 を停止する"
  type        = number
}

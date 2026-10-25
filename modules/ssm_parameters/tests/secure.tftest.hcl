# 個人情報を入れるパラメータが SecureString かつ write-only（value_wo）で作られることを確認する。
# state に値が残らないこと自体は provider の実装（value_wo 使用時は value を null にする）に依存し、
# mock provider では computed 属性にランダム値が入るため、ここでは検証しない。
mock_provider "aws" {}

variables {
  jvm_memory_mb          = 1300
  shutdown_timer_seconds = 900
}

run "secure_parameters_are_write_only" {
  # mock provider 上の apply なので AWS には接続しない
  command = apply

  assert {
    condition     = alltrue([for p in aws_ssm_parameter.secure : p.type == "SecureString" && p.value_wo_version == 1])
    error_message = "個人情報を入れるパラメータは SecureString で、value_wo（write-only）で作られるはずです。"
  }

  assert {
    condition     = output.ops_parameter_name == "/mc/ops" && output.whitelist_parameter_name == "/mc/whitelist"
    error_message = "パラメータ名は /mc/ops と /mc/whitelist のはずです。"
  }

  assert {
    condition     = length(output.parameter_arns) == 4
    error_message = "インスタンスが読むパラメータは 4 つのはずです。"
  }
}

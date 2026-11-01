# CD のワークフローが SSM Run Command で呼ぶ文書（cd-config.md「ホスト側との契約」）。
# 引数は allowedPattern / allowedValues で検査してからシェルに渡す。
locals {
  documents = {
    "mc-stop" = {
      timeout = 900
      parameters = {
        reason         = { type = "String", description = "Stop reason.", allowedPattern = "^(manual|idle|unresponsive|replace|start-failed)$" }
        require_backup = { type = "String", description = "Refuse to stop unless the backup succeeds.", allowedValues = ["true", "false"], default = "false" }
      }
      command = "/opt/minecraft/bin/stop.sh '{{ reason }}' '{{ require_backup }}'"
    }
    "mc-health-check" = {
      timeout    = 60
      parameters = {}
      command    = "/opt/minecraft/bin/health-check.sh"
    }
    "mc-restore-apply" = {
      timeout = 1800
      parameters = {
        key = { type = "String", description = "Backup object key.", allowedPattern = "^(stop|hourly)/[0-9]{8}-[0-9]{6}\\.tar\\.zst$" }
      }
      command = "/opt/minecraft/bin/restore-apply.sh '{{ key }}'"
    }
  }
}

resource "aws_ssm_document" "operation" {
  for_each        = local.documents
  name            = each.key
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Minecraft host operation: ${each.key}"
    parameters    = each.value.parameters
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "run"
      inputs = {
        timeoutSeconds = tostring(each.value.timeout)
        runCommand     = [each.value.command]
      }
    }]
  })
}

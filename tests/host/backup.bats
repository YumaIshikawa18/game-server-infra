#!/usr/bin/env bats
# バックアップと停止処理（reliability-design.md §2・§3）。

load helpers

setup() {
  setup_host
}

@test "hourly: 25 世代あれば最も古い 1 件だけを削除する" {
  backup_keys hourly 25
  run bash -c '. "$MC_BIN/common.sh"; . "$MC_BIN/backup-lib.sh"; trim_generations hourly 24'
  [ "$status" -eq 0 ]
  [ "$(count_calls 's3api delete-object')" -eq 1 ]
  grep -q 'delete-object .*--key hourly/20261101-010000.tar.zst' "$CALLS"
}

@test "hourly: 24 世代なら削除しない" {
  backup_keys hourly 24
  run bash -c '. "$MC_BIN/common.sh"; . "$MC_BIN/backup-lib.sh"; trim_generations hourly 24'
  [ "$status" -eq 0 ]
  [ "$(count_calls 's3api delete-object')" -eq 0 ]
}

@test "stop: 8 世代なら 1 件、7 世代なら 0 件を削除する" {
  backup_keys stop 8
  run bash -c '. "$MC_BIN/common.sh"; . "$MC_BIN/backup-lib.sh"; trim_generations stop 7'
  [ "$(count_calls 's3api delete-object')" -eq 1 ]
  : >"$CALLS"
  backup_keys stop 7
  run bash -c '. "$MC_BIN/common.sh"; . "$MC_BIN/backup-lib.sh"; trim_generations stop 7'
  [ "$(count_calls 's3api delete-object')" -eq 0 ]
}

@test "hourly: 停止処理がロックを持っていればバックアップしない" {
  exec 9>"$MC_LOCK_FILE"
  flock 9
  run "$MC_BIN/backup-hourly.sh"
  exec 9>&-
  [ "$status" -eq 0 ]
  [ "$(count_calls 'rcon-cli save-off')" -eq 0 ]
  [ "$(count_calls 's3api put-object')" -eq 0 ]
}

@test "hourly: アップロードに失敗しても save-on に戻し、失敗を記録する" {
  export STUB_PUT_FAIL=1
  run "$MC_BIN/backup-hourly.sh"
  [ "$status" -ne 0 ]
  [ "$(count_calls 'rcon-cli save-on')" -ge 1 ]
  grep -q 'metric-name BackupFailures --value 1' "$CALLS"
  grep -q 'sns publish' "$CALLS"
  [ -z "$(find "$MC_ROOT" -maxdepth 1 -name '.backup.*')" ]
}

@test "hourly: S3 の SHA-256 が一致しなければ失敗する" {
  export STUB_REMOTE_CHECKSUM=bWlzbWF0Y2g=
  run "$MC_BIN/backup-hourly.sh"
  [ "$status" -ne 0 ]
  [ "$(count_calls 'rcon-cli save-on')" -ge 1 ]
}

@test "hourly: 成功したら照合して世代を整理し、save-on に戻す" {
  backup_keys hourly 3
  run "$MC_BIN/backup-hourly.sh"
  [ "$status" -eq 0 ]
  grep -q 'put-object .*--key hourly/' "$CALLS"
  grep -q 'head-object .*--checksum-mode ENABLED' "$CALLS"
  grep -q 'metric-name BackupFailures --value 0' "$CALLS"
  [ "$(count_calls 'rcon-cli save-on')" -eq 1 ]
}

@test "stop: 置き換えでバックアップに失敗したら停止せず失敗を返す" {
  export STUB_PUT_FAIL=1
  run "$MC_BIN/stop.sh" replace true
  [ "$status" -eq 1 ]
  [ "$(count_calls 'systemd-run')" -eq 0 ]
  [ "$(count_calls 'docker stop')" -eq 0 ]
  [ "$(count_calls 'rcon-cli save-on')" -eq 1 ]
  [ ! -e "$MC_STATE_DIR/stopping" ]
}

@test "stop: 通常はバックアップ後にコンテナを止め、EC2 の停止を予約する" {
  run "$MC_BIN/stop.sh" manual
  [ "$status" -eq 0 ]
  grep -q 'put-object .*--key stop/' "$CALLS"
  grep -q 'docker stop -t 60 mc' "$CALLS"
  grep -q 'systemd-run .*ec2 stop-instances' "$CALLS"
  [ -e "$MC_STATE_DIR/stopping" ]
}

@test "stop: 通常停止はバックアップに失敗しても止める（警告付き）" {
  export STUB_PUT_FAIL=1
  run "$MC_BIN/stop.sh" idle
  [ "$status" -eq 0 ]
  grep -q 'systemd-run' "$CALLS"
  grep -q 'metric-name BackupFailures --value 1' "$CALLS"
}

@test "stop: 許可しない理由は拒否する" {
  run "$MC_BIN/stop.sh" 'manual;reboot'
  [ "$status" -eq 2 ]
  [ "$(count_calls 'create-tags')" -eq 0 ]
}

@test "hourly: 圧縮に失敗したら何もアップロードせず失敗する（Codex P1）" {
  fail_tar
  run "$MC_BIN/backup-hourly.sh"
  [ "$status" -ne 0 ]
  [ "$(count_calls 's3api put-object')" -eq 0 ]
  grep -q 'metric-name BackupFailures --value 1' "$CALLS"
  [ "$(count_calls 'rcon-cli save-on')" -ge 1 ]
}

@test "hourly: save-off に失敗したら通知して失敗し、save-on に戻す" {
  export STUB_RCON_FAIL=1
  run "$MC_BIN/backup-hourly.sh"
  [ "$status" -ne 0 ]
  [ "$(count_calls 's3api put-object')" -eq 0 ]
  grep -q 'sns publish' "$CALLS"
  [ "$(count_calls 'rcon-cli save-on')" -ge 1 ]
}

@test "hourly: 照合に失敗したアップロードは削除する" {
  export STUB_REMOTE_CHECKSUM=bWlzbWF0Y2g=
  run "$MC_BIN/backup-hourly.sh"
  [ "$status" -ne 0 ]
  grep -q 'delete-object .*--key hourly/' "$CALLS"
}

@test "stop: 置き換えで圧縮に失敗したら停止しない（Codex P1）" {
  fail_tar
  run "$MC_BIN/stop.sh" replace true
  [ "$status" -eq 1 ]
  [ "$(count_calls 's3api put-object')" -eq 0 ]
  [ "$(count_calls 'systemd-run')" -eq 0 ]
}

@test "stop: 置き換えで RCON の保存に失敗したら、アップロードも停止もしない（Codex P1）" {
  export STUB_RCON_FAIL=1
  run "$MC_BIN/stop.sh" replace true
  [ "$status" -eq 1 ]
  [ "$(count_calls 's3api put-object')" -eq 0 ]
  [ "$(count_calls 'systemd-run')" -eq 0 ]
  [ "$(count_calls 'docker stop')" -eq 0 ]
  [ "$(count_calls 'rcon-cli save-on')" -eq 1 ]
  [ ! -e "$MC_STATE_DIR/stopping" ]
}

@test "stop: 通常停止で保存に失敗しても止めるが、古い世代は削除しない" {
  export STUB_RCON_FAIL=1
  backup_keys stop 8
  run "$MC_BIN/stop.sh" manual
  [ "$status" -eq 0 ]
  grep -q 'systemd-run' "$CALLS"
  [ "$(count_calls 's3api delete-object')" -eq 0 ]
  grep -q 'metric-name BackupFailures --value 1' "$CALLS"
}

#!/usr/bin/env bats
# 復元（reliability-design.md §8、cd-config.md「ホスト側との契約」）。
# どの段階で失敗しても現在のワールドを残す。

load helpers

setup() {
  setup_host
  export STUB_RUNNING=false
  : >"$MC_STATE_DIR/restore"
  mkdir -p "$BATS_TEST_TMPDIR/backup/world"
  printf 'restored\n' >"$BATS_TEST_TMPDIR/backup/world/level.dat"
}

make_archive() {
  tar --zstd -C "$BATS_TEST_TMPDIR/backup" -cf "$STUB_DIR/restore.tar.zst" .
  openssl dgst -sha256 -binary "$STUB_DIR/restore.tar.zst" | base64 >"$STUB_DIR/checksum"
}

@test "正しいバックアップなら展開し、以前のワールドを退避する" {
  make_archive
  run "$MC_BIN/restore-apply.sh" stop/20261101-120000.tar.zst
  [ "$status" -eq 0 ]
  [ "$(cat "$MC_ROOT/data/world/level.dat")" = "restored" ]
  [ "$(cat "$MC_ROOT/data.pre-restore/world/level.dat")" = "level-data" ]
}

@test "許可しないキーは拒否する" {
  run "$MC_BIN/restore-apply.sh" '../stop/20261101-120000.tar.zst'
  [ "$status" -eq 2 ]
  [ "$(count_calls 'get-object')" -eq 0 ]
}

@test "復元モードでなければ拒否する" {
  rm -f "$MC_STATE_DIR/restore"
  run "$MC_BIN/restore-apply.sh" stop/20261101-120000.tar.zst
  [ "$status" -eq 2 ]
}

@test "SHA-256 が一致しなければワールドを変えない" {
  make_archive
  printf 'bWlzbWF0Y2g=\n' >"$STUB_DIR/checksum"
  run "$MC_BIN/restore-apply.sh" hourly/20261101-120000.tar.zst
  [ "$status" -eq 1 ]
  [ "$(cat "$MC_ROOT/data/world/level.dat")" = "level-data" ]
  [ ! -e "$MC_ROOT/data.pre-restore" ]
}

@test "シンボリックリンクを含むアーカイブは展開しない" {
  ln -s /etc/passwd "$BATS_TEST_TMPDIR/backup/world/link"
  make_archive
  run "$MC_BIN/restore-apply.sh" stop/20261101-120000.tar.zst
  [ "$status" -eq 1 ]
  [ "$(cat "$MC_ROOT/data/world/level.dat")" = "level-data" ]
  [ ! -e "$MC_ROOT/data.pre-restore" ]
}

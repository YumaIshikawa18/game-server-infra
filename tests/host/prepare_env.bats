#!/usr/bin/env bats
# 起動前の準備（infrastructure-specification.md の起動処理）。プレイヤー名は架空のものだけを使う。

load helpers

setup() {
  setup_host
  export SECRETS_ENV="$BATS_TEST_TMPDIR/etc/secrets.env"
  export OPS_FILE="$MC_ROOT/data/ops.json"
  export STUB_WHITELIST="player_one,PlayerTwo"
  unset STUB_OPS STUB_OPS_ERROR STUB_WHITELIST_FAIL
}

# 失敗しても前回の内容が残ることを確かめるため、前回の起動で書かれたファイルを置く。
seed_previous_files() {
  mkdir -p "$(dirname "$SECRETS_ENV")"
  printf 'previous-secrets\n' >"$SECRETS_ENV"
  printf 'previous-ops\n' >"$OPS_FILE"
}

assert_previous_files_kept() {
  [ "$(cat "$SECRETS_ENV")" = "previous-secrets" ]
  [ "$(cat "$OPS_FILE")" = "previous-ops" ]
}

assert_start_failed() {
  [ "$status" -ne 0 ]
  [ "$(count_calls 'sns publish')" -eq 1 ]
  grep -q '"event":"start_failed"' "$CALLS"
}

# 値が画面の出力、ログ、通知のいずれにも出ていないこと。
assert_not_exposed() {
  [[ $output != *"$1"* ]]
  [[ $(cat "$MC_LOG_FILE" "$CALLS") != *"$1"* ]]
}

@test "一覧が 1 名なら OPS= と ops.json にレベル 3 で書く" {
  export STUB_OPS="player_one"
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  grep -qx 'WHITELIST=player_one,PlayerTwo' "$SECRETS_ENV"
  grep -qx 'OPS=player_one' "$SECRETS_ENV"
  grep -qE '^RCON_PASSWORD=[0-9a-f]{48}$' "$SECRETS_ENV"
  jq -e '. == [{uuid: "", name: "player_one", level: 3}]' "$OPS_FILE"
}

@test "一覧の空白を除いて処理する" {
  export STUB_OPS=" player_one , PlayerTwo "
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  grep -qx 'OPS=player_one,PlayerTwo' "$SECRETS_ENV"
  jq -e 'map(.name) == ["player_one", "PlayerTwo"]' "$OPS_FILE"
}

@test "一覧が 2 名なら ops.json は 2 項目で、どちらもレベル 3 にする" {
  export STUB_OPS="player_one,PlayerTwo"
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  jq -e 'length == 2 and all(.level == 3)' "$OPS_FILE"
}

@test "一覧にない古い名前は ops.json から消える" {
  export STUB_OPS="player_one"
  printf '[{"uuid":"00000000-0000-0000-0000-00000000abcd","name":"stale_player","level":4}]\n' >"$OPS_FILE"
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  jq -e 'map(.name) == ["player_one"]' "$OPS_FILE"
}

@test "パラメータが未登録なら通知せず、OPS= を空で書いて ops.json を [] にする" {
  export STUB_OPS_ERROR="ParameterNotFound"
  printf '[{"uuid":"","name":"stale_player","level":3}]\n' >"$OPS_FILE"
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  grep -qx 'OPS=' "$SECRETS_ENV"
  jq -e '. == []' "$OPS_FILE"
  [ "$(count_calls 'sns publish')" -eq 0 ]
  grep -q 'event=env_prepared players=2 ops=0' "$MC_LOG_FILE"
  assert_not_exposed "stub-error-detail"
}

@test "権限エラーで読めなければ起動を中止し、ファイルを変えず、aws のエラーを出さない" {
  export STUB_OPS_ERROR="AccessDeniedException"
  seed_previous_files
  run "$MC_BIN/prepare-env.sh"
  assert_start_failed
  assert_previous_files_kept
  grep -q 'event=ops_unavailable' "$MC_LOG_FILE"
  assert_not_exposed "stub-error-detail"
  assert_not_exposed "AccessDeniedException"
}

@test "一覧の形式が不正なら起動を中止し、値を出さない" {
  export STUB_OPS="name;x"
  seed_previous_files
  run "$MC_BIN/prepare-env.sh"
  assert_start_failed
  assert_previous_files_kept
  grep -q 'event=ops_invalid' "$MC_LOG_FILE"
  assert_not_exposed "name;x"
}

@test "登録された値が空白だけなら未登録とは扱わず、起動を中止する" {
  export STUB_OPS="   "
  seed_previous_files
  run "$MC_BIN/prepare-env.sh"
  assert_start_failed
  assert_previous_files_kept
  grep -q 'event=ops_invalid' "$MC_LOG_FILE"
}

@test "ホワイトリストにない名前なら不一致と分かる文面で中止し、名前を出さない" {
  export STUB_OPS="player_one,outsider_one"
  seed_previous_files
  run "$MC_BIN/prepare-env.sh"
  assert_start_failed
  assert_previous_files_kept
  grep -q 'event=ops_not_whitelisted' "$MC_LOG_FILE"
  grep -q 'オペレーターの一覧にホワイトリストにない名前があるため' "$CALLS"
  assert_not_exposed "outsider_one"
}

@test "ホワイトリストと大文字小文字だけが異なる名前は受け付ける" {
  export STUB_OPS="PLAYER_ONE"
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  grep -qx 'OPS=PLAYER_ONE' "$SECRETS_ENV"
  jq -e 'map(.name) == ["PLAYER_ONE"]' "$OPS_FILE"
}

@test "重複する名前はエラーにせず 1 名として数える" {
  export STUB_OPS="player_one,PLAYER_ONE,PlayerTwo"
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  grep -qx 'OPS=player_one,PlayerTwo' "$SECRETS_ENV"
  jq -e 'map(.name) == ["player_one", "PlayerTwo"]' "$OPS_FILE"
  grep -q 'ops=2' "$MC_LOG_FILE"
}

@test "ops.json の一時ファイルを書けなければ起動を中止し、secrets.env を変えない" {
  export STUB_OPS="player_one"
  mkdir -p "$(dirname "$SECRETS_ENV")"
  printf 'previous-secrets\n' >"$SECRETS_ENV"
  # root はパーミッションで止められないため、親がファイルであるパスを指定する。
  printf 'not-a-directory\n' >"$BATS_TEST_TMPDIR/blocked"
  export OPS_FILE="$BATS_TEST_TMPDIR/blocked/ops.json"
  run "$MC_BIN/prepare-env.sh"
  assert_start_failed
  [ "$(cat "$SECRETS_ENV")" = "previous-secrets" ]
  [ ! -e "$SECRETS_ENV.new" ]
  grep -q 'event=ops_seed_failed' "$MC_LOG_FILE"
}

@test "ホワイトリストを読めなければ起動を中止する" {
  export STUB_WHITELIST_FAIL=1
  export STUB_OPS="player_one"
  seed_previous_files
  run "$MC_BIN/prepare-env.sh"
  assert_start_failed
  assert_previous_files_kept
  grep -q 'event=whitelist_unavailable' "$MC_LOG_FILE"
}

@test "ホワイトリストの形式が不正なら起動を中止する" {
  export STUB_WHITELIST="name;x"
  export STUB_OPS="player_one"
  seed_previous_files
  run "$MC_BIN/prepare-env.sh"
  assert_start_failed
  assert_previous_files_kept
  grep -q 'event=whitelist_invalid' "$MC_LOG_FILE"
  assert_not_exposed "name;x"
}

@test "正常時は secrets.env が 0600、ops.json の所有者が UID 1000 で、一時ファイルを残さない" {
  export STUB_OPS="player_one"
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$SECRETS_ENV")" = "600" ]
  [ "$(stat -c %u "$OPS_FILE")" = "1000" ]
  [ "$(stat -c %a "$OPS_FILE")" = "600" ]
  [ ! -e "$SECRETS_ENV.new" ]
  [ -z "$(find "$MC_ROOT/data" -maxdepth 1 -name 'ops.json.*')" ]
}

@test "正常時のログには players= と ops= の人数があり、名前がない" {
  export STUB_OPS="player_one"
  run "$MC_BIN/prepare-env.sh"
  [ "$status" -eq 0 ]
  grep -q 'event=env_prepared players=2 ops=1' "$MC_LOG_FILE"
  [ "$(count_calls 'sns publish')" -eq 0 ]
  assert_not_exposed "player_one"
  assert_not_exposed "PlayerTwo"
}

# ホスト上のスクリプトのテスト用ヘルパー。外部コマンド（aws / docker / curl / systemd-run）をスタブにする。
# スタブの呼び出しは $CALLS に 1 行ずつ記録する。

BIN_DIR="$BATS_TEST_DIRNAME/../../modules/minecraft_server/files/bin"

setup_host() {
  export MC_BIN="$BIN_DIR"
  export MC_ROOT="$BATS_TEST_TMPDIR/srv"
  export MC_STATE_DIR="$BATS_TEST_TMPDIR/run"
  export MC_LOCK_FILE="$MC_ROOT/.lock"
  export MC_LOG_FILE="$BATS_TEST_TMPDIR/log/scripts.log"
  export MC_HOST_ENV="$BATS_TEST_TMPDIR/host.env"
  # コンテナのルートは常にマウントポイント。マウントされていない場合は各テストで上書きする。
  export MC_WORLD_MOUNT=/
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"
  export CALLS="$STUB_DIR/calls"
  mkdir -p "$MC_ROOT/data/world" "$MC_STATE_DIR" "$STUB_DIR/bin"
  printf 'level-data\n' >"$MC_ROOT/data/world/level.dat"
  printf 'MC_REGION=ap-northeast-1\nMC_BUCKET=example-backup\nMC_TOPIC_ARN=arn:aws:sns:ap-northeast-1:123456789012:example-events\nMC_PARAM_PREFIX=/example/minecraft\n' >"$MC_HOST_ENV"
  : >"$CALLS"
  write_stubs
  export PATH="$STUB_DIR/bin:$PATH"
}

write_stubs() {
  cat >"$STUB_DIR/bin/aws" <<'STUB'
#!/usr/bin/env bash
printf 'aws %s\n' "$*" >>"$CALLS"
args=" $* "
value_of() {
  local previous=""
  for arg in "$@"; do
    if [[ $previous == "$1" ]]; then printf '%s' "$arg"; return; fi
    previous=$arg
  done
}
case "$args" in
  *" s3api list-objects-v2 "*) cat "$STUB_DIR/list.json" 2>/dev/null || printf 'null\n' ;;
  *" s3 cp "*)
    [[ ${STUB_PUT_FAIL:-0} == 1 ]] && exit 1
    # アップロードしたファイルのサイズと、メタデータの sha256 を S3 側の値として覚える。
    stat -c %s "$3" >"$STUB_DIR/size"
    previous=""
    for arg in "$@"; do
      [[ $previous == --metadata ]] && printf '%s' "${arg#sha256=}" >"$STUB_DIR/checksum"
      previous=$arg
    done ;;
  *" s3api head-object "*ContentLength*)
    printf '%s\t%s\n' "$(cat "$STUB_DIR/size" 2>/dev/null)" "${STUB_REMOTE_CHECKSUM:-$(cat "$STUB_DIR/checksum" 2>/dev/null)}" ;;
  *" s3api head-object "*Metadata.sha256*) printf '%s\n' "${STUB_REMOTE_CHECKSUM:-$(cat "$STUB_DIR/checksum" 2>/dev/null)}" ;;
  *" s3api get-object "*) cp "$STUB_DIR/restore.tar.zst" "${@: -1}" ;;
  *" s3api list-object-versions "*) printf '123\n' ;;
  *" ec2 describe-tags "*) printf '%s\n' "${STUB_MODE:-None}" ;;
  *" ssm get-parameter "*) printf '%s\n' "${STUB_WHITELIST:-player_one,PlayerTwo}" ;;
esac
exit 0
STUB
  cat >"$STUB_DIR/bin/docker" <<'STUB'
#!/usr/bin/env bash
printf 'docker %s\n' "$*" >>"$CALLS"
case "$1" in
  inspect) printf '%s\n' "${STUB_RUNNING:-true}" ;;
  exec)
    shift 2
    if [[ $1 == rcon-cli ]]; then
      # STUB_RCON_FAIL=1 のときは保存系のコマンド（save-off / save-all）だけを失敗させる。
      [[ ${STUB_RCON_FAIL:-0} == 1 && $2 == save-* && $2 != save-on ]] && exit 1
      [[ $2 == list ]] && printf 'There are %s of a max of 10 players online:\n' "${STUB_PLAYERS:-0}"
      exit 0
    fi
    [[ $1 == mc-monitor ]] && exit "${STUB_PING:-0}" ;;
esac
exit 0
STUB
  cat >"$STUB_DIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$CALLS"
url=${*: -1}
output=""
previous=""
for arg in "$@"; do
  [[ $previous == -o ]] && output=$arg
  previous=$arg
done
case "$url" in
  *latest/api/token) printf 'token\n' ;;
  *meta-data/instance-id) printf 'i-0123456789abcdef0\n' ;;
  https://*)
    source_file="$STUB_DIR/downloads/${url##*/}"
    [[ -f $source_file ]] || exit 22
    cp "$source_file" "$output" ;;
  *) exit 7 ;;
esac
STUB
  cat >"$STUB_DIR/bin/systemd-run" <<'STUB'
#!/usr/bin/env bash
printf 'systemd-run %s\n' "$*" >>"$CALLS"
STUB
  chmod +x "$STUB_DIR"/bin/*
}

# list-objects-v2 が返すキーを用意する（kind の n 件、1 時間ずつずらす）。
backup_keys() {
  local kind=$1 count=$2 index
  {
    printf '['
    for ((index = 1; index <= count; index++)); do
      ((index > 1)) && printf ','
      printf '"%s/20261101-%02d0000.tar.zst"' "$kind" "$index"
    done
    printf ']\n'
  } >"$STUB_DIR/list.json"
}

# tar を失敗させる（ディスク不足や読み取りエラーの代わり）。
fail_tar() {
  printf '#!/usr/bin/env bash\nprintf "tar %%s\\n" "$*" >>"$CALLS"\nexit 2\n' >"$STUB_DIR/bin/tar"
  chmod +x "$STUB_DIR/bin/tar"
}

count_calls() {
  grep -c -- "$1" "$CALLS" || true
}

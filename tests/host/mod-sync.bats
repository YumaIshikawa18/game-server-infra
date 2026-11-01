#!/usr/bin/env bats
# MOD の取得と照合（FR3、NFR5.12）。sha256 が一致しない jar は配置しない。

load helpers

setup() {
  setup_host
  export MODS_JSON="$BATS_TEST_TMPDIR/mods.json"
  mkdir -p "$STUB_DIR/downloads"
  printf 'server-mod\n' >"$STUB_DIR/downloads/server.jar"
  printf 'client-mod\n' >"$STUB_DIR/downloads/client.jar"
  server_sum=$(sha256sum "$STUB_DIR/downloads/server.jar" | cut -d' ' -f1)
  client_sum=$(sha256sum "$STUB_DIR/downloads/client.jar" | cut -d' ' -f1)
}

@test "sha256 が一致すれば配置し、client 専用は置かない" {
  printf '[{"name":"server-mod","url":"https://example.com/server.jar","sha256":"%s","side":"both"},{"name":"client-mod","url":"https://example.com/client.jar","sha256":"%s","side":"client"}]\n' \
    "$server_sum" "$client_sum" >"$MODS_JSON"
  run "$MC_BIN/mod-sync.sh"
  [ "$status" -eq 0 ]
  [ -f "$MC_ROOT/data/mods/server-mod.jar" ]
  [ ! -e "$MC_ROOT/data/mods/client-mod.jar" ]
}

@test "sha256 が一致しなければ配置せず、既存の mods/ も変えない" {
  mkdir -p "$MC_ROOT/data/mods"
  printf 'old\n' >"$MC_ROOT/data/mods/previous.jar"
  printf '[{"name":"server-mod","url":"https://example.com/server.jar","sha256":"%064d","side":"server"}]\n' 0 >"$MODS_JSON"
  run "$MC_BIN/mod-sync.sh"
  [ "$status" -eq 1 ]
  [ -f "$MC_ROOT/data/mods/previous.jar" ]
  [ ! -e "$MC_ROOT/data/mods/server-mod.jar" ]
  [ -z "$(find "$MC_ROOT/mods-cache" -name '*.jar')" ]
  grep -q 'sns publish' "$CALLS"
}

@test "照合済みのキャッシュがあればダウンロードしない" {
  mkdir -p "$MC_ROOT/mods-cache"
  cp "$STUB_DIR/downloads/server.jar" "$MC_ROOT/mods-cache/${server_sum}.jar"
  printf '[{"name":"server-mod","url":"https://example.com/server.jar","sha256":"%s","side":"server"}]\n' "$server_sum" >"$MODS_JSON"
  run "$MC_BIN/mod-sync.sh"
  [ "$status" -eq 0 ]
  [ "$(count_calls 'curl .*example.com')" -eq 0 ]
}

@test "https 以外の URL は一覧の不正として拒否する" {
  printf '[{"name":"server-mod","url":"http://example.com/server.jar","sha256":"%s","side":"server"}]\n' "$server_sum" >"$MODS_JSON"
  run "$MC_BIN/mod-sync.sh"
  [ "$status" -eq 1 ]
  [ "$(count_calls 'curl .*example.com')" -eq 0 ]
}

@test "一覧から外した jar は mods/ から消える" {
  mkdir -p "$MC_ROOT/data/mods"
  printf 'old\n' >"$MC_ROOT/data/mods/removed.jar"
  printf '[]\n' >"$MODS_JSON"
  run "$MC_BIN/mod-sync.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$MC_ROOT/data/mods/removed.jar" ]
}

@test "ダウンロードに失敗した MOD があれば全体を失敗にする" {
  printf '[{"name":"missing-mod","url":"https://example.com/missing.jar","sha256":"%064d","side":"server"}]\n' 0 >"$MODS_JSON"
  run "$MC_BIN/mod-sync.sh"
  [ "$status" -eq 1 ]
  [ ! -e "$MC_ROOT/data/mods/missing-mod.jar" ]
}

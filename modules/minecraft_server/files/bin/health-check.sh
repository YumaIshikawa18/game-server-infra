#!/usr/bin/env bash
# mc-health-check ドキュメントから呼ばれる。server list ping が成功したときだけ 0 を返す。
set -euo pipefail
MC_BIN=${MC_BIN:-$(dirname "${BASH_SOURCE[0]}")}
# shellcheck source=common.sh
. "$MC_BIN/common.sh"

main() {
  if container_running && ping_server; then
    printf 'minecraft=up\n'
    return 0
  fi
  printf 'minecraft=down\n'
  return 1
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi

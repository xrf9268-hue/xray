#!/usr/bin/env bash

set -euo pipefail

fd_root="${XRF_BATS_FD_ROOT:-/dev/fd}"

if [[ -r "${fd_root}/0" ]]; then
  exit 0
fi

cat >&2 << EOF
bats-core requires a readable file-descriptor filesystem at ${fd_root}.
This environment does not expose ${fd_root}/0, so bats cannot use process substitution.
Linux workaround: sudo ln -sf /proc/self/fd /dev/fd
EOF

exit 2

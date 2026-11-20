#!/usr/bin/env bash
# Test that kb-index and kb-lint read both flat frontmatter and the nested metadata: block
# that the Claude Code harness writes. Usage: scripts/test-kb-frontmatter.sh
set -eu
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BIN="$REPO/bin/.local/bin"
T="$(mktemp -d "${TMPDIR:-/tmp}/kb-fm-test.XXXXXX")"
trap 'rm -rf "${T:?}"' EXIT
export KB_HOST_ENV="$T/none"
fail=0
check() { # check DESCRIPTION COMMAND...: the command must succeed
  local desc="$1"
  shift
  if "$@"; then echo "ok    $desc"; else echo "FAIL  $desc"; fail=1; fi
}
# shellcheck disable=SC2329 # called through check
lint_ok() { "$BIN/kb-lint" "$T/kb" >"$T/lint.out" 2>&1 || { cat "$T/lint.out"; return 1; }; }
# shellcheck disable=SC2329 # called through check
lint_fails() { ! "$BIN/kb-lint" "$T/kb" >/dev/null 2>&1; }

mkdir -p "$T/kb/rule" "$T/kb/projects/demo/rule" "$T/kb/learning" "$T/kb/incident" "$T/kb/reference"
printf '# Guide\n' >"$T/kb/GUIDE.md"
printf -- '---\ntype: rule\nscope: user\nstatus: active\nupdated: 2026-11-20\nsummary: Flat summary\n---\nbody\n' >"$T/kb/rule/flat-h.md"
printf -- '---\nname: ""\nmetadata:\n  node_type: memory\n  type: rule\n  scope: demo\n  status: active\n  updated: 2026-11-20\n  summary: Nested summary\n  originSessionId: abc\n---\nbody\n' >"$T/kb/projects/demo/rule/nested-h.md"

"$BIN/kb-index" "$T/kb"
check "root index shows the flat summary" grep -q 'flat-h.md): Flat summary' "$T/kb/INDEX.md"
check "project index shows the nested summary" grep -q 'nested-h.md): Nested summary' "$T/kb/projects/demo/INDEX.md"
check "kb-lint passes both shapes" lint_ok

# A nested note that lacks a summary must still fail
printf -- '---\nname: ""\nmetadata:\n  type: rule\n  scope: demo\n  status: active\n  updated: 2026-11-20\n---\nbody\n' >"$T/kb/projects/demo/rule/nosummary-h.md"
check "kb-lint still rejects a nested note without a summary" lint_fails
exit "$fail"

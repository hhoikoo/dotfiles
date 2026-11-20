#!/usr/bin/env bash
# Round-trip test of kb-sync and kb-index against a local bare repo, never a real remote.
# Usage: scripts/test-kb-sync.sh [SEED_KB]   SEED_KB (a git clone) seeds the remote; default is a small synthetic kb.
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
BIN="$REPO/bin/.local/bin"
T="$(mktemp -d "${TMPDIR:-/tmp}/kb-sync-test.XXXXXX")"
trap 'rm -rf "${T:?}"' EXIT
export KB_HOST_ENV="$T/host.env" KB_SETTLE=0 GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --file "$T/gitconfig" user.name test
git config --file "$T/gitconfig" user.email test@example.invalid
git config --file "$T/gitconfig" commit.gpgsign false
git config --file "$T/gitconfig" init.defaultBranch main
: >"$T/host.env"
fail=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
now() { python3 -c 'import time; print(time.time())'; }
secs() { python3 -c "print('%.2f' % ($2 - $1))"; }
under() { python3 -c "import sys; sys.exit(0 if $1 < $2 else 1)"; } # under SECONDS LIMIT
waitlock() { local i=0; while [ -d "$1/.git/kb-sync.lock" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done; ! [ -d "$1/.git/kb-sync.lock" ]; }
note() { # note KB TYPE NAME SUMMARY
  mkdir -p "$1/$2"
  printf -- '---\ntype: %s\nscope: user\nstatus: active\nupdated: 2026-11-20\nsummary: %s\n---\nbody\n' "$2" "$4" >"$1/$2/$3.md"
}

# remote: a bare clone of the seed kb (or a synthetic one)
if [ -n "${1:-}" ]; then
  git clone -q --bare "$1" "$T/remote.git"
else
  git init -q "$T/seed"
  printf 'INDEX.md\nMEMORY.md\n.sync-error\n' >"$T/seed/.gitignore"
  i=0; while [ "$i" -lt 40 ]; do note "$T/seed" rule "r$i-h" "Seed rule $i"; i=$((i + 1)); done
  git -C "$T/seed" add -A; git -C "$T/seed" commit -q -m seed
  git clone -q --bare "$T/seed" "$T/remote.git"
fi
git -C "$T/remote.git" symbolic-ref HEAD refs/heads/main
git clone -q "$T/remote.git" "$T/w1"
git clone -q "$T/remote.git" "$T/w2"
W1="$T/w1"; W2="$T/w2"
for w in "$W1" "$W2"; do git -C "$w" branch -q --set-upstream-to=origin/main main 2>/dev/null; done
run() { KB_DIR="$1" "$BIN/kb-sync" "${@:2}"; }
head_of() { git -C "$1" rev-parse HEAD; }

echo "== no changes"
run "$W1" start >"$T/start.out" 2>&1; rc=$?
check "start exits 0" test "$rc" = 0
check "start reports no error when the last sync was clean" bash -c "! grep -q 'last sync failed' '$T/start.out'"
waitlock "$W1"; check "start's background run finishes and frees the lock" test $? = 0
check "start's background run built the index" test -f "$W1/INDEX.md"
t0=$(now); run "$W1" end; rc=$?; t1=$(now)
check "end with no changes exits 0" test "$rc" = 0
echo "      end with no changes: $(secs "$t0" "$t1") s"
check "end with no changes is fast" under "$(secs "$t0" "$t1")" 1
check "end with no changes leaves no lock behind" test ! -d "$W1/.git/kb-sync.lock"
t0=$(now); "$BIN/kb-index" "$W1"; t1=$(now)
echo "      kb-index: $(secs "$t0" "$t1") s"

echo "== new note: local commit, background push"
note "$W1/projects/tproj" learning "one-h" "First new note"
run "$W1" end; rc=$?
check "end exits 0" test "$rc" = 0
check "end committed in the foreground" test "$(git -C "$W1" log -1 --format=%s)" = "Sync 1 notes from $(hostname -s 2>/dev/null || hostname)"
waitlock "$W1"
check "background run pushed the commit" test "$(head_of "$W1")" = "$(git -C "$T/remote.git" rev-parse main)"
check "no error file after a clean push" test ! -f "$W1/.sync-error"
check "the project index lists the new note" grep -q 'one-h.md): First new note' "$W1/projects/tproj/INDEX.md"
check "a second end has nothing to do" bash -c "! test -d '$W1/.git/kb-sync.lock' && KB_DIR='$W1' '$BIN/kb-sync' end"

echo "== second writer pulls on start"
run "$W2" start >"$T/start.out" 2>&1
waitlock "$W2"
check "start fetched and rebased in the background" test "$(head_of "$W2")" = "$(head_of "$W1")"
check "the project index lists the pulled note" grep -q 'one-h.md): First new note' "$W2/projects/tproj/INDEX.md"

echo "== two writers, different notes"
note "$W1" learning "two-a-h" "Writer one"
note "$W2" learning "two-b-h" "Writer two"
run "$W1" end; run "$W2" end
waitlock "$W1"; waitlock "$W2"
run "$W1" start >/dev/null 2>&1; waitlock "$W1"
check "remote has both notes" bash -c "git -C '$T/remote.git' ls-tree -r --name-only main | grep -q two-a-h && git -C '$T/remote.git' ls-tree -r --name-only main | grep -q two-b-h"
check "writer one converged to the remote" test "$(head_of "$W1")" = "$(git -C "$T/remote.git" rev-parse main)"
check "writer two has nothing left to push" test "$(git -C "$W2" rev-list --count origin/main..HEAD)" = 0

echo "== conflict"
run "$W2" start >/dev/null 2>&1; waitlock "$W2"
note "$W1/projects/tproj" learning "one-h" "Edited by writer one"
note "$W2/projects/tproj" learning "one-h" "Edited by writer two"
run "$W1" end; waitlock "$W1"
before="$(git -C "$T/remote.git" rev-parse main)"
run "$W2" end; rc=$?
check "end exits 0 even on a conflict" test "$rc" = 0
waitlock "$W2"
check "conflict wrote .sync-error" grep -q 'conflict' "$W2/.sync-error"
check "the conflicting local commit is kept" test "$(git -C "$W2" rev-list --count origin/main..HEAD)" = 1
check "nothing was force pushed" test "$(git -C "$T/remote.git" rev-parse main)" = "$before"
check "no rebase is left half done" test ! -d "$W2/.git/rebase-merge"
run "$W2" start >"$T/start.out" 2>&1
check "start reports the last error on stdout" grep -q 'the last sync failed' "$T/start.out"
waitlock "$W2"
run "$W2" sync >/dev/null 2>&1; rc=$?
check "foreground sync returns 2 on a conflict" test "$rc" = 2
git -C "$W2" reset -q --hard origin/main; rm -f "$W2/.sync-error"

echo "== planted secret"
note "$W1" learning "leak-h" "Has a key"
printf 'aws AKIAABCDEFGHIJKLMNOP\n' >>"$W1/learning/leak-h.md"
note "$W1" learning "fine-h" "Clean note"
run "$W1" end; rc=$?
check "end exits 0" test "$rc" = 0
waitlock "$W1"
check "the secret note was not committed" bash -c "! git -C '$W1' ls-files | grep -q leak-h"
check "the clean note was committed but nothing was pushed" bash -c "git -C '$W1' ls-files | grep -q fine-h && ! git -C '$T/remote.git' ls-tree -r --name-only main | grep -q fine-h"
check "the secret never reached the remote" bash -c "! git -C '$T/remote.git' ls-tree -r --name-only main | grep -q leak-h"
check "the error file names the secret" grep -q 'possible secret' "$W1/.sync-error"
run "$W1" sync >/dev/null 2>&1; rc=$?
check "foreground sync returns 3" test "$rc" = 3
rm -f "$W1/learning/leak-h.md" "$W1/.sync-error"
run "$W1" sync >/dev/null 2>&1; check "after the secret is removed a sync pushes the clean note" bash -c "git -C '$T/remote.git' ls-tree -r --name-only main | grep -q fine-h"

echo "== secret already in a local commit"
note "$W1" learning "pre-h" "Pre"
printf 'token: abcdefghijklmnopqrstuvwxyz0123456789\n' >>"$W1/learning/pre-h.md"
git -C "$W1" add -A; git -C "$W1" commit -q -m "bad commit"
run "$W1" start >/dev/null 2>&1; waitlock "$W1"
check "start's background run refuses to push it" grep -q 'possible secret' "$W1/.sync-error"
check "the remote does not have it" bash -c "! git -C '$T/remote.git' ls-tree -r --name-only main | grep -q pre-h"
git -C "$W1" reset -q --hard origin/main; rm -f "$W1/.sync-error"

echo "== exclusion and branch check"
printf 'KB_EXCLUDE=secretproj,other\n' >"$KB_HOST_ENV"
note "$W1/projects/secretproj" rule "x-h" "Excluded"
run "$W1" end 2>"$T/err.out"; waitlock "$W1"
check "an excluded project's note is refused" grep -q 'KB_EXCLUDE' "$T/err.out"
check "the excluded note stays untracked" bash -c "! git -C '$W1' ls-files | grep -q secretproj"
rm -rf "$W1/projects/secretproj"; : >"$KB_HOST_ENV"
git -C "$W1" checkout -q -b side
run "$W1" end 2>"$T/err.out"
check "a kb on another branch is not synced" grep -q 'branch side' "$W1/.sync-error"
git -C "$W1" checkout -q main; rm -f "$W1/.sync-error"

echo "== detached background run"
note "$W1" learning "slow-h" "Slow push"
cat >"$T/remote.git/hooks/pre-receive" <<'HOOK'
#!/bin/sh
sleep 3
HOOK
chmod +x "$T/remote.git/hooks/pre-receive"
t0=$(now); run "$W1" end | cat; t1=$(now)
echo "      end with a 3 s push: $(secs "$t0" "$t1") s"
check "end returns before the slow push finishes" under "$(secs "$t0" "$t1")" 2.5
check "the lock is held by the background run" test -d "$W1/.git/kb-sync.lock"
check "the lock names a live process" kill -0 "$(cat "$W1/.git/kb-sync.lock/pid")"
waitlock "$W1"
check "the slow push still arrived" bash -c "git -C '$T/remote.git' ls-tree -r --name-only main | grep -q slow-h"
rm -f "$T/remote.git/hooks/pre-receive"

echo "== stale lock and live lock"
mkdir "$W1/.git/kb-sync.lock"; echo 999999 >"$W1/.git/kb-sync.lock/pid"
note "$W1" learning "stale-h" "After a stale lock"
run "$W1" end 2>"$T/err.out"; waitlock "$W1"
check "a stale lock is cleared" grep -q 'stale lock' "$T/err.out"
check "the note went out" bash -c "git -C '$T/remote.git' ls-tree -r --name-only main | grep -q stale-h"
mkdir "$W1/.git/kb-sync.lock"; echo $$ >"$W1/.git/kb-sync.lock/pid"
run "$W1" end 2>"$T/err.out"
check "a live lock makes end skip" grep -q 'another kb-sync is running' "$T/err.out"
rm -rf "$W1/.git/kb-sync.lock"

echo "== offline remote"
git -C "$W1" remote set-url origin "$T/missing.git"
note "$W1" learning "off-h" "Offline note"
run "$W1" end; waitlock "$W1"
check "the note is committed locally" test "$(git -C "$W1" rev-list --count origin/main..HEAD)" = 1
check "no error file for plain offline" test ! -f "$W1/.sync-error"
git -C "$W1" remote set-url origin "$T/remote.git"
run "$W1" start >/dev/null 2>&1; waitlock "$W1"
check "the next start pushes it" test "$(head_of "$W1")" = "$(git -C "$T/remote.git" rev-parse main)"

exit "$fail"

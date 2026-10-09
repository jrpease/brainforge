#!/usr/bin/env bash
# A stale Brainforge checkout must not report a brain "up to date". Found for real: a marketplace
# clone six commits behind still shipped the brain's own version, so runtime-version == V and
# /upgrade said "up to date (v0.8.0)" to a brain two minor versions behind.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $1"; exit 1; }

awk '/^```python$/,/^```$/' "$ROOT/commands/upgrade.md" | sed '1d;$d' > "$TMP/bf-upgrade.py"
[ -s "$TMP/bf-upgrade.py" ] || fail "could not extract the upgrade fence"
G() { git -c user.email=fx@fx -c user.name=fx "$@"; }

# mkcheckout <dir> <version> [repository]: a plugin tree, not yet a git repo
mkcheckout() {
  mkdir -p "$1/.claude-plugin" "$1/scaffold/.claude/commands"
  printf '{ "name": "fx", "version": "%s",%s\n  "runtime": { "bump": [".claude/commands/**"], "remove": [], "once": [] } }\n' \
    "$2" "${3:+ \"repository\": \"$3\",}" > "$1/.claude-plugin/plugin.json"
  printf 'shipped sync\n' > "$1/scaffold/.claude/commands/sync.md"
}
# mkbrain <brain> <bf>: a brain whose birth manifest was written by a checkout at the same version
mkbrain() {
  mkdir -p "$1/.claude/commands"; printf 'shipped sync\n' > "$1/.claude/commands/sync.md"
  python3 "$TMP/bf-upgrade.py" "$2" "$1" "Acme" --apply > /dev/null   # adoption pass: no guard
}
# gitcheckout <dir> <version>: a git checkout level with a bare origin
gitcheckout() {
  mkcheckout "$1" "$2"; git -C "$1" init -q; git -C "$1" add -A; G -C "$1" commit -qm v"$2"
  git clone -q --bare "$1" "$1.origin"; git -C "$1" remote add origin "$1.origin"
  git -C "$1" fetch -q origin; git -C "$1" remote set-head origin -a > /dev/null
}
run() { python3 "$TMP/bf-upgrade.py" "$1" "$2" "Acme" > "$3" 2>&1; }

# --- A: level with origin -> UP-TO-DATE (the guard does not cry wolf) ---
gitcheckout "$TMP/a/bf" 0.0.2; mkbrain "$TMP/a/brain" "$TMP/a/bf"
run "$TMP/a/bf" "$TMP/a/brain" "$TMP/a.txt" || { cat "$TMP/a.txt"; fail "current checkout must exit 0"; }
[ "$(cat "$TMP/a.txt")" = "$(printf 'UP-TO-DATE\t0.0.2')" ] || fail "current checkout: expected UP-TO-DATE (got: $(cat "$TMP/a.txt"))"

# --- B: the reported bug. Origin moved on to 0.0.3; the checkout still ships 0.0.2 = the brain ---
gitcheckout "$TMP/b/bf" 0.0.2; mkbrain "$TMP/b/brain" "$TMP/b/bf"
git clone -q "$TMP/b/bf.origin" "$TMP/b/other"
sed -i.bak 's/"0.0.2"/"0.0.3"/' "$TMP/b/other/.claude-plugin/plugin.json"; rm "$TMP/b/other/.claude-plugin/plugin.json.bak"
G -C "$TMP/b/other" commit -qam v0.0.3; git -C "$TMP/b/other" push -q origin HEAD
run "$TMP/b/bf" "$TMP/b/brain" "$TMP/b.txt" && fail "stale checkout must exit 1"
grep -q '^UP-TO-DATE' "$TMP/b.txt"                     && fail "stale checkout still said UP-TO-DATE"
grep -qE '^STALE-CHECKOUT	1 commit\(s\) on origin/[A-Za-z]+ missing from HEAD' "$TMP/b.txt" || fail "expected STALE-CHECKOUT naming 1 commit (got: $(cat "$TMP/b.txt"))"
grep -q 're-read commands/upgrade.md' "$TMP/b.txt" || fail "STALE-CHECKOUT must tell the model to re-read upgrade.md after pulling (got: $(cat "$TMP/b.txt"))"
# after pulling, it routes normally again: brain 0.0.2 < checkout 0.0.3 -> steady-state pass
git -C "$TMP/b/bf" pull -q --ff-only origin "$(git -C "$TMP/b/bf" symbolic-ref --short HEAD)"
run "$TMP/b/bf" "$TMP/b/brain" "$TMP/b2.txt" || { cat "$TMP/b2.txt"; fail "pulled checkout must run"; }
grep -q '^UP-TO-DATE' "$TMP/b2.txt"                    && fail "pulled checkout: brain is behind, must not be UP-TO-DATE"

# --- C: dirty checkout -> refused ---
gitcheckout "$TMP/c/bf" 0.0.2; mkbrain "$TMP/c/brain" "$TMP/c/bf"
printf 'local edit\n' >> "$TMP/c/bf/scaffold/.claude/commands/sync.md"
run "$TMP/c/bf" "$TMP/c/brain" "$TMP/c.txt" && fail "dirty checkout must exit 1"
grep -q '^DIRTY-CHECKOUT' "$TMP/c.txt"                 || fail "expected DIRTY-CHECKOUT (got: $(cat "$TMP/c.txt"))"
# an untracked scratch file (bf-upgrade.py saved in the checkout) is not dirt
git -C "$TMP/c/bf" checkout -q -- .; touch "$TMP/c/bf/bf-upgrade.py"
run "$TMP/c/bf" "$TMP/c/brain" "$TMP/c2.txt" || fail "an untracked scratch file must not refuse (got: $(cat "$TMP/c2.txt"))"

# --- D: detached HEAD is allowed, judged against origin's default branch like any other ---
git -C "$TMP/c/bf" checkout -q --detach
run "$TMP/c/bf" "$TMP/c/brain" "$TMP/d.txt" || fail "detached, current: must exit 0 (got: $(cat "$TMP/d.txt"))"

# --- E: origin unreachable -> refused, never a bare UP-TO-DATE ---
rm -rf "$TMP/c/bf.origin"
run "$TMP/c/bf" "$TMP/c/brain" "$TMP/e.txt" && fail "unreachable origin must exit 1"
grep -q '^UNVERIFIED-CHECKOUT' "$TMP/e.txt"            || fail "expected UNVERIFIED-CHECKOUT (got: $(cat "$TMP/e.txt"))"

# --- F: non-git copy (the plugin cache): compared with the published plugin.json ---
mkcheckout "$TMP/f/pub" 0.0.3
mkcheckout "$TMP/f/bf" 0.0.2 "file://$TMP/f/pub"; mkbrain "$TMP/f/brain" "$TMP/f/bf"
run "$TMP/f/bf" "$TMP/f/brain" "$TMP/f.txt" && fail "stale plugin copy must exit 1"
grep -qE '^STALE-CHECKOUT	published 0\.0\.3, this copy ships 0\.0\.2' "$TMP/f.txt" || fail "expected STALE-CHECKOUT for the copy (got: $(cat "$TMP/f.txt"))"
grep -q 're-read commands/upgrade.md' "$TMP/f.txt" || fail "STALE-CHECKOUT (copy) must tell the model to re-read upgrade.md after updating (got: $(cat "$TMP/f.txt"))"
sed -i.bak 's/"0.0.3"/"0.0.2"/' "$TMP/f/pub/.claude-plugin/plugin.json"
run "$TMP/f/bf" "$TMP/f/brain" "$TMP/f2.txt" || fail "current plugin copy must exit 0 (got: $(cat "$TMP/f2.txt"))"
grep -q '^UP-TO-DATE' "$TMP/f2.txt"                    || fail "current plugin copy: expected UP-TO-DATE"

# --- F2: a plugin copy inside some OTHER repo (a dotfiles home) is judged as a copy, not as that repo ---
mkdir -p "$TMP/home"; git -C "$TMP/home" init -q; printf 'x\n' > "$TMP/home/.zshrc"
git -C "$TMP/home" add -A; G -C "$TMP/home" commit -qm dotfiles; printf 'dirty\n' >> "$TMP/home/.zshrc"
mkcheckout "$TMP/home/cache/bf" 0.0.2 "file://$TMP/f/pub"; mkbrain "$TMP/home/brain" "$TMP/home/cache/bf"
run "$TMP/home/cache/bf" "$TMP/home/brain" "$TMP/f3.txt" || fail "copy inside another repo must use the copy path (got: $(cat "$TMP/f3.txt"))"
grep -q '^UP-TO-DATE' "$TMP/f3.txt"                    || fail "copy inside another repo: expected UP-TO-DATE"

# --- F3: a git checkout with no remote named origin -> refused, and says why ---
gitcheckout "$TMP/h/bf" 0.0.2; mkbrain "$TMP/h/brain" "$TMP/h/bf"; git -C "$TMP/h/bf" remote rename origin upstream
run "$TMP/h/bf" "$TMP/h/brain" "$TMP/h.txt" && fail "no origin must exit 1"
grep -q '^UNVERIFIED-CHECKOUT.*no remote named origin' "$TMP/h.txt" || fail "must name the missing origin (got: $(cat "$TMP/h.txt"))"

# --- G: non-git copy with no repository -> refused ---
mkcheckout "$TMP/g/bf" 0.0.2; mkbrain "$TMP/g/brain" "$TMP/g/bf"
run "$TMP/g/bf" "$TMP/g/brain" "$TMP/g.txt" && fail "unverifiable copy must exit 1"
grep -q '^UNVERIFIED-CHECKOUT' "$TMP/g.txt"            || fail "expected UNVERIFIED-CHECKOUT (got: $(cat "$TMP/g.txt"))"

echo "PASS upgrade-stale-checkout"

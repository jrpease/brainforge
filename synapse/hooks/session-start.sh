#!/usr/bin/env bash
# synapse session start: keep every subscribed brain present and fresh, then render the map.
# The map is the ~300-token unconditional context: the model can never claim it didn't know
# the brain was there. Governing principle: NEVER appear grounded when not grounded — every
# failure prints a loud one-liner; the hook itself always exits 0.
set -u
[ -n "${SYNAPSE_BRAINS:-}" ] || exit 0
home="${SYNAPSE_HOME:-$HOME/.synapse}"
mkdir -p "$home"

# Network calls are BOUNDED. A blackholed remote — VPN down, captive portal, firewall drop —
# hangs a plain clone/pull for ~75s on TCP connect retries. That is past Claude Code's 60s hook
# default, so the hook gets killed and NO brain's map prints, including healthy already-cloned
# ones. Silence is the single outcome this hook must never produce, so the network never gets
# to cause it.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ConnectTimeout=5 -o BatchMode=yes}"
net_timeout="${SYNAPSE_NET_TIMEOUT:-8}"
err=""

# bounded <secs> <cmd...> — run with a deadline, 124 on timeout, first stderr line in $err.
# Hand-rolled because macOS ships no `timeout`, and this hook stays dependency-free.
bounded() {
  local secs=$1; shift
  local log; log=$(mktemp 2>/dev/null) || log=/dev/null
  "$@" >"$log" 2>&1 &
  local pid=$! n=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$n" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
      err="timed out after ${secs}s"
      [ "$log" = /dev/null ] || rm -f "$log"
      return 124
    fi
    sleep 1; n=$((n + 1))
  done
  wait "$pid"; local rc=$?
  err=$(head -1 "$log" 2>/dev/null)
  [ "$log" = /dev/null ] || rm -f "$log"
  return $rc
}

IFS=',' read -r -a remotes <<< "$SYNAPSE_BRAINS"
for remote in "${remotes[@]}"; do
  remote=$(printf '%s' "$remote" | sed 's/^ *//; s/ *$//; s:/*$::')
  [ -n "$remote" ] || continue
  name=$(basename -s .git "$remote")
  dir="$home/$name"

  # Origin verification: two remotes can share a basename (org1/brain, org2/brain).
  # If a same-named dir already exists but points at a different remote, never alias
  # onto it — fall back to a deterministic per-remote dir instead.
  if [ -d "$dir/.git" ]; then
    existing_remote=$(git -C "$dir" config --get remote.origin.url 2>/dev/null | sed 's:/*$::')
    if [ "$existing_remote" != "$remote" ]; then
      shorthash=$(printf '%s' "$remote" | shasum | cut -c1-8)
      echo "🧠 synapse: $name directory collision — $remote conflicts with existing clone of $existing_remote; using $name-$shorthash instead."
      name="$name-$shorthash"
      dir="$home/$name"
    fi
  fi

  # A directory that exists but holds no repo (an interrupted or killed first clone) made every
  # later clone fail forever. Move it aside instead of being permanently UNGROUNDED.
  if [ -d "$dir" ] && [ ! -d "$dir/.git" ]; then
    mv "$dir" "$dir.broken.$$" 2>/dev/null \
      && echo "🧠 synapse: $name had a non-repo directory — moved it aside and re-cloning."
  fi

  if [ ! -d "$dir/.git" ]; then
    bounded "$net_timeout" git clone --quiet "$remote" "$dir" \
      || { echo "🧠 synapse: $name UNAVAILABLE (${err:-clone failed}) — proceeding UNGROUNDED for this brain."; continue; }
  else
    if bounded "$net_timeout" git -C "$dir" fetch --quiet; then
      git -C "$dir" merge --ff-only --quiet '@{u}' 2>/dev/null \
        || { git -C "$dir" reset --hard --quiet '@{u}' 2>/dev/null \
             && echo "🧠 synapse: $name had diverged — reset to origin (this directory is a read-only mirror)."; }
    else
      # Distinguishing offline from expired-credentials from repo-deleted is the whole point of
      # surfacing git's own first line; the old code sent all three to 2>/dev/null.
      echo "🧠 synapse: $name not refreshed (${err:-fetch failed}) — using the current local copy."
    fi
  fi

  m="$dir/.brainforge/brain-manifest.json"
  if [ ! -f "$m" ]; then
    echo "🧠 synapse: $name has no manifest — read $dir/context/ directly (degraded routing)."
    continue
  fi

  gen_at=$(sed -n 's/^  "generatedAt": "\(.*\)",$/\1/p' "$m" | head -1)
  ctx_root=$(sed -n 's/^  "contextRoot": "\(.*\)",$/\1/p' "$m" | head -1)
  ctx_fp=$(sed -n 's/^  "contextFingerprint": "\(.*\)",$/\1/p' "$m" | head -1)
  last=$(git -C "$dir" log -1 --format=%cs 2>/dev/null || echo "?")

  echo "🧠 $name — brain at $dir (last change $last, map generated $gen_at)"

  # Staleness, by CONTENT. `contextFingerprint` is the git tree object id of the brain's
  # context root, stamped by gen-manifest.sh from the working tree it actually measured
  # (schema 3); recomputing it here is one rev-parse. Identical content gives an identical
  # oid, so this holds across commits, rebases and squashes — including the one flow no
  # commit sha can survive, where /sync lands the derived change and the regenerated
  # manifest in the SAME commit. That flow is why the old `generatedFrom` == HEAD check
  # could never pass: the commit that landed a fresh map was the commit that invalidated it,
  # so the warning was on permanently and people learned to scroll past it.
  # See gen-manifest.sh's FINGERPRINT CONTRACT — these two definitions move together.
  if [ -n "$ctx_fp" ]; then
    live_fp=$(git -C "$dir" rev-parse --verify -q "HEAD:${ctx_root:-context}" 2>/dev/null || echo "")
    [ "$ctx_fp" = "$live_fp" ] \
      || echo "   ⚠ map predates the current content — for detail, trust domain _index.md files over the map."
  else
    echo "   ⚠ map is pre-schema-3, so staleness cannot be checked — run \`bash .brainforge/gen-manifest.sh\` in the brain and commit the result."
  fi

  # Domain lines. Relies on the gen-manifest formatting contract:
  # domain keys at 6-space indent, one per line; file entries are single-line objects.
  # A domain only one intent reaches is marked ON ITS OWN LINE rather than warned about.
  # 21 of the 24 kinds are single-intent and every adapter mandates one, so a per-domain ⚠
  # would be permanent — precisely the disease a staleness warning that never turns off is.
  # The marker costs ~3 tokens, tells the reader the same thing, and implies no defect.
  cov="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/routing/coverage.sh"
  narrow=""
  [ -r "$cov" ] && narrow=$(bash "$cov" "$m" --narrow-paths 2>/dev/null || true)

  awk -v narrow="$narrow" '
    BEGIN { n = split(narrow, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") N[a[i]] = 1 }
    /^      "path": /  { sub(/^      "path": "/,"");  sub(/",$/,""); path=$0 }
    /^      "title": / { sub(/^      "title": "/,""); sub(/",$/,""); title=$0 }
    /^      "kinds": / { sub(/^      "kinds": \[/,""); sub(/\],$/,""); gsub(/"/,""); kinds=$0 }
    /^      "band": /  { sub(/^      "band": "/,"");  sub(/",$/,""); band=$0
                         printf "   - %s (%s) [%s] — %s%s\n", title, path, kinds, band, \
                                (path in N ? " · single-intent" : "") }
  ' "$m"

  # Unclassified domains stay visible, never vanish.
  sed -n '/"unclassified": \[/,/\]/p' "$m" | sed -n 's/^    "\(.*\)",\{0,1\}$/   - unclassified: \1/p'

  # Unindexed directories hold content with no _index.md, so the map cannot see them at all —
  # while the fingerprint above simultaneously reports the map as current. Visible, never silent.
  sed -n '/"unindexed": \[/,/\]/p' "$m" | sed -n 's/^    "\(.*\)",\{0,1\}$/   - unindexed: \1 (content with no _index.md — routing cannot reach it)/p'

  # Routing coverage. A domain with NO kinds is at least a visible orphan (the line above).
  # A domain declaring a kind no intent points at is a SILENT one: it renders like any healthy
  # domain, is never made a routing candidate, and so is neither loaded nor named in the
  # skill's "skipped:" slot. Same for an expensive domain behind a single intent — the band
  # gate opens it for exactly one phrasing and no other, which is how 21.8K tokens of a real
  # brain, including its only accurate doc on the subject, stayed unread.
  #
  # The join is delegated to routing/coverage.sh so there is ONE implementation of it: the
  # same one /synapse:coverage reports in full. Only the two findings that change what a
  # reader should OPEN reach the map; the rest are audit output and stay in the command.
  #
  # This cannot live in the brain (gen-manifest.sh) — a brain-local copy of the vocabulary
  # updates only by /upgrade PR, so it would start false-alarming the moment the plugin's
  # vocabulary grows and the brain hasn't upgraded. The reader always runs the current table.
  [ -r "$cov" ] && bash "$cov" "$m" --map

  echo "   canon/ = authored truth · derived/ = synced from source (check last-synced) · routing via the brain-routing skill"
done
exit 0

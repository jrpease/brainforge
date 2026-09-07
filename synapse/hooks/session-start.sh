#!/usr/bin/env bash
# synapse session start: keep every subscribed brain present and fresh, then render the map.
# The map is the ~300-token unconditional context: the model can never claim it didn't know
# the brain was there. Governing principle: NEVER appear grounded when not grounded — every
# failure prints a loud one-liner; the hook itself always exits 0.
set -u
[ -n "${SYNAPSE_BRAINS:-}" ] || exit 0
home="${SYNAPSE_HOME:-$HOME/.synapse}"
mkdir -p "$home"

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

  if [ ! -d "$dir/.git" ]; then
    git clone --quiet "$remote" "$dir" 2>/dev/null \
      || { echo "🧠 synapse: $name UNAVAILABLE (clone failed) — proceeding UNGROUNDED for this brain."; continue; }
  else
    git -C "$dir" pull --ff-only --quiet 2>/dev/null \
      || echo "🧠 synapse: $name could not fast-forward — using current local copy."
  fi

  m="$dir/.brainforge/brain-manifest.json"
  if [ ! -f "$m" ]; then
    echo "🧠 synapse: $name has no manifest — read $dir/context/ directly (degraded routing)."
    continue
  fi

  gen_at=$(sed -n 's/^  "generatedAt": "\(.*\)",$/\1/p' "$m" | head -1)
  gen_sha=$(sed -n 's/^  "generatedFrom": "\(.*\)",$/\1/p' "$m" | head -1)
  head_sha=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "")
  last=$(git -C "$dir" log -1 --format=%cs 2>/dev/null || echo "?")

  echo "🧠 $name — brain at $dir (last change $last, map generated $gen_at)"
  [ "$gen_sha" = "$head_sha" ] \
    || echo "   ⚠ map predates the latest change — for detail, trust domain _index.md files over the map."

  # Domain lines. Relies on the gen-manifest formatting contract:
  # domain keys at 6-space indent, one per line; file entries are single-line objects.
  awk '
    /^      "path": /  { sub(/^      "path": "/,"");  sub(/",$/,""); path=$0 }
    /^      "title": / { sub(/^      "title": "/,""); sub(/",$/,""); title=$0 }
    /^      "kinds": / { sub(/^      "kinds": \[/,""); sub(/\],$/,""); gsub(/"/,""); kinds=$0 }
    /^      "band": /  { sub(/^      "band": "/,"");  sub(/",$/,""); band=$0
                         printf "   - %s (%s) [%s] — %s\n", title, path, kinds, band }
  ' "$m"

  # Unclassified domains stay visible, never vanish.
  sed -n '/"unclassified": \[/,/\]/p' "$m" | sed -n 's/^    "\(.*\)",\{0,1\}$/   - unclassified: \1/p'

  # Unroutable kinds. A domain with NO kinds is at least a visible orphan (the line above).
  # A domain declaring a kind no intent points at is a SILENT one: it renders like any
  # healthy domain, is never made a routing candidate, and so is neither loaded nor named
  # in the skill's "skipped:" slot. Warn per KIND, not per domain — a domain can declare
  # one good kind and one dead one, and it is the dead kind that names the gap.
  #
  # The routable vocabulary IS the union of intents.json's values: a kind no intent
  # references is unroutable whether or not a catalog table lists it. So there is no second
  # list here to drift. This check cannot live in the brain (gen-manifest.sh) — a
  # brain-local copy updates only by /upgrade PR, so it would start false-alarming the
  # moment the plugin's vocabulary grows and the brain hasn't upgraded.
  #
  # Relies on intents.json's one-intent-per-line layout (a parsing contract, see
  # routing/README.md), since this hook stays dependency-free.
  intents="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/routing/intents.json"
  if [ -r "$intents" ]; then
    vocab=$(sed -n 's/^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*\[\(.*\)\],\{0,1\}[[:space:]]*$/\1/p' "$intents" \
            | tr ',' '\n' | tr -d ' "' | grep -v '^$' | sort -u)
    if [ -n "$vocab" ]; then
      awk '
        /^      "path": /  { sub(/^      "path": "/,"");  sub(/",$/,""); path=$0 }
        /^      "kinds": / { sub(/^      "kinds": \[/,""); sub(/\],$/,""); gsub(/"/,""); gsub(/ /,"")
                             n=split($0, a, ","); for (i=1; i<=n; i++) if (a[i] != "") print a[i], path }
      ' "$m" | while read -r kind path; do
        printf '%s\n' "$vocab" | grep -qxF "$kind" \
          || echo "   ⚠ unroutable kind \"$kind\" ($path) — no intent points at it; this content never routes."
      done
    fi
  fi

  echo "   canon/ = authored truth · derived/ = synced mirror (check last-synced) · routing via the brain-routing skill"
done
exit 0

#!/usr/bin/env bash
# Git filter for claude/.claude/settings.json; keeps per-machine keys out of commits.
# Usage: scripts/settings-filter.sh clean|smudge  (reads stdin, writes stdout)
#   clean   removes every key in the overlay, plus enabledPlugins entries from the
#           overlay's marketplaces, then sorts keys
#   smudge  merges the overlay in
# Overlay: ${CLAUDE_SETTINGS_OVERLAY:-~/.config/claude/local.json} (untracked, optional)
set -euo pipefail

overlay="${CLAUDE_SETTINGS_OVERLAY:-$HOME/.config/claude/local.json}"
ov='{}'
[[ -s $overlay ]] && ov="$(jq -c . "$overlay")"

case ${1:-} in
  clean)
    jq -S --argjson ov "$ov" '
      def strip($o):
        if ($o | type) == "object" and type == "object" then
          reduce ($o | keys_unsorted[]) as $k (.;
            if has($k) then
              if ($o[$k] | type) == "object" and (.[$k] | type) == "object" then
                .[$k] |= strip($o[$k]) | if .[$k] == {} then del(.[$k]) else . end
              else del(.[$k]) end
            else . end)
        else . end;
      (($ov.extraKnownMarketplaces // {}) | keys) as $local
      | strip($ov)
      | if (.enabledPlugins | type) == "object" then
          .enabledPlugins |= with_entries(select((.key | split("@") | last) as $m | ($local | index($m)) == null))
        else . end'
    ;;
  smudge)
    jq --argjson ov "$ov" '. * $ov'
    ;;
  *)
    echo "usage: $0 clean|smudge" >&2
    exit 2
    ;;
esac

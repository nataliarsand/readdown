#!/bin/bash
# snapshot-downloads.sh — track Readdown GitHub download counts over time.
#
#   snapshot-downloads.sh            record today's cumulative counts
#   snapshot-downloads.sh --report   show downloads per day (day-over-day deltas)
#
# GitHub only exposes a *cumulative* download_count per release asset — there is
# no per-day history. So we snapshot that total once a day; the difference
# between two consecutive snapshots is the number of downloads on that day.
#
# Runs daily via ~/Library/LaunchAgents/com.heya.readdown.download-snapshot.plist
# Data: metrics/downloads.csv  (gitignored)

set -euo pipefail
# launchd gives a minimal PATH — make sure `gh` (Homebrew) is findable.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

REPO="nataliarsand/readdown"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CSV="$DIR/metrics/downloads.csv"
mkdir -p "$DIR/metrics"

# ── Report mode ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--report" ]]; then
    if [[ ! -f "$CSV" ]]; then
        echo "No data yet — run the snapshot at least twice on different days."
        exit 0
    fi
    echo "Readdown downloads per day"
    echo "=========================="
    # Sum every asset per date → cumulative total, then diff consecutive days.
    awk -F, 'NR>1 { total[$1] += $4 } END { for (d in total) print d","total[d] }' "$CSV" \
      | sort \
      | awk -F, '
          BEGIN { printf "%-12s  %8s   %s\n", "Date", "New", "Cumulative" }
          {
            if (NR == 1) printf "%-12s  %8s   %d  (baseline)\n", $1, "-", $2
            else         printf "%-12s  %+8d   %d\n", $1, $2 - p, $2
            p = $2
          }'
    exit 0
fi

# ── Snapshot mode (default) ──────────────────────────────────────────────────
DATE="$(date +%F)"
[[ -f "$CSV" ]] || echo "date,tag,asset,count" > "$CSV"

if grep -q "^${DATE}," "$CSV"; then
    echo "$(date '+%F %T') — already recorded for $DATE, skipping"
    exit 0
fi

# One row per release asset: date,tag,asset,cumulative_count
gh api "repos/$REPO/releases" --paginate \
  --jq '.[] | .tag_name as $t | .assets[] | "\($t),\(.name),\(.download_count)"' \
  | sed "s/^/${DATE},/" >> "$CSV"

ROWS=$(grep -c "^${DATE}," "$CSV" || true)
echo "$(date '+%F %T') — recorded $DATE ($ROWS assets)"

#!/bin/bash
# One node's pool, launched on every node of a pbs/run-pairs-capacity.pbs job by mpiexec -ppn 1:
#   node-pool.sh <repo> <work> [schema]
# Picks its slice WORK/node<rank>/slice.tsv (rank = PALS_RANKID / PMI_RANK), runs bin/run-pairs.sh
# into WORK/node<rank>/ with a 30 s node sampler (node.log) like pbs/run-pairs-debug.pbs.
set -u
REPO=${1:?}; WORK=${2:?}; SCHEMA=${3:-}
k=${PALS_RANKID:-${PMI_RANK:-${PMIX_RANK:-${OMPI_COMM_WORLD_RANK:-}}}}
if [ -z "$k" ]; then echo "node-pool.sh: no rank variable (PALS_RANKID/PMI_RANK) on $(hostname)" >&2; exit 2; fi
D=$WORK/node$k
cd "$REPO" || exit 2
echo "$(date '+%F %T') node$k = $(hostname) nproc $(nproc) MemTotal $(awk '/MemTotal/{printf "%d GB", $2/1048576}' /proc/meminfo) pairs $(grep -vc '^#' "$D/slice.tsv") pids.max $(cat /sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup | head -1)/pids.max 2>/dev/null)" >> "$WORK/nodes.log"
( while true; do
    echo "$(date '+%F %T') avail_GB=$(awk '/MemAvailable/{printf "%d",$2/1048576}' /proc/meminfo) ours_GB=$(ps -u "$USER" -o rss=,comm= | awk '$2 ~ /^(lar|wire-cell|python3)$/ {s+=$1} END{printf "%.1f", s/1048576}') lar=$(pgrep -u "$USER" -x lar | wc -l) wct=$(pgrep -u "$USER" -x wire-cell | wc -l) pairs=$(pgrep -u "$USER" -f 'bin/run_pair.py' | wc -l) load=$(cut -d' ' -f1 /proc/loadavg) pids=$(cat /sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup | head -1)/pids.current 2>/dev/null)"
    sleep 30
  done >> "$D/node.log" ) &
SAMPLER=$!
bash bin/run-pairs.sh site/aurora.sh "$D/slice.tsv" "$D" ${SCHEMA:+"$SCHEMA"}
kill $SAMPLER 2>/dev/null
echo "$(date '+%F %T') node$k = $(hostname) $(tail -1 "$D/pool.log")" >> "$WORK/nodes.log"

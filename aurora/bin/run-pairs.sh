#!/bin/bash
# Run many reco1 / flat-CAF pairs through the three steps (HOST side).
#
#   run-pairs.sh <site config> <pairs.tsv> <workdir> [schema.json]
#
# pairs.tsv (bin/find-pairs.py): id <TAB> reality <TAB> reco1 path <TAB> caf path [<TAB> anything]
# schema: default schema/recTreeWireCell.schema.json next to this repo's bin/.
#
# A pool: one pair = one bin/run-pair.sh (steps 1-3 + validation, sequential).  The concurrency
# limit is re-read before every launch: WC_MAXPAR, or WC_DAY_MAXPAR between WC_DAY_START and
# WC_DAY_END local time, or a number in <workdir>/maxpar.override (live; delete to go back).
# No launch while our RSS > WC_MEM_GUARD_GB or the machine has < WC_SYS_MIN_AVAIL_GB available,
# or (WC_KRB_WAIT=1, FNAL) while there is no Kerberos ticket.  Running pairs are never killed.
# Pairs whose <id>/status is OK are skipped, so rerunning resumes.
set -u
SITE=${1:?site config}; PAIRS=${2:?pairs.tsv}; WORK=${3:?workdir}
BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCHEMA=${4:-$BIN/../schema/recTreeWireCell.schema.json}
source "$SITE"
mkdir -p "$WORK"; cp -f "$PAIRS" "$WORK/pairs.tsv"; cp -f "$SCHEMA" "$WORK/schema.json"
LOG=$WORK/pool.log
{
  echo "start   $(/bin/date '+%F %T %Z') on $(hostname)  site $SITE"
  echo "pairs   $(grep -vc '^#' "$PAIRS")  schema $SCHEMA (md5 $(md5sum < "$SCHEMA" | cut -c1-12))"
  echo "limits  MAXPAR $WC_MAXPAR, day $WC_DAY_MAXPAR ($WC_DAY_START-$WC_DAY_END), CPUSET '${WC_CPUSET:-}', mem guard ${WC_MEM_GUARD_GB} GB, min avail ${WC_SYS_MIN_AVAIL_GB} GB"
} >> "$WORK/RUN-RECORD.txt"

cur_maxpar() {
  local o h
  o=$(cat "$WORK/maxpar.override" 2>/dev/null)
  if [[ $o =~ ^[0-9]+$ ]] && [ "$o" -gt 0 ]; then echo "$o"; return; fi
  h=$((10#$(/bin/date +%H)))
  if [ $h -ge "$WC_DAY_START" ] && [ $h -lt "$WC_DAY_END" ]; then echo "$WC_DAY_MAXPAR"; else echo "$WC_MAXPAR"; fi
}
ourmem_gb() { ps -u "$USER" -o rss=,comm= | awk '$2 ~ /^(lar|wire-cell|python3)$/ {s+=$1} END {printf "%d", s/1048576}'; }
sys_avail_gb() { awk '/MemAvailable/ {printf "%d", $2/1048576}' /proc/meminfo; }

nrun=0; last=""
while IFS=$'\t' read -r id real r1 caf _rest; do
  [ -z "$id" ] && continue; [[ $id == \#* ]] && continue
  [ "$(cat "$WORK/$id/status" 2>/dev/null)" = OK ] && continue
  lim=$(cur_maxpar); [ "$lim" != "$last" ] && { echo "$(/bin/date '+%F %T') concurrency limit $lim" >> "$LOG"; last=$lim; }
  while [ $nrun -ge "$lim" ]; do wait -n; nrun=$((nrun-1)); lim=$(cur_maxpar); done
  while [ "$(ourmem_gb)" -ge "$WC_MEM_GUARD_GB" ] || [ "$(sys_avail_gb)" -lt "$WC_SYS_MIN_AVAIL_GB" ]; do /usr/bin/sleep 30; done
  if [ "${WC_KRB_WAIT:-0}" = 1 ] && ! /usr/bin/klist -s 2>/dev/null; then
    echo "$(/bin/date '+%F %T') no valid Kerberos ticket -- waiting (kinit to resume)" >> "$LOG"
    until /usr/bin/klist -s 2>/dev/null; do /usr/bin/sleep 60; done
  fi
  ( "$BIN/run-pair.sh" "$id" "$real" "$r1" "$caf" "$WORK" "$SCHEMA" > /dev/null 2>&1
    echo "$(/bin/date '+%F %T') $id $(cat "$WORK/$id/status" 2>/dev/null || echo 'NO STATUS (run-pair.sh did not run?)')" >> "$LOG" ) &
  nrun=$((nrun+1))
  /usr/bin/sleep 2
done < "$PAIRS"
wait
echo "$(/bin/date '+%F %T') pool done: $(cat "$WORK"/*/status 2>/dev/null | grep -cx OK) pairs OK" >> "$LOG"
python3 "$BIN/cost-summary.py" "$WORK" > "$WORK/cost-summary.md" 2>&1
echo "end     $(/bin/date '+%F %T %Z')" >> "$WORK/RUN-RECORD.txt"

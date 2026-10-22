#!/bin/bash
# Run many reco1 / flat-CAF pairs through the three steps (HOST side).
#
#   run-pairs.sh <site config> <pairs.tsv> <workdir> [schema.json]
#
# pairs.tsv (bin/find-pairs.py): id <TAB> reality <TAB> reco1 path <TAB> caf path [<TAB> anything]
# (the reco1 column may hold several comma-separated files: a multi-reco1 unit, see run_pair.py)
# schema: default schema/recTreeWireCell.schema.json next to this repo's bin/.
#
# A pool: one pair = one bin/run_pair.py (precheck, steps 1-3, validation, with the exception
# handling described there: timeouts, step-1 slicing around a failing event, step-2 retries,
# partial merge, every failed try kept).  The concurrency
# limit is re-read before every launch: WC_MAXPAR, or WC_DAY_MAXPAR between WC_DAY_START and
# WC_DAY_END local time on Monday-Friday (WC_WEEKEND_DAY_MAXPAR on Saturday/Sunday, default
# WC_DAY_MAXPAR), or a number in <control>/maxpar.override (live; delete to go back).
# <control> = WC_CONTROL_DIR (default the work dir): several pools can share one control dir, and
# bin/load-governor.sh writes maxpar.override / memguard.override there from the machine's load.
# WC_GLOBAL=1: the limit counts EVERY run_pair.py of this user (all pools together), not only this
# pool's, so concurrent pools share one budget.
# No launch while our RSS > WC_MEM_GUARD_GB or the machine has < WC_SYS_MIN_AVAIL_GB available,
# or while the job's cgroup has fewer than WC_PIDS_HEADROOM (400) tasks (processes + threads)
# left under its pids.max (Aurora PBS: 8192 per job).  A step-1 lar is ~25 tasks for its first
# ~90 s of setup and then jumps to 87-100 (the thread pool comes up after the geometry), so the
# pool also counts every unit launched within the last WC_RAMP_S (180) seconds as
# WC_TASKS_PER_UNIT (100) tasks still to come, and never runs more than
# (pids.max - headroom) / WC_TASKS_PER_UNIT units (77 on Aurora) however high MAXPAR is.  Without
# that, 100 units launched 2 s apart all ramped together and 221 of 800 died with
# "pthread_create failed: Resource temporarily unavailable" (BNB 1M job 8952145, 2026-10-22).
# or (WC_KRB_WAIT=1, FNAL) while there is no Kerberos ticket.  Running pairs are never killed.
# Pairs whose <id>/status is OK, PARTIAL or EMPTY are skipped (WC_RETRY_PARTIAL=1 reruns PARTIAL ones);
# a FAIL pair is rerun, reusing every finished step-1 slice and step-2 tar.
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
  echo "limits  MAXPAR $WC_MAXPAR, day $WC_DAY_MAXPAR ($WC_DAY_START-$WC_DAY_END; weekend day ${WC_WEEKEND_DAY_MAXPAR:-$WC_DAY_MAXPAR}), keep ${WC_KEEP:-all}, CPUSET '${WC_CPUSET:-}', mem guard ${WC_MEM_GUARD_GB} GB, min avail ${WC_SYS_MIN_AVAIL_GB} GB, cgroup pids.max $(cat "/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup 2>/dev/null | head -1)/pids.max" 2>/dev/null || echo none)"
} >> "$WORK/RUN-RECORD.txt"

CTRL=${WC_CONTROL_DIR:-$WORK}
cur_maxpar() {
  local o h
  o=$(cat "$CTRL/maxpar.override" 2>/dev/null)
  if [[ $o =~ ^[0-9]+$ ]] && [ "$o" -gt 0 ]; then echo "$o"; return; fi
  h=$((10#$(/bin/date +%H)))
  if [ $h -ge "$WC_DAY_START" ] && [ $h -lt "$WC_DAY_END" ]; then
    if [ "$(/bin/date +%u)" -ge 6 ]; then echo "${WC_WEEKEND_DAY_MAXPAR:-$WC_DAY_MAXPAR}"; else echo "$WC_DAY_MAXPAR"; fi
  else echo "$WC_MAXPAR"; fi
}
cur_memguard() {
  local o; o=$(cat "$CTRL/memguard.override" 2>/dev/null)
  if [[ $o =~ ^[0-9]+$ ]] && [ "$o" -gt 0 ]; then echo "$o"; else echo "$WC_MEM_GUARD_GB"; fi
}
running_global() { ps -u "$USER" -o args= | grep -c '[b]in/run_pair\.py'; }
ourmem_gb() { ps -u "$USER" -o rss=,comm= | awk '$2 ~ /^(lar|wire-cell|python3)$/ {s+=$1} END {printf "%d", s/1048576}'; }
sys_avail_gb() { awk '/MemAvailable/ {printf "%d", $2/1048576}' /proc/meminfo; }
CG=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup 2>/dev/null | head -1)
pids_left() {   # tasks left under the cgroup's pids.max; a big number when there is no limit
  local m c; m=$(cat "$CG/pids.max" 2>/dev/null); c=$(cat "$CG/pids.current" 2>/dev/null)
  if [[ $m =~ ^[0-9]+$ ]] && [[ $c =~ ^[0-9]+$ ]]; then echo $((m - c)); else echo 999999; fi
}
# the units launched within the last WC_RAMP_S seconds have not spawned their threads yet
RAMP_S=${WC_RAMP_S:-180}; TPU=${WC_TASKS_PER_UNIT:-100}; HEADROOM=${WC_PIDS_HEADROOM:-400}
LAUNCH_TIMES=()
n_ramping() {
  local now t keep=() n=0; now=$(/bin/date +%s)
  for t in "${LAUNCH_TIMES[@]}"; do if [ $((now - t)) -lt "$RAMP_S" ]; then keep+=("$t"); n=$((n+1)); fi; done
  LAUNCH_TIMES=("${keep[@]}"); echo $n
}
pids_room() {   # tasks left once the ramping units and this launch have spawned their threads
  echo $(( $(pids_left) - ($(n_ramping) + 1) * TPU ))
}
pids_cap() {    # the most units the cgroup can hold; a big number when there is no limit
  local m; m=$(cat "$CG/pids.max" 2>/dev/null)
  if [[ $m =~ ^[0-9]+$ ]]; then echo $(( (m - HEADROOM) / TPU )); else echo 999999; fi
}

nrun=0; last=""
while IFS=$'\t' read -r id real r1 caf _rest; do
  [ -z "$id" ] && continue; [[ $id == \#* ]] && continue
  st=$(cat "$WORK/$id/status" 2>/dev/null)
  [ "$st" = OK ] && continue; [[ $st == EMPTY* ]] && continue
  [ "$st" = PARTIAL ] && [ "${WC_RETRY_PARTIAL:-0}" != 1 ] && continue
  lim=$(cur_maxpar); cap=$(pids_cap); [ "$lim" -gt "$cap" ] && lim=$cap
  [ "$lim" != "$last" ] && { echo "$(/bin/date '+%F %T') concurrency limit $lim (pids cap $cap)" >> "$LOG"; last=$lim; }
  if [ "${WC_GLOBAL:-0}" = 1 ]; then
    while [ "$(running_global)" -ge "$lim" ]; do /usr/bin/sleep 15; lim=$(cur_maxpar); done
  else
    while [ $nrun -ge "$lim" ]; do wait -n; nrun=$((nrun-1)); lim=$(cur_maxpar); [ "$lim" -gt "$cap" ] && lim=$cap; done
  fi
  while [ "$(ourmem_gb)" -ge "$(cur_memguard)" ] || [ "$(sys_avail_gb)" -lt "$WC_SYS_MIN_AVAIL_GB" ]; do /usr/bin/sleep 30; done
  if [ "$(pids_room)" -lt "$HEADROOM" ]; then
    echo "$(/bin/date '+%F %T') pids: $(cat "$CG/pids.current") of $(cat "$CG/pids.max") tasks used, $nrun pairs running, $(n_ramping) ramping -- waiting" >> "$LOG"
    while [ "$(pids_room)" -lt "$HEADROOM" ]; do /usr/bin/sleep 15; done
  fi
  if [ "${WC_KRB_WAIT:-0}" = 1 ] && ! /usr/bin/klist -s 2>/dev/null; then
    echo "$(/bin/date '+%F %T') no valid Kerberos ticket -- waiting (kinit to resume)" >> "$LOG"
    until /usr/bin/klist -s 2>/dev/null; do /usr/bin/sleep 60; done
  fi
  rm -f "$WORK/$id/status"
  ( python3 "$BIN/run_pair.py" "$id" "$real" "$r1" "$caf" "$WORK" "$SCHEMA" > "$WORK/$id.run_pair.out" 2>&1
    echo "$(/bin/date '+%F %T') $id $(cat "$WORK/$id/status" 2>/dev/null || echo 'NO STATUS (run_pair.py did not run?)')" >> "$LOG" ) &
  nrun=$((nrun+1)); LAUNCH_TIMES+=("$(/bin/date +%s)")
  /usr/bin/sleep 2
done < "$PAIRS"
wait
echo "$(/bin/date '+%F %T') pool done: $(cat "$WORK"/*/status 2>/dev/null | grep -cx OK) OK, $(cat "$WORK"/*/status 2>/dev/null | grep -cx PARTIAL) PARTIAL, $(cat "$WORK"/*/status 2>/dev/null | grep -c '^EMPTY') EMPTY, $(cat "$WORK"/*/status 2>/dev/null | grep -c '^FAIL') FAIL" >> "$LOG"
python3 "$BIN/cost-summary.py" "$WORK" > "$WORK/cost-summary.md" 2>&1
echo "end     $(/bin/date '+%F %T %Z')" >> "$WORK/RUN-RECORD.txt"

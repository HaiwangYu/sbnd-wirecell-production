#!/bin/bash
# Load governor for a shared node (HOST side): sets the pools' budget from the other users' load.
#
#   load-governor.sh <control dir>        (stop: touch <control dir>/STOP)
#
# Every WC_GOV_PERIOD seconds (60) it measures the OTHER users' share of the machine:
#   CPU    = their summed %CPU in a `top` sample (WC_GOV_SAMPLE s) / (ncores * 100)
#   memory = their summed RSS / MemTotal
# and writes, for bin/run-pairs.sh (WC_CONTROL_DIR=<control dir>):
#   idle  (CPU < WC_GOV_IDLE_PCT and memory < WC_GOV_IDLE_PCT, default 20 %)  -> WC_GOV_HIGH_PCT (60 %)
#   busy  (otherwise)                                                          -> WC_GOV_LOW_PCT  (30 %)
# as maxpar.override = floor(ncores * pct) jobs (each job is one single-threaded process) and
# memguard.override = floor(MemTotal_GB * pct) GB of our own RSS.  Down at once; up only after
# WC_GOV_UP_AFTER (3) consecutive idle samples.  Running jobs are never killed: after a step down
# our load drains as jobs finish (a pair runs ~10-25 min).  One line per sample in governor.log.
# Headroom (the share rule alone let the machine run out of memory, 2026-10-16: another user grew
# to 70 GB while we stayed inside our 30 %): the job cap is also at most
#   running + (MemAvailable - growth - WC_GOV_MIN_AVAIL_GB) / WC_GOV_GB_PER_JOB
# where growth = running * WC_GOV_GB_PER_JOB - our lar/wire-cell RSS (what our running jobs have not
# reached yet: a freshly started job holds ~0.3 GB, then ~1.6 GB) (20 GB, 2 GB per job; never below
# the jobs already running, which are not killed), and an ALERT
# line is logged when MemAvailable < WC_GOV_ALERT_GB (10).
set -u
CTRL=${1:?control dir}
mkdir -p "$CTRL"
PERIOD=${WC_GOV_PERIOD:-60}; SAMPLE=${WC_GOV_SAMPLE:-10}
IDLE=${WC_GOV_IDLE_PCT:-20}; HIGH=${WC_GOV_HIGH_PCT:-60}; LOW=${WC_GOV_LOW_PCT:-30}; UPN=${WC_GOV_UP_AFTER:-3}
MINAV=${WC_GOV_MIN_AVAIL_GB:-20}; PERJOB=${WC_GOV_GB_PER_JOB:-2}; ALERT=${WC_GOV_ALERT_GB:-10}
NC=$(nproc)
MEMKB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
level=$LOW; idle_run=0
echo "$(/bin/date '+%F %T') start: ncores $NC, MemTotal $((MEMKB/1048576)) GB, idle < $IDLE %, high $HIGH %, low $LOW %, up after $UPN" >> "$CTRL/governor.log"
while [ ! -e "$CTRL/STOP" ]; do
  # second iteration of top = a true SAMPLE-second average
  read -r ocpu ucpu < <(top -b -n 2 -d "$SAMPLE" | awk -v me="$USER" '/^top -/{blk++} blk==2 && $1 ~ /^[0-9]+$/ {if ($2==me) u+=$9; else o+=$9} END{printf "%.0f %.0f\n", o, u}')
  read -r omem umem < <(ps -eo user=,rss= | awk -v me="$USER" '{if ($1==me) u+=$2; else o+=$2} END{printf "%.0f %.0f\n", o, u}')
  cpu_pct=$(( ocpu / NC ))                    # top %CPU is per core
  mem_pct=$(( omem * 100 / MEMKB ))
  if [ "$cpu_pct" -lt "$IDLE" ] && [ "$mem_pct" -lt "$IDLE" ]; then idle_run=$((idle_run+1)); else idle_run=0; fi
  if [ "$idle_run" -eq 0 ]; then level=$LOW; elif [ "$idle_run" -ge "$UPN" ]; then level=$HIGH; fi
  jobs=$(( NC * level / 100 )); memg=$(( MEMKB * level / 100 / 1048576 ))
  avail=$(awk '/MemAvailable/ {printf "%d", $2/1048576}' /proc/meminfo)
  nrun=$(ps -u "$USER" -o args= | grep -c '[b]in/run_pair\.py')
  jobrss=$(ps -u "$USER" -o rss=,comm= | awk '$2=="lar" || $2=="wire-cell" {s+=$1} END{printf "%d", s/1048576}')
  growth=$(( nrun * PERJOB - jobrss )); [ "$growth" -lt 0 ] && growth=0
  free_gb=$(( avail - growth - MINAV ))
  room=$(( free_gb > 0 ? free_gb / PERJOB : 0 ))
  hcap=$(( nrun + room )); note=""
  if [ "$hcap" -lt "$jobs" ]; then jobs=$hcap; note=" (headroom: ${avail} GB available, ${growth} GB still to grow)"; fi
  [ "$jobs" -lt 1 ] && jobs=1
  [ "$avail" -lt "$ALERT" ] && note="$note ALERT: only ${avail} GB available"
  echo "$jobs" > "$CTRL/maxpar.override.tmp" && mv "$CTRL/maxpar.override.tmp" "$CTRL/maxpar.override"
  echo "$memg" > "$CTRL/memguard.override.tmp" && mv "$CTRL/memguard.override.tmp" "$CTRL/memguard.override"
  echo "$(/bin/date '+%F %T') others cpu ${cpu_pct}% mem ${mem_pct}% | ours cpu $((ucpu / NC))% mem $((umem * 100 / MEMKB))% pairs $nrun | level ${level}% -> ${jobs} jobs, ${memg} GB${note}" >> "$CTRL/governor.log"
  /usr/bin/sleep "$PERIOD"
done
echo "$(/bin/date '+%F %T') stop (STOP file)" >> "$CTRL/governor.log"

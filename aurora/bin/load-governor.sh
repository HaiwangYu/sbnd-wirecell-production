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
set -u
CTRL=${1:?control dir}
mkdir -p "$CTRL"
PERIOD=${WC_GOV_PERIOD:-60}; SAMPLE=${WC_GOV_SAMPLE:-10}
IDLE=${WC_GOV_IDLE_PCT:-20}; HIGH=${WC_GOV_HIGH_PCT:-60}; LOW=${WC_GOV_LOW_PCT:-30}; UPN=${WC_GOV_UP_AFTER:-3}
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
  echo "$jobs" > "$CTRL/maxpar.override.tmp" && mv "$CTRL/maxpar.override.tmp" "$CTRL/maxpar.override"
  echo "$memg" > "$CTRL/memguard.override.tmp" && mv "$CTRL/memguard.override.tmp" "$CTRL/memguard.override"
  nrun=$(ps -u "$USER" -o args= | grep -c '[b]in/run_pair\.py')
  echo "$(/bin/date '+%F %T') others cpu ${cpu_pct}% mem ${mem_pct}% | ours cpu $((ucpu / NC))% mem $((umem * 100 / MEMKB))% pairs $nrun | level ${level}% -> ${jobs} jobs, ${memg} GB" >> "$CTRL/governor.log"
  /usr/bin/sleep "$PERIOD"
done
echo "$(/bin/date '+%F %T') stop (STOP file)" >> "$CTRL/governor.log"

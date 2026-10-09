#!/bin/bash
# One reco1 / flat-CAF pair through the three steps (HOST side; each step runs in the SL7 container).
#
#   run-pair.sh <id> <sim|data> <reco1.root> <flat.caf.root> <workdir> <schema.json>
#
# Needs the site config in the environment (bin/run-pairs.sh sources site/<site>.sh):
#   WC_WRAP (container wrapper), WC_SL7_SETUP (run setup sourced inside), WC_CPUSET (taskset list or "").
#
# Layout: <workdir>/<id>/
#   ql/         step 1: qlpctree.tar.gz, mabc.zip, nugraph.h5, lar.log.gz, frameshift.txt
#   pr/         step 2: pr_evt<E>/tracking-pr.root (+ recTreeWireCell), mabc-pr.zip, wct.log.gz, dl_fail
#   pr-try1/    a failed first step-2 attempt (the intermittent PR crash), kept for study
#   merged/     step 3: <caf name with .wc before .flat.caf.root / .caf.root>, merge.json
#   validate.json, cost.tsv (step, rc, wall_s, cpu_s, maxrss_MB, out_MB), status (OK|FAIL <step>)
set -u
ID=${1:?id}; REAL=${2:?reality}; R1=${3:?reco1}; CAF=${4:?caf}; WORK=${5:?workdir}; SCHEMA=${6:?schema}
BIN=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
D=$WORK/$ID; mkdir -p "$D/cost"
: "${WC_WRAP:?source a site config}"; : "${WC_SL7_SETUP:?}"
PIN=(); [ -n "${WC_CPUSET:-}" ] && PIN=(taskset -c "$WC_CPUSET")

# run <step> <cmd...>: inside the container, timed; returns the command's rc
run() {
  local step=$1; shift
  SL7_SETUP=$WC_SL7_SETUP "$WC_WRAP" /usr/bin/time -v -o "$D/cost/$step.time" ${PIN[@]+"${PIN[@]}"} "$@" \
    > "$D/cost/$step.out" 2>&1
  local rc=$?
  echo $rc > "$D/cost/$step.rc"
  return $rc
}

caf_name=$(basename "$CAF")
case $caf_name in
  *.flat.caf.root) out_name=${caf_name%.flat.caf.root}.wc.flat.caf.root ;;
  *.caf.root) out_name=${caf_name%.caf.root}.wc.caf.root ;;
  *) out_name=${caf_name%.root}.wc.root ;;
esac

status="OK"
if [ "$(cat "$D/cost/step1.rc" 2>/dev/null)" != 0 ]; then
  run step1 "$BIN/step1.sh" "$R1" "$D/ql" "$REAL" || status="FAIL step1"
fi
if [ "$status" = OK ] && [ "$(cat "$D/cost/step2.rc" 2>/dev/null)" != 0 ]; then
  if ! run step2 "$BIN/step2.sh" "$D/ql/qlpctree.tar.gz" "$D/pr" "$REAL"; then
    # one retry: the PR stage has an intermittent crash (ai-helper #38 log (b)); a crash also leaves
    # the previous event's tracking-pr.root as a stub, so the whole tar is rerun in a fresh dir
    rm -rf "${D:?}/pr-try1"; mv "$D/pr" "$D/pr-try1"
    mv "$D/cost/step2.time" "$D/cost/step2-try1.time" 2>/dev/null
    cp "$D/cost/step2.rc" "$D/cost/step2-try1.rc"
    run step2 "$BIN/step2.sh" "$D/ql/qlpctree.tar.gz" "$D/pr" "$REAL" || status="FAIL step2"
  fi
fi
if [ "$status" = OK ]; then
  ls "$D"/pr/pr_evt*/tracking-pr.root > "$D/pr/files.txt"
  mkdir -p "$D/merged"
  run step3 python3 "$BIN/merge-caf.py" --caf "$CAF" --out "$D/merged/$out_name" --schema "$SCHEMA" \
      --summary "$D/merged/merge.json" @"$D/pr/files.txt" || status="FAIL step3"
fi
if [ "$status" = OK ] && [ "${WC_VALIDATE:-1}" = 1 ]; then
  run validate python3 "$BIN/validate-merge.py" --merged "$D/merged/$out_name" --caf "$CAF" \
      --json "$D/validate.json" @"$D/pr/files.txt" || status="FAIL validate"
fi

# cost table
mb() { du -sbc "$@" 2>/dev/null | tail -1 | awk '{printf "%.2f", $1/1e6}'; }
{
  printf "step\trc\twall_s\tcpu_s\tmaxrss_MB\tout_MB\n"
  for s in step1 step2-try1 step2 step3 validate; do
    t=$D/cost/$s.time; [ -f "$t" ] || continue
    wall=$(awk -F': ' '/Elapsed/ {n=split($2,a,":"); print (n==3 ? a[1]*3600+a[2]*60+a[3] : a[1]*60+a[2])}' "$t")
    cpu=$(awk -F': ' '/User time/ {u=$2} /System time/ {s=$2} END {print u+s}' "$t")
    rss=$(awk -F': ' '/Maximum resident/ {printf "%.0f", $2/1024}' "$t")
    case $s in
      step1) out=$(mb "$D/ql") ;; step2) out=$(mb "$D/pr") ;; step2-try1) out=$(mb "$D/pr-try1") ;;
      step3) out=$(mb "$D/merged/$out_name") ;; *) out=0 ;;
    esac
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$s" "$(cat "$D/cost/$s.rc" 2>/dev/null)" "$wall" "$cpu" "$rss" "$out"
  done
} > "$D/cost.tsv"
echo "$status" > "$D/status"
[ "$status" = OK ]

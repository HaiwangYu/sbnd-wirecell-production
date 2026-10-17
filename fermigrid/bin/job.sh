#!/bin/bash
# FermiGrid job: process this job's slice of a pairs list with the r8 workflow (aurora/bin/run_pair.py)
# and copy the results to dCache.
#
#   job.sh <pairs.tsv name> <pairs per job> <sample> <output base>
#
# pairs.tsv (bin/find-pairs.py) arrives with jobsub -f (in $CONDOR_DIR_INPUT); the code tarball with
# --tar_file_name dropbox:// (unpacked in $INPUT_TAR_DIR_LOCAL).  Job $PROCESS takes lines
# [PROCESS*K, PROCESS*K+K) of the list.  For each pair:
#   1. ifdh cp the reco1 and the CAF to scratch;
#   2. run_pair.py, WC_KEEP=semiprod, WC_STAMP_INPUT_FILE=1 (the event's input_file and the merged
#      CAF's provenance name the ORIGINAL files, not the scratch copies);
#   3. copy to <output base>/<sample>/<id>/: <id>.qlpctree.tar.gz, <id>.tracking-pr.tar (every
#      pr_evt<E>/tracking-pr.root of the pair, paths kept), the merged CAF, <id>.logs.tar.gz
#      (status, run_pair.log, events.json, validate.json, merge.json, cost.tsv, every lar/wct log).
# Local emulation (fermigrid/bin/emulate-worker.sh): WC_GRID_EMULATE=1 copies with cp from a
# mounted /pnfs and writes the outputs under a local directory.
set -u
LIST=${1:?pairs list}; K=${2:?pairs per job}; SAMPLE=${3:?sample}; OUTBASE=${4:?output base}
P=${PROCESS:-0}
T0=$(date +%s)
echo "job.sh $(date '+%F %T') host $(hostname) PROCESS $P list $LIST K $K sample $SAMPLE out $OUTBASE"
export WC_TOP=${INPUT_TAR_DIR_LOCAL:?no INPUT_TAR_DIR_LOCAL}/wc
A=$WC_TOP/sbnd-wirecell-production/aurora
export WC_SL7_SETUP=$WC_TOP/sbnd-wirecell-production/aurora/env/fnal/setup-fnal-run.sh
export WC_WRAP=$WC_TOP/sbnd-wirecell-production/fermigrid/bin/grid-wrap.sh
export WC_CPUSET= WC_KEEP=semiprod WC_STAMP_INPUT_FILE=1
cat "$WC_TOP/TARBALL-PROVENANCE.txt"
# the UPS setup reads unset variables: no set -u while it runs
set +u; source "$WC_SL7_SETUP" > setup.log 2>&1; src_rc=$?; set -u
[ $src_rc = 0 ] && command -v wire-cell > /dev/null || { echo "setup failed (rc $src_rc)"; tail -20 setup.log; exit 3; }
echo "env: wire-cell $(command -v wire-cell) lar $(command -v lar) python3 $(command -v python3) ifdh $(command -v ifdh)"
listf=${CONDOR_DIR_INPUT:-.}/$(basename "$LIST"); [ -f "$listf" ] || listf=$LIST
S=${_CONDOR_SCRATCH_DIR:-$PWD}/wcjob; mkdir -p "$S"
fetch() {  # fetch <pnfs path> <local dir>
  if [ "${WC_GRID_EMULATE:-0}" = 1 ]; then cp "$1" "$2/"; else ifdh cp "$1" "$2/$(basename "$1")"; fi
}
put() {    # put <local file> <dest dir>
  if [ "${WC_GRID_EMULATE:-0}" = 1 ]; then mkdir -p "$2" && cp "$1" "$2/"; else ifdh cp "$1" "$2/$(basename "$1")"; fi
}
mkdest() { if [ "${WC_GRID_EMULATE:-0}" = 1 ]; then mkdir -p "$1"; else ifdh mkdir_p "$1"; fi; }
# a pair whose merged CAF and qlpctree are already at the destination is skipped, so a job that
# is restarted (e.g. auto-released after a memory hold) does not redo the pairs it finished
done_already() {
  local dest=$1 ls
  if [ "${WC_GRID_EMULATE:-0}" = 1 ]; then ls=$(ls "$dest" 2>/dev/null); else ls=$(ifdh ls "$dest" 0 2>/dev/null | xargs -n1 basename 2>/dev/null); fi
  echo "$ls" | grep -q 'flat.caf.root$\|\.caf\.root$' && echo "$ls" | grep -q 'qlpctree.*tar.gz$'
}
n=0; nok=0
grep -v '^#' "$listf" | sed -n "$((P*K+1)),$((P*K+K))p" > "$S/my-pairs.tsv"
echo "pairs in this job: $(wc -l < "$S/my-pairs.tsv")"
while IFS=$'\t' read -r id real r1 caf nev; do
  [ -z "$id" ] && continue
  n=$((n+1)); t=$(date +%s)
  echo "=== pair $n $id ($real, $nev events) $(date '+%F %T')"
  if done_already "$OUTBASE/$SAMPLE/$id"; then echo "  already at the destination, skipped"; nok=$((nok+1)); continue; fi
  in=$S/in; rm -rf "$in" "$S/work"; mkdir -p "$in"
  fetch "$r1" "$in" && fetch "$caf" "$in" || { echo "  FETCH FAILED"; continue; }
  WC_RECO1_ORIG=$r1 WC_CAF_ORIG=$caf python3 "$A/bin/run_pair.py" "$id" "$real" "$in/$(basename "$r1")" "$in/$(basename "$caf")" \
      "$S/work" "$A/schema/recTreeWireCell.schema.json" > "$S/run_pair.out" 2>&1
  d=$S/work/$id; st=$(cat "$d/status" 2>/dev/null || echo "NO STATUS")
  echo "  status: $st ($(( $(date +%s) - t )) s)"
  out=$S/out/$id; rm -rf "$out"; mkdir -p "$out"
  cp "$S/run_pair.out" "$d/" 2>/dev/null
  ( cd "$d" && tar -czf "$out/$id.logs.tar.gz" --ignore-failed-read status run_pair.log run_pair.out events.json validate.json \
        merged/merge.json cost.tsv cost $(ls -d ql/*/lar.log.gz ql/*/frameshift.txt pr/*/wct.log.gz pr/*/dl_fail fs/*.log.gz \
        attempts/*/*.log.gz attempts/*/*.txt 2>/dev/null) ) 2>/dev/null
  case "$st" in
    OK|PARTIAL)
      nok=$((nok+1))
      for q in "$d"/ql/*/qlpctree.tar.gz; do tag=$(basename "$(dirname "$q")"); cp "$q" "$out/$id.qlpctree$([ "$tag" = all ] || echo ".$tag").tar.gz"; done
      ( cd "$d" && tar -cf "$out/$id.tracking-pr.tar" pr/*/pr_evt*/tracking-pr.root )
      cp "$d"/merged/*.root "$out/"
      ;;
  esac
  dest=$OUTBASE/$SAMPLE/$id; mkdest "$dest"
  for f in "$out"/*; do put "$f" "$dest" || echo "  COPY FAILED $f"; done
  echo "  copied $(ls "$out" | wc -l) files ($(du -sm "$out" | cut -f1) MB) to $dest"
  rm -rf "$in" "$S/work" "$out"
done < "$S/my-pairs.tsv"
echo "job done $(date '+%F %T'): $nok/$n pairs OK or PARTIAL, $(( $(date +%s) - T0 )) s"
[ "$n" -gt 0 ] && [ "$nok" -eq "$n" ]

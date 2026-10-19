#!/bin/bash
# FermiGrid job: process this job's slice of a pairs list with the r8 workflow (aurora/bin/run_pair.py)
# and copy the results to dCache.
#
#   job.sh <pairs.tsv name> <pairs per job> <sample> <output base>
#
# pairs.tsv (bin/find-pairs.py) arrives with jobsub -f (in $CONDOR_DIR_INPUT); the code tarball with
# --tar_file_name dropbox:// (unpacked in $INPUT_TAR_DIR_LOCAL).  Job $PROCESS takes lines
# [PROCESS*K, PROCESS*K+K) of the list.  For each pair:
#   0. list <output base>/<sample>/<id>/; a FINISHED pair (<id>.done there) is skipped; if the
#      listing fails the pair is skipped too, nothing is run or written;
#   1. ifdh cp the reco1 and the CAF to scratch, each checked against the source's size (3 tries);
#   2. run_pair.py, WC_KEEP=semiprod, WC_STAMP_INPUT_FILE=1 (the event's input_file and the merged
#      CAF's provenance name the ORIGINAL files, not the scratch copies);
#   3. copy to <output base>/<sample>/<id>/, each file checked against the local size (3 tries):
#      <id>.qlpctree.tar.gz, <id>.tracking-pr.tar (every pr_evt<E>/tracking-pr.root of the pair,
#      paths kept), the merged CAF, then <id>.logs.tar.gz (status, run_pair.log, events.json,
#      validate.json, merge.json, cost.tsv, every lar/wct log), and LAST <id>.done (status, job,
#      the files and their sizes) for an OK, PARTIAL or EMPTY pair whose files all arrived.
#      Nothing at the destination is overwritten: the logs of a later try of the pair go to
#      <id>.logs.try<k>.tar.gz; a data file of an unfinished pair (an interrupted copy) is kept if
#      its size matches, else replaced.
# Local emulation (fermigrid/bin/emulate-worker.sh): WC_GRID_EMULATE=1 copies with cp from a
# mounted /pnfs and writes the outputs under a local directory.
set -u
LIST=${1:?pairs list}; K=${2:?pairs per job}; SAMPLE=${3:?sample}; OUTBASE=${4:?output base}
# the job's index: $PROCESS in a plain cluster; with --maxConcurrent jobsub_lite submits a DAG whose
# nodes are separate clusters, all with PROCESS=0, and the index is $JOBSUBJOBSECTION (0-based)
if [ -n "${DAGMANJOBID:-}" ] && [ -n "${JOBSUBJOBSECTION:-}" ]; then P=$JOBSUBJOBSECTION; else P=${PROCESS:-0}; fi
T0=$(date +%s)
echo "job.sh $(date '+%F %T') host $(hostname) index $P (PROCESS ${PROCESS:-} JOBSUBJOBSECTION ${JOBSUBJOBSECTION:-} DAG ${DAGMANJOBID:-}) list $LIST K $K sample $SAMPLE out $OUTBASE"
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
EMU=${WC_GRID_EMULATE:-0}; NAP=${WC_GRID_RETRY_SLEEP:-60}
# ---- storage: ifdh on the grid; cp / stat on a mounted /pnfs and a local output dir in emulation.
# ifdh cp never overwrites a dCache file (gfal: "exists and overwrite is not set") and creates the
# parent directories; `ifdh ls <dir> 0` lists only <dir> itself, `ifdh ll <dir> 1` its files.
size_of() {    # size_of <remote file>: bytes, or nothing
  if [ "$EMU" = 1 ]; then stat -c %s "$1" 2>/dev/null; else ifdh ll "$1" 0 2>/dev/null | awk '$1 ~ /^-/ && NF >= 9 {print $5; exit}'; fi
}
rm_remote() { if [ "$EMU" = 1 ]; then rm -f "$1"; else ifdh rm "$1" > /dev/null 2>&1; fi; }
dest_ls() {    # dest_ls <dir>: "<size> <name>" per file; an absent (or empty) dir lists nothing; 1 = the listing failed
  local out rc k
  if [ "$EMU" = 1 ]; then [ -d "$1" ] && (cd "$1" && stat -c '%s %n' -- * 2>/dev/null); return 0; fi
  for k in 1 2 3; do
    out=$(ifdh ll "$1" 1 2> "$S/ifdh-ll.err"); rc=$?
    if [ $rc = 0 ]; then echo "$out" | awk '$1 ~ /^-/ && NF >= 9 {n = $NF; sub(/.*\//, "", n); print $5, n}'; return 0; fi
    # dCache's https door answers 404 for an absent and for an empty directory alike
    grep -q 'No such file or directory' "$S/ifdh-ll.err" && return 0
    sleep $((NAP / 2 * k))
  done
  sed 's/^/    ifdh: /' "$S/ifdh-ll.err" | tail -3 >&2; return 1
}
fetch() {      # fetch <pnfs file> <local dir>: copy, the copy's size must equal the source's
  local src=$1 dst=$2/$(basename "$1") want= got= k
  for k in 1 2 3; do
    rm -f "$dst"; want=$(size_of "$src"); got=
    if [ -n "$want" ]; then
      if [ "$EMU" = 1 ]; then cp "$src" "$dst"; else ifdh cp "$src" "$dst"; fi
      got=$(stat -c %s "$dst" 2>/dev/null)
      [ "$got" = "$want" ] && return 0
    fi
    echo "  fetch try $k of $(basename "$src"): source ${want:-?} bytes, copy ${got:-none}"
    sleep $((NAP * k))
  done
  rm -f "$dst"; return 1
}
put() {        # put <local file> <dest dir> <name>: copy, the size at the destination must equal the local one
  local want got= k
  want=$(stat -c %s "$1")
  for k in 1 2 3; do
    if [ "$EMU" = 1 ]; then mkdir -p "$2" && cp "$1" "$2/$3"; else ifdh cp "$1" "$2/$3"; fi
    got=$(size_of "$2/$3")
    [ "$got" = "$want" ] && return 0
    echo "  put try $k of $3: local $want bytes, destination ${got:-none}"
    # ours: the name was free (or held a leftover of an unfinished pair) before this put
    [ -n "$got" ] && rm_remote "$2/$3"
    sleep $((NAP * k))
  done
  return 1
}
# a pair is FINISHED when <id>.done is at the destination; outputs of fg1 (before the marker)
# count as finished when the merged CAF, the qlpctree, the tracking-pr tar and the logs are there
has() { echo "$names" | grep -qxF "$1"; }
finished() {   # finished <id>, with $names = the destination's file names
  has "$1.done" && return 0
  echo "$names" | grep -q '\.caf\.root$' && echo "$names" | grep -F "$1.qlpctree" | grep -q '\.tar\.gz$' \
    && has "$1.tracking-pr.tar" && has "$1.logs.tar.gz"
}
n=0; nok=0; nempty=0; nskip=0
grep -v '^#' "$listf" | sed -n "$((P*K+1)),$((P*K+K))p" > "$S/my-pairs.tsv"
echo "pairs in this job: $(wc -l < "$S/my-pairs.tsv")"
while IFS=$'\t' read -r id real r1 caf nev; do
  [ -z "$id" ] && continue
  n=$((n+1)); t=$(date +%s)
  echo "=== pair $n $id ($real, $nev events) $(date '+%F %T')"
  dest=$OUTBASE/$SAMPLE/$id
  if ! listing=$(dest_ls "$dest"); then echo "  DESTINATION LISTING FAILED: not run, nothing written"; continue; fi
  names=$(echo "$listing" | awk 'NF {print $2}')
  if finished "$id"; then echo "  finished at the destination ($(echo "$names" | grep -c .) files), skipped"; nok=$((nok+1)); nskip=$((nskip+1)); continue; fi
  [ -n "$names" ] && echo "  unfinished at the destination: $(echo $names)"
  in=$S/in; rm -rf "$in" "$S/work"; mkdir -p "$in"
  fetch "$r1" "$in" && fetch "$caf" "$in" || { echo "  FETCH FAILED"; rm -rf "$in"; continue; }
  WC_RECO1_ORIG=$r1 WC_CAF_ORIG=$caf python3 "$A/bin/run_pair.py" "$id" "$real" "$in/$(basename "$r1")" "$in/$(basename "$caf")" \
      "$S/work" "$A/schema/recTreeWireCell.schema.json" > "$S/run_pair.out" 2>&1
  d=$S/work/$id; st=$(cat "$d/status" 2>/dev/null || echo "NO STATUS")
  echo "  status: $st ($(( $(date +%s) - t )) s)"
  case "$st" in EMPTY*) [[ $nev =~ ^[1-9] ]] && echo "  note: the list says $nev events (SAM event_count); the copy has the source's size" ;; esac
  out=$S/out/$id; rm -rf "$out"; mkdir -p "$out"
  cp "$S/run_pair.out" "$d/" 2>/dev/null
  logs=$S/out/$id.logs.tar.gz
  ( cd "$d" && tar -czf "$logs" --ignore-failed-read status run_pair.log run_pair.out events.json validate.json \
        merged/merge.json cost.tsv cost $(ls -d ql/*/lar.log.gz ql/*/frameshift.txt pr/*/wct.log.gz pr/*/dl_fail fs/*.log.gz \
        attempts/*/*.log.gz attempts/*/*.txt 2>/dev/null) ) 2>/dev/null
  good=0
  case "$st" in
    OK*|PARTIAL*)
      good=1
      for q in "$d"/ql/*/qlpctree.tar.gz; do tag=$(basename "$(dirname "$q")"); cp "$q" "$out/$id.qlpctree$([ "$tag" = all ] || echo ".$tag").tar.gz"; done
      ( cd "$d" && tar -cf "$out/$id.tracking-pr.tar" pr/*/pr_evt*/tracking-pr.root )
      cp "$d"/merged/*.root "$out/"
      ;;
    EMPTY*) good=1 ;;
  esac
  # the destination again, just before writing (hours later): never overwrite a finished pair
  if ! listing=$(dest_ls "$dest"); then echo "  DESTINATION LISTING FAILED: nothing written"; rm -rf "$in" "$S/work" "$out" "$logs"; continue; fi
  names=$(echo "$listing" | awk 'NF {print $2}')
  copied=0; failed=0
  if finished "$id"; then
    echo "  finished at the destination meanwhile: only the logs are written"; rm -rf "$out"; mkdir -p "$out"; good=0
  fi
  for f in "$out"/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f"); have=$(echo "$listing" | awk -v b="$b" '$2 == b {print $1}')
    if [ -n "$have" ]; then
      [ "$have" = "$(stat -c %s "$f")" ] && { echo "  $b: already there, same size"; continue; }
      echo "  $b: replacing a leftover of an unfinished try ($have bytes)"; rm_remote "$dest/$b"
    fi
    if put "$f" "$dest" "$b"; then copied=$((copied+1)); else echo "  COPY FAILED $b"; failed=1; fi
  done
  # the logs: never over an earlier try's
  lname=$id.logs.tar.gz; k=2
  while has "$lname"; do lname=$id.logs.try$k.tar.gz; k=$((k+1)); done
  if put "$logs" "$dest" "$lname"; then copied=$((copied+1)); else echo "  COPY FAILED $lname"; failed=1; fi
  if [ $good = 1 ] && [ $failed = 0 ]; then
    { echo "status	$st"; echo "job	${CLUSTER:-}.${PROCESS:-} ${JOBSUBJOBID:-} index $P host $(hostname) $(date '+%F %T')"
      [ "$lname" = "$id.logs.tar.gz" ] || echo "logs	$lname"
      (cd "$out" && stat -c 'file	%s	%n' -- * 2>/dev/null); } > "$S/out/$id.done"
    if put "$S/out/$id.done" "$dest" "$id.done"; then
      nok=$((nok+1)); case "$st" in EMPTY*) nempty=$((nempty+1)) ;; esac
    else echo "  COPY FAILED $id.done"; fi
  fi
  echo "  copied $copied files ($(du -smc "$out" "$logs" | tail -1 | cut -f1) MB) to $dest$([ $failed = 1 ] && echo ', WITH FAILURES')"
  rm -rf "$in" "$S/work" "$out" "$logs" "$S/out/$id.done"
done < "$S/my-pairs.tsv"
echo "job done $(date '+%F %T'): $nok/$n pairs finished ($nskip already at the destination, $nempty EMPTY), $(( $(date +%s) - T0 )) s"
[ "$n" -gt 0 ] && [ "$nok" -eq "$n" ]

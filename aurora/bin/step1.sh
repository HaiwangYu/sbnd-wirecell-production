#!/bin/bash
# STEP 1 (inside SL7, with the run setup sourced): reco1 artROOT -> qlpctree.tar.gz
#   step1.sh <reco1.root[,reco1.root...]> <outdir> <sim|data> [nskip] [nevents|all]
# Several reco1 files (comma-separated, a multi-reco1 unit: one flat CAF made from several
# reco1) are one lar job with one -s per file, in that order: art reads them as one event
# sequence, and nskip / nevents index that sequence.  A file with no events is fine.
# imaging + clustering + charge-light matching + all-APA clustering (+ MC truth tables) via our
# larwirecell job wcls-img-clus-matching{,-data}.fcl; the art input file name rides in the set
# metadata ("input_file", larwirecell sbnd-wc-flatcaf).  DATA must carry the FrameShift product
# (run run_frameshift.fcl first) -- the reader does not fail without it, it uses 0 (see AGENTS.md).
set -u
R1=${1:?reco1[,reco1...]}; OUT=${2:?outdir}; REAL=${3:?sim|data}; K=${4:-0}; N=${5:-all}
case $REAL in
  sim) FCL=wcls-img-clus-matching.fcl ;;
  data) FCL=wcls-img-clus-matching-data.fcl ;;
  *) echo "step1.sh: reality must be sim or data" >&2; exit 2 ;;
esac
mkdir -p "$OUT" && cd "$OUT" || exit 2
NARG=(); [ "$N" = all ] || NARG=(-n "$N")
IFS=',' read -r -a R1S <<< "$R1"
SRC=(); for f in "${R1S[@]}"; do SRC+=(-s "$f"); done
lar ${NARG[@]+"${NARG[@]}"} --nskip "$K" -c "$FCL" "${SRC[@]}" --no-output > lar.log 2>&1
rc=$?
grep -oE "frame_apply_at_caf [0-9.-]+ ns" lar.log | sort | uniq -c > frameshift.txt
[ $rc -eq 0 ] && [ ! -s qlpctree.tar.gz ] && { echo "step1.sh: lar rc 0 but no qlpctree.tar.gz" >&2; rc=95; }
if [ "$REAL" = data ] && [ $rc -eq 0 ] && ! grep -qvE "frame_apply_at_caf 0 ns" frameshift.txt; then
  echo "step1.sh: WARNING data with frame_apply_at_caf 0 everywhere -- no FrameShift product?" >&2
fi
gzip -f lar.log
exit $rc

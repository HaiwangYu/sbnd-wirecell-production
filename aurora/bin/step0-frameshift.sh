#!/bin/bash
# STEP 0, DATA only (inside SL7, with the run setup sourced): reco1 artROOT -> a local copy with
# the FrameShift product, which step 1 needs for the charge-light matching on Gen2 data.
#   step0-frameshift.sh <reco1.root> <out.root> [fcl]
# sbndcode's run_frameshift.fcl (default) copies every event and adds FrameShift.  Without it the
# step-1 reader does NOT fail, it silently uses a shift of 0 (AGENTS.md).  Exit 96 if the product
# did not land.  The copy is an intermediate: run_pair.py deletes it under WC_KEEP=minimal.
set -u
R1=${1:?reco1}; OUT=${2:?out.root}; FCL=${3:-run_frameshift.fcl}
mkdir -p "$(dirname "$OUT")" && cd "$(dirname "$OUT")" || exit 2
rm -f "$OUT" "$OUT.tmp"
lar -c "$FCL" -s "$R1" -o "$OUT.tmp" > frameshift-lar.log 2>&1
rc=$?
if [ $rc -eq 0 ]; then
  python3 - "$OUT.tmp" "$R1" <<'PY' || rc=96
import sys
import ROOT
ROOT.gErrorIgnoreLevel = ROOT.kError
out, inp = (ROOT.TFile.Open(p) for p in sys.argv[1:3])
t, ti = out.Get('Events'), inp.Get('Events')
fs = [b.GetName() for b in t.GetListOfBranches() if 'FrameShift' in b.GetName()]
print('step0-frameshift: events %d (input %d), FrameShift branches %s' % (t.GetEntries(), ti.GetEntries(), fs))
sys.exit(0 if fs and t.GetEntries() == ti.GetEntries() else 1)
PY
  [ $rc -eq 0 ] && mv "$OUT.tmp" "$OUT"
fi
[ $rc -eq 0 ] || { echo "step0-frameshift.sh: rc $rc (96 = no FrameShift product or event count changed)" >&2; rm -f "$OUT.tmp"; }
gzip -f frameshift-lar.log
exit $rc

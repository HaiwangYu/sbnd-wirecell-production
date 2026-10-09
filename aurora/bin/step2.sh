#!/bin/bash
# STEP 2 (inside SL7, with the run setup sourced): qlpctree.tar.gz -> pr_evt<E>/tracking-pr.root
#   step2.sh <qlpctree.tar.gz> <outdir> <sim|data>
# Standalone PR (wct-pr.jsonnet) with flat_tree=true: every tracking-pr.root also gets
# recTreeWireCell (all its trees as ONE flat CAF-style entry) for step 3; DL-vertex dump on
# unless DLVTX_DUMP=false.
set -u
TAR=${1:?tar}; OUT=${2:?outdir}; REAL=${3:?sim|data}; DUMP=${DLVTX_DUMP:-true}
mkdir -p "$OUT" && cd "$OUT" || exit 2
# Without these the DL vertex fails SILENTLY (WARN + traditional vertex, rc 0) -- refuse to run.
python3 -c "import importlib.util as u, sys; sys.exit(0 if all(u.find_spec(m) for m in ('SCN_Vertex', 'torch', 'sparseconvnet')) else 1)" \
  || { echo "step2.sh: SCN_Vertex/torch/sparseconvnet not importable (DL environment missing)" >&2; exit 97; }
wire-cell -l stdout -L debug -c pgrapher/experiment/sbnd/wct-pr.jsonnet \
  --tla-str input="$TAR" --tla-str reality="$REAL" \
  --tla-code dl_vtx_dump="$DUMP" --tla-code flat_tree=true > wct.log 2>&1
rc=$?
grep -c "DL vertex failed" wct.log > dl_fail
grep -c "RootFlatTreeVisitor.*no recTreeWireCell written" wct.log > flat_fail
gzip -f wct.log
if [ $rc -eq 0 ]; then
  [ "$(cat dl_fail)" = 0 ] || { echo "step2.sh: DL vertex failed $(cat dl_fail) times" >&2; rc=94; }
  [ "$(cat flat_fail)" = 0 ] || { echo "step2.sh: recTreeWireCell not written for some event" >&2; rc=93; }
  ls pr_evt*/tracking-pr.root > /dev/null 2>&1 || { echo "step2.sh: no tracking-pr.root" >&2; rc=92; }
fi
exit $rc

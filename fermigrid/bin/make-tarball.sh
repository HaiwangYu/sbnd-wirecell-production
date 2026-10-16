#!/bin/bash
# Build the code tarball for FermiGrid jobs: the LOCAL builds and configuration exactly as the
# local productions use them (r8, ai-helper #42), relocated under one directory.
#
#   make-tarball.sh <out.tar.gz>
#
# Inside the tarball everything sits at its path relative to /exp/sbnd/app/users/yuhw (Y), under
# the top directory wc/; the setup scripts are copied with Y replaced by ${WC_TOP}, which the job
# sets to <unpack dir>/wc.  So WIRECELL_PATH, LD_LIBRARY_PATH, FHICL_FILE_PATH, CET_PLUGIN_PATH,
# PYTHONPATH have the same entries in the same order as a local job (env/fnal/setup-fnal-run.sh),
# with Y -> ${WC_TOP}.  The UPS stack (sbndcode v10_14_02_03 e26:prof, scn, ...) comes from CVMFS.
#
# What is shipped is what a traced local pair opened (an MC and a data pair, strace, see
# fermigrid/README.md), plus whole small directories:
#   opt/bin/wire-cell, opt/lib/libWireCell*.so libWCP*.so *.rootmap *.pcm   (debug info stripped)
#   opt/larwirecell/v10_01_28/{fcl, slf7.x86_64.e26.prof/lib/*.so}         (debug info stripped)
#   opt/python, opt/share/wirecell, opt/ups-patches
#   wire-cell-toolkit/cfg (all), sbndcode/sbndcode/WireCell/cfg (all)
#   wire-cell-data: sbnd/, sbnd*.json*, the BDT/XGBoost weights and the SCN vertex model in use
#   wcp-porting-img/sbnd: the top-level *.fcl, *.jsonnet and the setup scripts; standalone-sample
#     exists only as an (empty) WIRECELL_PATH entry
#   sbnd-wirecell-production: aurora/{bin,lib,schema,env,site}, fermigrid/
# Stripping removes symbols only (strip --strip-debug): the code is the code that runs locally.
set -euo pipefail
OUT=${1:?out.tar.gz}
Y=/exp/sbnd/app/users/yuhw
ST=$(mktemp -d "${TMPDIR:-/tmp}/wcgrid.XXXXXX"); trap 'rm -rf "$ST"' EXIT
W=$ST/wc
cp_rel() {  # cp_rel <path relative to Y> ...
  for r in "$@"; do mkdir -p "$W/$(dirname "$r")"; cp -a "$Y/$r" "$W/$r"; done
}
cd "$Y"
# --- builds
cp_rel opt/bin/wire-cell
for f in opt/lib/libWireCell*.so opt/lib/libWCP*.so opt/lib/*.rootmap opt/lib/*.pcm; do cp_rel "$f"; done
cp_rel opt/larwirecell/v10_01_28/fcl
for f in opt/larwirecell/v10_01_28/slf7.x86_64.e26.prof/lib/*.so; do cp_rel "$f"; done
cp_rel opt/python opt/share/wirecell opt/ups-patches
find "$W/opt" -type f \( -name '*.so' -o -path '*/bin/wire-cell' \) -exec strip --strip-debug {} +
find "$W/opt/python" -name __pycache__ -prune -exec rm -rf {} +
# --- configuration and data
cp_rel wire-cell-toolkit/cfg sbndcode/sbndcode/WireCell/cfg wire-cell-data/sbnd
for f in wire-cell-data/sbnd*.json* ; do cp_rel "$f"; done
cp_rel wire-cell-data/uboone/scn_vtx/t48k-m16-l5-lr5d-res0.5-CP24.pth
for f in XGB_nue_seed2_0923.xml numu_scalars_scores_0923.xml numu_tagger1.weights.xml numu_tagger2.weights.xml \
         numu_tagger3.weights.xml cos_tagger_10.weights.xml br3_3_BDT.weights.xml br3_5_BDT.weights.xml \
         br3_6_BDT.weights.xml lol_1_BDT.weights.xml lol_2_BDT.weights.xml pio_2_BDT.weights.xml \
         sig_1_BDT.weights.xml sig_2_BDT.weights.xml stw_2_BDT.weights.xml stw_3_BDT.weights.xml \
         stw_4_BDT.weights.xml tro_1_BDT.weights.xml tro_2_BDT.weights.xml tro_4_BDT.weights.xml \
         tro_5_BDT.weights.xml; do cp_rel "wire-cell-data/uboone/weights/$f"; done
for f in wcp-porting-img/sbnd/*.fcl wcp-porting-img/sbnd/*.jsonnet; do cp_rel "$f"; done
mkdir -p "$W/wcp-porting-img/sbnd/standalone-sample"
# --- workflow
for d in bin lib schema env site; do cp_rel "sbnd-wirecell-production/aurora/$d"; done
cp_rel sbnd-wirecell-production/fermigrid
find "$W/sbnd-wirecell-production" -name __pycache__ -prune -exec rm -rf {} +
# --- relocated setup scripts: Y -> ${WC_TOP}
for s in wcp-porting-img/sbnd/setup-local-opt.sh wcp-porting-img/sbnd/setup-ap.sh wcp-porting-img/sbnd/setup-dlvtx.sh \
         sbnd-wirecell-production/aurora/env/fnal/setup-fnal-run.sh; do
  mkdir -p "$W/$(dirname "$s")"
  sed "s#$Y#\${WC_TOP}#g" "$Y/$s" > "$W/$s"
done
# provenance of this tarball
{
  echo "built $(date '+%F %T %Z') on $(hostname) by $USER"
  echo "wire-cell-toolkit $(git -C $Y/wire-cell-toolkit rev-parse --short HEAD) $(git -C $Y/wire-cell-toolkit status --short cfg | wc -l) dirty cfg files"
  echo "larwirecell $(git -C $Y/larsoft-wct036/v10_14_02/srcs/larwirecell rev-parse --short HEAD) $(git -C $Y/larsoft-wct036/v10_14_02/srcs/larwirecell status --short larwirecell | wc -l) dirty files"
  echo "wcp-porting-img $(git -C $Y/wcp-porting-img rev-parse --short HEAD)"
  echo "sbnd-wirecell-production $(git -C $Y/sbnd-wirecell-production rev-parse --short HEAD) $(git -C $Y/sbnd-wirecell-production status --short | wc -l) dirty files"
  echo "wire-cell-data $(git -C $Y/wire-cell-data rev-parse --short HEAD 2>/dev/null || echo '?')"
  echo "opt/lib/libWireCellClus.so md5 (unstripped) $(md5sum < $Y/opt/lib/libWireCellClus.so | cut -c1-12)"
} > "$W/TARBALL-PROVENANCE.txt"
tar -C "$ST" -czf "$OUT" wc
echo "$OUT: $(du -h "$OUT" | cut -f1), $(tar -tzf "$OUT" | wc -l) entries"
cat "$W/TARBALL-PROVENANCE.txt"

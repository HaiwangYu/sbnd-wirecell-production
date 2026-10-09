# Aurora port of setup-polaris-opt.sh (Recipe A'): local WCT + larwirecell install
# under $OPT on top of sbndcode v10_14_02_03 from twester's Flare UPS tree, with
# our $Y/products overlay (spdlog v1_14_1, fmt v11_0_2, scn).  Source INSIDE the
# SL7 container (in-aurora-sl7.sh does that for you).
#
# Layout (Flare):
#   $Y/products         = our UPS overlay (spdlog, fmt, scn) -- first in $PRODUCTS
#   $UPS_TREE           = twester's tree (173 products incl. sbndcode v10_14_02_03)
#   $OPT                = WCT install (lib/, include/, share/wirecell/, bin/, python/)
#   $OPT/larwirecell/$LWC_VER/slf7.x86_64.e26.prof/lib = hand-copied larwirecell .so
#   $WCT_SRC            = wire-cell-toolkit checkout (its cfg/ is prepended in setup-aurora-ap.sh)
#   $WCD                = wire-cell-data checkout
#   $Y/tools/bin        = patchelf (static binary; the UPS product is not on scisoft)
Y=${Y:-/lus/flare/projects/neutrinoGPU/yuhw}
export Y
export UPS_TREE=/lus/flare/projects/neutrinoGPU/scisoft/larsoft
export OPT=$Y/opt
export WCT_SRC=$Y/wire-cell-toolkit
export WCD=$Y/wire-cell-data
export WCP_SBND=$Y/wcp-porting-validation/sbnd
export LWC_VER=${LWC_VER:-v10_01_28}

source $UPS_TREE/setup >/dev/null 2>&1
export PRODUCTS=$Y/products:$PRODUCTS
# sbndcode v10_14_02_03 -> larsoft v10_14_02_02, the pairing of the FNAL MRB area.
setup sbndcode v10_14_02_03 -q e26:prof
setup cetmodules v3_24_00
setup cmake v3_27_4
setup gdb v13_1 2>/dev/null
# setup_sbnd.sh exports this at FNAL; the bare tree setup does not, and `mrb newDev`
# refuses without it ("MRB_PROJECT is not defined", build run 5, 2026-09-16).
export MRB_PROJECT=larsoft

path-remove ()  { local IFS=':'; local NEWPATH; local DIR; local PATHVARIABLE=${2:-PATH}
  for DIR in ${!PATHVARIABLE}; do [ "$DIR" != "$1" ] && NEWPATH=${NEWPATH:+$NEWPATH:}$DIR; done
  export $PATHVARIABLE="$NEWPATH"; }
path-prepend () { path-remove "$1" "$2"; local PATHVARIABLE="${2:-PATH}"
  export $PATHVARIABLE="$1${!PATHVARIABLE:+:${!PATHVARIABLE}}"; }
path-append ()  { path-remove "$1" "$2"; local PATHVARIABLE="${2:-PATH}"
  export $PATHVARIABLE="${!PATHVARIABLE:+${!PATHVARIABLE}:}$1"; }

# Drop the tree's larwirecell/wirecell that sbndcode pulled in so their plugins
# and cfg cannot shadow ours.  -j = this product ONLY: a plain `unsetup wirecell`
# also unsetups everything wirecell depends on (root, python, boost, eigen, tbb,
# hdf5, ...) and left the chain at 56 products with no ROOTSYS and the system
# python 3.6 (build runs 2-4, 2026-09-16).
unsetup -j larwirecell 2>/dev/null
unsetup -j wirecell 2>/dev/null
# The ambient spdlog is v1_9_2 (bundled fmt).  WCT is built against spdlog
# v1_14_1 + external fmt v11_0_2 (our overlay); larwirecell must see the same pair.
unsetup -j spdlog 2>/dev/null
setup spdlog v1_14_1 -q e26:prof
setup fmt v11_0_2 -q e26:prof 2>/dev/null

LWC_FQ="$OPT/larwirecell/$LWC_VER/slf7.x86_64.e26.prof"
export LARWIRECELL_DIR="$OPT/larwirecell/$LWC_VER"
export LARWIRECELL_VERSION=$LWC_VER
export LARWIRECELL_FQ_DIR="$LWC_FQ"
export LARWIRECELL_INC="$OPT/larwirecell/$LWC_VER/include"
export LARWIRECELL_LIB="$LWC_FQ/lib"
export LARWIRECELL_FCL="$OPT/larwirecell/$LWC_VER/fcl"
export WIRECELL_FQ_DIR=$OPT
export WIRECELL_DIR=$OPT
export WIRECELL_INC=$OPT/include
export WIRECELL_LIB=$OPT/lib

path-prepend "$LWC_FQ/lib"        CET_PLUGIN_PATH
path-prepend "$LWC_FQ/lib"        LD_LIBRARY_PATH
path-prepend "$LARWIRECELL_FCL"   FHICL_FILE_PATH
path-prepend "$OPT"               CMAKE_PREFIX_PATH
path-prepend "$OPT/lib"           LD_LIBRARY_PATH
path-prepend "$OPT/bin"           PATH
path-prepend "$Y/tools/bin"       PATH
path-prepend "$OPT/lib/python3.9/site-packages" PYTHONPATH 2>/dev/null

# WIRECELL_PATH layering as at FNAL: sbndcode cfg wins over opt/share/wirecell,
# wire-cell-data at the back.  setup-aurora-ap.sh re-layers for the AP chain.
path-prepend "$WCD"                                  WIRECELL_PATH
path-prepend "$OPT/share/wirecell"                   WIRECELL_PATH
path-prepend "$SBNDCODE_DIR/wire-cell-cfg"           WIRECELL_PATH
path-prepend . FHICL_FILE_PATH
path-prepend "$WCP_SBND" FHICL_FILE_PATH
export CXXFLAGS="-DSPDLOG_FMT_EXTERNAL"

# waf's preforked subprocess pool breaks inside the container (Polaris 2026-09-15).
export WAF_NO_PREFORK=1

# Shell functions must survive a child `bash -c` ("setup: command not found").
for f in setup unsetup path-prepend path-append path-remove; do
    declare -F "$f" >/dev/null 2>&1 && export -f "$f"
done

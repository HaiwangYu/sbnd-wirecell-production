# ai-helper #48: run setup for WCLocal2026Nov16-Aurora (sourced inside SL7; site/aurora.sh: WC_SL7_SETUP=<this file>).
# = the production run setup with WCT 0.38.0 ($Y/opt-0.38.0, worktree $Y/wct-0.38.0 at c935e30d),
#   wire-cell-data 99c6497f (worktree $Y/wcd-0.38.0, has dv2max/sbnd/aurora_space) in place of $Y/wire-cell-data,
#   scipy + lightgbm 4.6.0 (SL7 build), GODEBUG=asyncpreemptoff=1 (ai-helper #45).
Y=/lus/flare/projects/neutrinoGPU/yuhw
export WC_OPT=${WC_OPT:-$Y/opt-0.38.0} WC_WCT_SRC=${WC_WCT_SRC:-$Y/wct-0.38.0}
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-aurora-run.sh"
export WCD=$Y/wcd-0.38.0
export WIRECELL_PATH=$(echo "$WIRECELL_PATH" | sed "s#$Y/wire-cell-data\(/\|:\|\$\)#$WCD\1#g")
export PYTHONPATH=$PYTHONPATH:$Y/products/dv2-extra-py39/site
export DV2_THREADS=1 DV2_STRICT=1 GODEBUG=asyncpreemptoff=1

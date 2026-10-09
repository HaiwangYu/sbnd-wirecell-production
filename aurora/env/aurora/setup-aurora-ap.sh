# Aurora port of setup-polaris-ap.sh: env for the 1-step img-clus-match-pr chain
# (wcls-img-clus-matching-pr-flash.fcl).  Source INSIDE SL7.
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/setup-aurora-opt.sh"

# The AP chain uses the TOOLKIT cfg, not sbndcode's fork: prepend the toolkit
# SOURCE cfg so it wins.  A `git checkout` in $WCT_SRC therefore changes what
# every job runs -- gate 0 of the procedure doc.
path-prepend "$WCT_SRC/cfg"          WIRECELL_PATH
# QLMatching reads semi-analytical-sbnd.json by bare name from wire-cell-data.
path-prepend "$WCD/sbnd/photodet"    WIRECELL_PATH
# Xin's standalone chain helpers + our sbnd/ jsonnet (pr-operating-point.jsonnet etc.).
path-prepend "$WCP_SBND/sbnd_xin"    WIRECELL_PATH
path-prepend "$WCP_SBND"             WIRECELL_PATH

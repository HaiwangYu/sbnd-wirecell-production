# Site config: ALCF Aurora compute node (inside a PBS job; the node is ours).  Sourced on the HOST.
HERE_SITE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export Y=${Y:-/lus/flare/projects/neutrinoGPU/yuhw}
export WC_WRAP=$HERE_SITE/env/aurora/in-aurora-sl7.sh            # apptainer SL7, no CVMFS (Flare UPS tree)
export WC_SL7_SETUP=$HERE_SITE/env/aurora/setup-aurora-run.sh    # opt + AP + DL vertex
export WC_CPUSET=${WC_CPUSET:-}              # whole node: no pinning (set e.g. 1-103 to leave cores free)
export WC_MAXPAR=${WC_MAXPAR:-100}           # 104 cores, 1 TB: one pair per core is fine (RSS ~2 GB)
export WC_DAY_MAXPAR=${WC_DAY_MAXPAR:-$WC_MAXPAR}   # no day/night rule on a batch node
export WC_DAY_START=${WC_DAY_START:-8} WC_DAY_END=${WC_DAY_END:-20}
export WC_MEM_GUARD_GB=${WC_MEM_GUARD_GB:-800}
export WC_SYS_MIN_AVAIL_GB=${WC_SYS_MIN_AVAIL_GB:-50}
export WC_KRB_WAIT=0
# The wrapper runs apptainer --cleanenv: the per-step knobs run_pair.py / the steps read from the
# environment must be forwarded explicitly (only those that are set are).
export PASS_ENV="${PASS_ENV:-} WC_EVT_SUBDIR WCLS_INPUT_FILE DLVTX_DUMP WC_TRUTH_MATCH"

# Site config: FNAL sbndbuild03 (64 cores, 125 GB, shared).  Sourced on the HOST by bin/run-pairs.sh.
# Owner's rules for this node: never more than half the machine; half again in the day.
HERE_SITE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export WC_WRAP=/exp/sbnd/app/users/yuhw/claude-utilities/in-gpvm-sl7.sh   # SL7 container wrapper
export WC_SL7_SETUP=$HERE_SITE/env/fnal/setup-fnal-run.sh                  # sourced inside, same shell
export WC_CPUSET=${WC_CPUSET:-32-63}         # every process pinned here: at most half the cores
export WC_MAXPAR=${WC_MAXPAR:-28}            # concurrent pairs at night
export WC_DAY_MAXPAR=${WC_DAY_MAXPAR:-14}    # 08:00-20:00 local
export WC_DAY_START=${WC_DAY_START:-8} WC_DAY_END=${WC_DAY_END:-20}
export WC_MEM_GUARD_GB=${WC_MEM_GUARD_GB:-50}       # no new pair while our RSS exceeds this
export WC_SYS_MIN_AVAIL_GB=${WC_SYS_MIN_AVAIL_GB:-15}   # ... or the machine has less available
export WC_KRB_WAIT=1                          # FNAL: wait (do not fail) while there is no Kerberos ticket

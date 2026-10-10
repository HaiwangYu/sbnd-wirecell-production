# Site config: FNAL sbndbuild03 at 60 % (64 cores, 125 GB, shared).  Sourced on the HOST by bin/run-pairs.sh.
# Owner-approved 2026-10-10 for the open FixedDev BNB data run (ai-helper #39): up to 60 % of the CPU
# and memory, halved in the WEEKDAY daytime (people use the node); full 60 % at night and on weekends.
# For anything else use site/fnal-sbndbuild03.sh (the standing half-machine rule).
source "$(dirname "${BASH_SOURCE[0]}")/fnal-sbndbuild03.sh"
export WC_CPUSET=${WC_CPUSET_60:-26-63}      # 38 cores = 60 % of 64
export WC_MAXPAR=38                          # nights and weekends
export WC_DAY_MAXPAR=19                      # Mon-Fri 08:00-20:00
export WC_WEEKEND_DAY_MAXPAR=38              # Sat-Sun 08:00-20:00
export WC_MEM_GUARD_GB=70                    # our RSS; 60 % of 125 GB = 75 GB
export WC_SYS_MIN_AVAIL_GB=15

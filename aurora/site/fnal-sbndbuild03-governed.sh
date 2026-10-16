# Site config: FNAL sbndbuild03 under bin/load-governor.sh (owner rule 2026-10-15, ai-helper #42):
# at most 60 % of CPU and memory while the other users take < 20 % of both, else at most 30 %.
# The governor writes maxpar.override / memguard.override into WC_CONTROL_DIR; every pool sharing
# that dir counts all of this user's run_pair.py jobs (WC_GLOBAL=1), so they share one budget.
# Start the governor first:  nohup bin/load-governor.sh $WC_CONTROL_DIR &
source "$(dirname "${BASH_SOURCE[0]}")/fnal-sbndbuild03.sh"
export WC_CPUSET=${WC_CPUSET_GOV:-26-63}     # 38 cores = 60 % of 64; at 30 % only 19 jobs run on them
export WC_GLOBAL=1
export WC_CONTROL_DIR=${WC_CONTROL_DIR:?set WC_CONTROL_DIR to the shared control dir}
# fallbacks when no override file exists yet (the governor's low level)
export WC_MAXPAR=19 WC_DAY_MAXPAR=19 WC_WEEKEND_DAY_MAXPAR=19
export WC_MEM_GUARD_GB=37
export WC_SYS_MIN_AVAIL_GB=15

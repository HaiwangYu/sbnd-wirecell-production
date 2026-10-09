# FNAL (sbndbuild03 / sbndgpvm) run environment for the 3-step workflow, the twin
# of env/aurora/setup-aurora-run.sh.  Source INSIDE the SL7 container, in the SAME
# shell that then runs the step scripts (pass it as SL7_SETUP to in-gpvm-sl7.sh):
# setup-dlvtx.sh needs the path-prepend FUNCTION that setup-local-opt.sh defines,
# and a function does not survive into a child `bash -c` (ai-helper #38 trap).
WCP_SBND=${WCP_SBND:-/exp/sbnd/app/users/yuhw/wcp-porting-img/sbnd}
source "$WCP_SBND/setup-ap.sh"
source "$WCP_SBND/setup-dlvtx.sh"
# the step-1 fcls (wcls-img-clus-matching{,-data}.fcl) and their #includes
path-prepend "$WCP_SBND" FHICL_FILE_PATH
export FHICL_FILE_PATH
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

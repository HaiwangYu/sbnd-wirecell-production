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
# ai-helper issue 48: the DV2-MAX vertexer (toolkit >= 0.38.0) imports lightgbm, threadpoolctl and scipy.
# Locally scipy comes from the wire-cell-python venv; a FermiGrid worker has no venv, so the code tarball
# ships them as wc/pydv2 (make-tarball.sh WC_TARBALL_PYDV2), found here after the relocation
# (/exp/sbnd/app/users/yuhw -> ${WC_TOP}).  Absent locally: nothing changes.
WC_PYDV2=/exp/sbnd/app/users/yuhw/pydv2
if [ -d "$WC_PYDV2" ]; then path-prepend "$WC_PYDV2" PYTHONPATH; export PYTHONPATH; fi
# ai-helper #45: the Go/ROOT SIGURG step-2 crash
export GODEBUG=asyncpreemptoff=1

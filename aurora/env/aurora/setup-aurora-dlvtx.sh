# Aurora port of setup-polaris-dlvtx.sh: DL (SCN) neutrino-vertex environment.
# Source AFTER setup-aurora-ap.sh, only for jobs running tagger_check_neutrino.
# The scn v01_00_00 product (torch + sparseconvnet venv) exists only on
# /cvmfs/uboone.opensciencegrid.org; it must be copied into $Y/products/scn/
# (plan v2 phase A2.1).  Without it TaggerCheckNeutrino logs "DL vertex failed:
# ... No module named 'torch'" at WARN and SILENTLY falls back to the geometric
# vertex -- always grep the log:  grep -c 'DL vertex failed' lar.log   # want 0
SBND_SCN_PROD=${SBND_SCN_PROD:-${Y:-/lus/flare/projects/neutrinoGPU/yuhw}/products/scn/v01_00_00/Linux64bit+3.10-2.17}
SBND_SCN_SP="$SBND_SCN_PROD/venv/lib/python3.9/site-packages"
if [ ! -d "$SBND_SCN_SP" ]; then
    echo "setup-aurora-dlvtx.sh: ERROR: scn UPS product not found at $SBND_SCN_SP (copy it from uboone CVMFS into \$Y/products)" >&2
else
    path-prepend "$SBND_SCN_SP" PYTHONPATH
    path-prepend "$SBND_SCN_SP/sparseconvnet-0.2-py3.9-linux-x86_64.egg" PYTHONPATH
    # Ours: SCN_Vertex.py + SCN/DeepVtx.py, installed by wcb into $OPT/python.
    path-prepend "${OPT}/python" PYTHONPATH
    export PYTHONPATH
    export OMP_NUM_THREADS=${OMP_NUM_THREADS:-1}
    export MKL_NUM_THREADS=${MKL_NUM_THREADS:-1}
fi

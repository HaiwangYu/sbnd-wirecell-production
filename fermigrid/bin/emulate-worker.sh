#!/bin/bash
# Run bin/job.sh as FermiGrid would, on this machine: the code tarball unpacked into a fresh
# directory, the SL7 image, and ONLY /cvmfs and /pnfs (inputs) mounted -- no /exp, no /nashome --
# so anything the job still needs from the local areas fails here, not on the grid.
#
#   emulate-worker.sh <tarball> <pairs.tsv> <pairs per job> <PROCESS> <sample> <work dir>
# Outputs go to <work dir>/out/<sample>/<id>/ exactly as job.sh lays them out on dCache.
set -euo pipefail
TAR=$(realpath "${1:?tarball}"); LIST=$(realpath "${2:?pairs}"); K=${3:?}; P=${4:?}; SAMPLE=${5:?}; W=${6:?work dir}
mkdir -p "$W"/{tar,input,scratch,out}; W=$(realpath "$W")
tar -C "$W/tar" -xzf "$TAR"; cp "$LIST" "$W/input/"
IMG=/cvmfs/singularity.opensciencegrid.org/fermilab/fnal-dev-sl7:latest
/cvmfs/oasis.opensciencegrid.org/mis/apptainer/current/bin/apptainer exec --contain --cleanenv \
  -B /cvmfs,/pnfs,"$W" --pwd "$W/scratch" \
  --env INPUT_TAR_DIR_LOCAL="$W/tar",CONDOR_DIR_INPUT="$W/input",_CONDOR_SCRATCH_DIR="$W/scratch",PROCESS="$P",WC_GRID_EMULATE=1 \
  "$IMG" bash "$W/tar/wc/sbnd-wirecell-production/fermigrid/bin/job.sh" "$(basename "$LIST")" "$K" "$SAMPLE" "$W/out"

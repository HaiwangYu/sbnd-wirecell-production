#!/bin/bash
# Submit one sample to FermiGrid with jobsub_lite.
#
#   submit.sh <code tarball> <pairs.tsv> <pairs per job> <sample> <campaign tag> [--dry-run]
#
# One job = <pairs per job> consecutive rows of pairs.tsv (bin/find-pairs.py); jobs = ceil(rows/K).
# Outputs: $WC_GRID_OUTBASE/<campaign tag>/<sample>/<id>/  (default /pnfs/sbnd/scratch/users/$USER/prod-fermigrid)
# The code tarball (bin/make-tarball.sh) goes through the RCDS (CVMFS) dropbox, the pairs list with -f.
# Resources (override with the environment):
#   WC_GRID_MEMORY   (3000MB)  peak RSS per pair: step 1 ~1.6 GB (max 3.1), step 2 ~1.5 GB (max 6 on a crash)
#   WC_GRID_DISK     (15GB)    reco1 copy + FrameShift copy (data) + one pair's outputs, with margin
#   WC_GRID_LIFETIME (8h)      expected wall time of a job
#   WC_GRID_USAGE    (DEDICATED,OPPORTUNISTIC)
#   WC_GRID_IMAGE    the SL7 image the local productions use (fnal-dev-sl7)
#   WC_GRID_MAXCONCURRENT      cap on running jobs of this submission (unset = none)
# Needs a valid token (jobsub_lite gets it through htgettoken; the first time interactively).
set -euo pipefail
TAR=$(realpath "${1:?code tarball}"); PAIRS=$(realpath "${2:?pairs.tsv}"); K=${3:?pairs per job}
SAMPLE=${4:?sample}; TAG=${5:?campaign tag}; DRY=${6:-}
F=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUTBASE=${WC_GRID_OUTBASE:-/pnfs/sbnd/scratch/users/$USER/prod-fermigrid}/$TAG
N=$(grep -vc '^#' "$PAIRS"); NJ=$(( (N + K - 1) / K ))
IMG=${WC_GRID_IMAGE:-/cvmfs/singularity.opensciencegrid.org/fermilab/fnal-dev-sl7:latest}
REQ='(TARGET.HAS_SINGULARITY=?=true)&&(TARGET.HAS_CVMFS_sbnd_opensciencegrid_org==true)&&(TARGET.HAS_CVMFS_larsoft_opensciencegrid_org==true)&&(TARGET.HAS_CVMFS_uboone_opensciencegrid_org==true)'
cmd=(jobsub_submit -G sbnd --role=Analysis -N "$NJ"
     --memory="${WC_GRID_MEMORY:-3000MB}" --disk="${WC_GRID_DISK:-15GB}" --expected-lifetime="${WC_GRID_LIFETIME:-8h}" --cpu=1
     --resource-provides=usage_model="${WC_GRID_USAGE:-DEDICATED,OPPORTUNISTIC}"
     --singularity-image "$IMG" --append_condor_requirements="$REQ"
     --tar_file_name "dropbox://$TAR" -f "dropbox://$PAIRS" --mail_never)
[ -n "${WC_GRID_MAXCONCURRENT:-}" ] && cmd+=(--maxConcurrent "$WC_GRID_MAXCONCURRENT")
cmd+=("file://$F/bin/job.sh" "$(basename "$PAIRS")" "$K" "$SAMPLE" "$OUTBASE")
echo "$(date '+%F %T') $N pairs, $K per job -> $NJ jobs; output $OUTBASE/$SAMPLE"
printf '%q ' "${cmd[@]}"; echo
[ "$DRY" = --dry-run ] && exit 0
"${cmd[@]}"

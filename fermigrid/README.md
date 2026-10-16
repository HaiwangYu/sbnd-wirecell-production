# The Wire-Cell production on FermiGrid

This folder runs the r8 workflow on FermiGrid with `jobsub_lite`, using exactly the local builds and configuration. r8 is ai-helper #42: FrameShift for data, step 1, step 2 with the truth match, the CAF merge, validation; `aurora/bin/run_pair.py` per reco1 / flat-CAF pair.

Tracking: [sbnd-wirecell-production #1](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/1).

## Why jobsub_lite, and what is taken from larbatch

`larbatch`'s `project.py` (`/cvmfs/larsoft.opensciencegrid.org/products/larbatch/v01_61_01/bin/project.py`) wraps `jobsub_submit` around one `lar` stage per job (`condor_lar.sh`). A pair here is not one `lar` command; it is `run_pair.py`, steps 0–3. So `bin/submit.sh` calls `jobsub_submit` directly, with the same mechanics `project.py` uses:

| | `project.py` | here |
|---|---|---|
| code | a local release tarball, `--tar_file_name dropbox://` (RCDS, CVMFS-based) | the same: `bin/make-tarball.sh` → `--tar_file_name dropbox://wcgrid-*.tar.gz` |
| container | `+SingularityImage` + `HAS_SINGULARITY` | `--singularity-image` (`fnal-dev-sl7`, the image the local productions use) + `HAS_SINGULARITY` and `HAS_CVMFS_{sbnd,larsoft,uboone}` |
| resources | `--memory --disk --expected-lifetime --resource-provides=usage_model=…` | the same, from `WC_GRID_*` |
| inputs | SAM project / `ifdh cp` | the pairs list (`-f dropbox://pairs.tsv`) + `ifdh cp` of each reco1 and CAF |

## The code tarball (`bin/make-tarball.sh`)

The tarball ships what a local job reads from `/exp` or `/nashome`. The list was established by tracing every successful `open`/`execve` of one MC and one data pair through all steps (`strace -f`, 156 files). The UPS stack (sbndcode `v10_14_02_03` `e26:prof`, the scn product, …) comes from CVMFS on the worker.

| shipped | from `/exp/sbnd/app/users/yuhw/` |
|---|---|
| `wire-cell`, `libWireCell*.so`, `libWCP*.so`, rootmap, pcm | `opt/` (debug info stripped: symbols only, same code) |
| larwirecell plugins and fcl | `opt/larwirecell/v10_01_28` |
| SCN vertex code, `opt/share/wirecell`, the `ups-patches` | `opt/python`, … |
| `cfg/` | `wire-cell-toolkit/cfg` (all), `sbndcode/sbndcode/WireCell/cfg` |
| data | `wire-cell-data`: `sbnd/`, the SBND geometry / charge-error / photon files, the BDT + XGBoost weights and the SCN model in use |
| step-1 fcls and jsonnet | `wcp-porting-img/sbnd/*.fcl`, `*.jsonnet` |
| workflow | `sbnd-wirecell-production/aurora/{bin,lib,schema,env,site}`, `fermigrid/` |
| setup scripts | `setup-local-opt.sh`, `setup-ap.sh`, `setup-dlvtx.sh`, `aurora/env/fnal/setup-fnal-run.sh`, with `/exp/sbnd/app/users/yuhw` → `${WC_TOP}` |

- Everything sits at its path relative to `/exp/sbnd/app/users/yuhw`, under `wc/`. The job sets `WC_TOP=$INPUT_TAR_DIR_LOCAL/wc`.
- `WIRECELL_PATH`, `LD_LIBRARY_PATH`, `FHICL_FILE_PATH`, `CET_PLUGIN_PATH` and `PYTHONPATH` get the local entries in the local order.
- `TARBALL-PROVENANCE.txt` in the tarball records every repository's commit.
- Size: 83 MB.
- `python3` is CVMFS Python 3.9.15. The local runs use the `wire-cell-python` venv built on it, but the trace shows no module imported from the venv.

## A job (`bin/job.sh`)

Job `$PROCESS` takes K consecutive rows of the pairs list. For each pair:
1. `ifdh cp` the reco1 and the CAF to scratch;
2. `run_pair.py` with `WC_KEEP=semiprod` and `WC_STAMP_INPUT_FILE=1` (the event's `input_file` and the merged CAF's provenance name the original /pnfs files, not the copies);
3. copy to `<output base>/<sample>/<id>/`:

| file | content |
|---|---|
| `<id>.qlpctree.tar.gz` | step 1 |
| `<id>.tracking-pr.tar` | every `pr/all/pr_evt<E>/tracking-pr.root` of the pair, paths kept (one file per pair instead of one per event, for dCache) |
| `<merged CAF>.wc.flat.caf.root` | the flat CAF with `recTreeWireCell` |
| `<id>.logs.tar.gz` | `status`, `run_pair.log`, `events.json`, `validate.json`, `merge.json`, `cost.tsv`, every lar / wire-cell log |

The FrameShift copy and Bee are not kept. The job exits non-zero unless every pair is `OK` or `PARTIAL`.

## Before the grid: emulate a worker (`bin/emulate-worker.sh`)

`job.sh` runs in the SL7 image with only `/cvmfs` and `/pnfs` mounted (no `/exp`, no `/nashome`) and the tarball unpacked into a fresh directory. `bin/compare-outputs.py` then compares the outputs with a local run of the same pair, value by value (uproot, NaN = NaN; `qlpctree` tensors by datapath).

2026-10-16, one MC CV pair (5 events) and one beam-off pair (2 events) vs the same pairs run locally:
- **MC:** 100 trees, 18,581 branches identical; 1,128 `qlpctree` tensors identical.
- **Data:** identical except `Trun.input_file` (the original reco1 instead of the FrameShift copy, by design).
- **Both:** `recTreeWireCell_info` names the original CAF.

## Usage

```bash
# 0. a token (the first time interactively, a browser link; then Kerberos renews it)
htgettoken -a htvaultprod.fnal.gov -i sbnd
# 1. the code tarball
bin/make-tarball.sh /exp/sbnd/data/users/$USER/production-prep/fermigrid-dev/tar/wcgrid-<tag>.tar.gz
# 2. pairs: ../aurora/bin/find-pairs.py (MC: --caf-relation child; Gen2 InTime data: sibling)
# 3. submit one sample
bin/submit.sh <tarball> <pairs.tsv> <pairs per job> <sample> <campaign tag> [--dry-run]
# 4. watch
jobsub_q -G sbnd --user $USER
```

## Status

See issue #1.

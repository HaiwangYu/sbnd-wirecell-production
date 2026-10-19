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

Job `$PROCESS` takes K consecutive rows of the pairs list. (In a `--maxConcurrent` DAG every node has `PROCESS=0`, and the index is `JOBSUBJOBSECTION`.) For each pair:
0. list `<output base>/<sample>/<id>/` (`ifdh ll <dir> 1`):
   - a **finished** pair is skipped. Finished means `<id>.done` is there; for fg1 outputs, made before the marker existed, it means the merged CAF, the qlpctree, `<id>.tracking-pr.tar` and `<id>.logs.tar.gz` are all there.
   - if the listing fails (3 tries), the pair is skipped and nothing is run or written;
1. `ifdh cp` the reco1 and the CAF to scratch. Each copy must have the source's size (`ifdh ll`); otherwise the copy is retried, up to 3 tries, and then the pair is `FETCH FAILED`;
2. `run_pair.py` with `WC_KEEP=semiprod` and `WC_STAMP_INPUT_FILE=1` (the event's `input_file` and the merged CAF's provenance name the original /pnfs files, not the copies);
3. list the destination again, then copy to `<output base>/<sample>/<id>/`. Each file must arrive with its local size (3 tries):

| file | content |
|---|---|
| `<id>.qlpctree.tar.gz` | step 1 |
| `<id>.tracking-pr.tar` | every `pr/all/pr_evt<E>/tracking-pr.root` of the pair, paths kept (one file per pair instead of one per event, for dCache) |
| `<merged CAF>.wc.flat.caf.root` | the flat CAF with `recTreeWireCell` |
| `<id>.logs.tar.gz` | `status`, `run_pair.log`, `events.json`, `validate.json`, `merge.json`, `cost.tsv`, every lar / wire-cell log |
| `<id>.done` | written last, only for an `OK`, `PARTIAL` or `EMPTY` pair whose files all arrived: the status, the job, and each file with its size |

**Nothing at the destination is overwritten:**
- `ifdh cp` refuses to overwrite a dCache file anyway (gfal: "exists and overwrite is not set").
- The logs of a later try go to `<id>.logs.try<k>.tar.gz`.
- A data file left by an interrupted try of an unfinished pair is kept if its size matches, and replaced otherwise.
- If the pair became finished while the job ran, only the logs are written.

**An empty reco1 file** (0 entries in `Events`) gives `EMPTY no events in the reco1 file`; nothing runs and only the logs and `<id>.done` are written. fg1 had 38 such gen2 InTime files and 4 nueCC ones; 2 of the InTime files carry a non-zero SAM `event_count`.

The FrameShift copy and Bee are not kept. The job exits non-zero unless every pair is finished.

**Why (fg1, issue #1):**
- `job.sh` listed the destination with `ifdh ls <dir> 0`, which prints only the directory itself, so a restarted job could not see a finished pair: it would run the pair again, and its copies would fail as "exists".
- In 3 pairs (2 CV, 1 nueCC), the first try saw 0 events, most likely a truncated input copy: the source files hold 12, 12 and 14 events. A later try produced the outputs, but its logs could not replace the first try's. Their `logs.tar.gz` is the failed first try; the data files are good.

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

## The grid test (2026-10-16): identical to r8

- **Setup:** cluster `30675092@jobsub05`, 4 jobs, 2 pairs each. 7 MC CV pairs of r8 semi-production, 108 events. Tarball v2: toolkit `4b6853d4`, larwirecell `ad5d942`, workflow `dec6fb2`.
- **Timing:** started within a minute of submission; all done in 53 min. Nodes: fnpc18001, fnpc18003, fnpc8201, fnpc17011.
- **Result:** 7/7 pairs `OK`.
- **`bin/compare-outputs.py` against r8, per pair:**
  - every tree of every `tracking-pr.root` and of the merged CAF (2,070 trees, 324k branch arrays) is identical, `Trun.input_file` included;
  - every `qlpctree` tensor (24.4k, arrays and metadata) is identical;
  - the only difference is the `recTreeWireCell_info` note: its creation time and the schema's path (on CVMFS instead of `/exp`; same file).
  - The CAF's `globalTree` is not readable by uproot. The merge copies it byte for byte.
- **Grid speed:** about **2.1× the r8 local time** on the same pairs (70.4 vs 33.1 s per event). Per pair 49–98 s per event; the slowest node (fnpc8201) ran at ~98.
- **Memory:** peak RSS ≤ 1.94 GB. Setup and copies are negligible (seconds).

## Resource estimate and proposal (for review)

Per event on the grid = r8 local × 2.13 (measured on MC CV; nueCC and beam-off scaled from their r8 local cost):

| sample | events | r8 local s/evt | grid s/evt | events/file | files | core-hours | output (kept) |
|---|---|---|---|---|---|---|---|
| MC BNB CV | 500,000 | 36.7 | ~78 | 13.2 | ~37,900 (of 749k in the def) | ~10,800 | 3.26 MB/evt → ~1.6 TB |
| MC nueCC | 100,000 | 61.3 | ~131 | 8.5 | ~11,800 (of ~13,400 with a CAF) | ~3,600 | 4.28 → ~0.43 TB |
| beam-off (InTime) | 50,000 | 24.2 | ~52 | 47.3 | ~1,060 (of 49k) | ~720 | 2.37 → ~0.12 TB |
| **total** | 650,000 | | | | ~50,800 | **~15,200 (+~3 % retries)** | **~2.2 TB** |

- **Input read from dCache:** about 17 TB (CV 13.7, nueCC 3.2, beam-off 0.2). A random 150 files of each def were all `ONLINE`, so no prestage is expected.

**Proposed job shape** (aim: 2–3 h jobs, so a lost job costs little):

| sample | pairs per job | events per job | expected job time | jobs |
|---|---|---|---|---|
| MC CV | 8 | ~106 | ~2.3 h | ~4,740 |
| MC nueCC | 10 | ~85 | ~3.1 h | ~1,180 |
| beam-off | 3 | ~142 | ~2.0 h | ~354 |

**Proposed resources per job:**

| setting | proposal | why |
|---|---|---|
| `--cpu` | 1 | every step is single-threaded |
| `--memory` | **4000MB** | median peak ~1.6 GB, but r8 has rare successful steps up to 3.0 (step 1) and 5.3 GB (one beam-off step 2), and the step-2 crash runaway reaches 4.2–4.5 GB. Plus `+FERMIHTC_AutoRelease=True; +FERMIHTC_GraceMemory=2048`: a job held for memory is released with 2 GB more, and the restart skips the pairs already copied (`job.sh`) |
| `--disk` | 6GB | reco1 ≤ 0.5 GB + FrameShift copy (data) + one pair's work and outputs (≤ 0.3 GB) |
| `--expected-lifetime` | 6h | 2–3 h expected; the slowest node is ~1.4× the average |
| `usage_model` | DEDICATED,OPPORTUNISTIC | onsite first; OFFSITE (OSG) is possible later (CVMFS + xrootd/ifdh), but not tested |
| `--maxConcurrent` | ~2,000 per sample | caps the dCache load (~17 TB read) and our share of `group_sbnd` |

**Queues** (HTCondor at `gpcollector03`, 2026-10-16):
- FermiGrid pool: 12,506 slots, 11,253 claimed.
- `group_sbnd` quota: 8,001 (ICARUS 8,000, DUNE 6,400, uBooNE 3,400). SBND's weighted use at that moment: ~19.7k (surplus sharing).
- Jobs run as `--role=Analysis` in `group_sbnd`.
- Most partitionable slots are sized at ~2–2.5 GB per core, so 4 GB jobs match fewer of them than 2 GB jobs would.

**Elapsed time** for ~15.7k core-hours: ~16 h at 1,000 concurrent jobs, ~8 h at 2,000, ~5 h at 3,000.

**Open points for review:**
1. **Which files.**
   - CV: the first ~37,900 files of the def by name, or a random seeded sample; with or without r8's 990.
   - nueCC: ~11,800 of ~13,400.
   - beam-off: ~1,060 of 49k; with or without r8's 212.
2. **Output on `/pnfs/sbnd/scratch`** (~2.2 TB) is not permanent: dCache scratch evicts files that are not used. Copy to persistent or tape-backed storage afterwards?
3. **Memory:** 4000MB + auto-release (proposed), or 3000MB to match more slots and accept rare memory holds.
4. **Concurrency cap**, and onsite only vs adding OFFSITE.

Before submitting: the full pairs lists, made in bulk (`samweb list-file-locations` + batched metadata; per-file SAM calls would take ~12 h for 38k files).

## Status

See issue #1.

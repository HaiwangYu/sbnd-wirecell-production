# run3bnb: Run 3 BNB real data on FermiGrid, with the fg1 configuration

- Tracking: [sbnd-wirecell-production #5](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/5). fg1: [#1](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/1).
- **Status:** **submitted 2026-11-07 23:15 CST** (owner's go-ahead; BNB only, not the Run 3 off-beam sample).
  - Cluster `87458459@jobsub01`: 736 jobs, a plain cluster (index = `PROCESS`).
  - Output `/pnfs/sbnd/scratch/users/yuhw/prod-fermigrid/run3bnb/bnb-data/`.
  - Submit log: `production-prep/fermigrid-dev/run3bnb/submit.log`.

## Request (owner, 2026-11-07)

- Run `data_SBND2026A_Gen2_Run3_BeamLight_Fixed_Dev_Data_v10_14_02_08_reco1_sbnd` with the same configuration as fg1: FermiGrid, the fg1 chain.
- Reference: https://sbnsoftware.github.io/sbn/sbnprod_wiki/gen2_data

## The sample

| | |
|---|---|
| reco1 | `data_SBND2026A_Gen2_Run3_BeamLight_Fixed_Dev_Data_v10_14_02_08_reco1_sbnd`: 2,208 files, 109,487 events (SAM `sbn_dm.event_count`), ~50 events per file, ~204 MB per file |
| flat CAF | `data_SBND2026A_Gen2_Run3_BeamLight_Fixed_Dev_Data_v10_14_02_08_flatcaf_sbnd`, ~10 MB per file |
| runs | 7 runs, 20586–20597 (files per run: 244, 357, 241, 416, 134, 340, 476) |
| production | sbndcode `v10_14_02_08`; one job per raw file: `decode_reco1_reco2_caf`; `production.name` `Gen2_Run3_BeamLight_Fixed_Dev_Data`; stream `bnblight` |
| POT | 5e18 (wiki) |
| **blinding** | **unblinded**: the wiki lists "Run 3 Fixed Development: Files 2208: Events 109k: POT: 5e18" under *Data (Unblinded)*, "available for use and doesn't require access requests". (Full Run 1 BNB, Full Run 2b and Full Run 2c BNB are the blinded sets.) |

**Pairs:** `fermigrid/bin/make-pairs-bulk.py --relation sibling`. The reco1 and its flat CAF are both children of one raw file, as for fg1's beam-off data.
- **Result:** 2,208 pairs, 109,487 events, 0 skipped: every reco1 has exactly one sibling CAF, and all files are ONLINE (checked 2026-11-07).
- **Lists:** `/exp/sbnd/data/users/yuhw/production-prep/fermigrid-dev/run3bnb/pairs-run3bnb.tsv` (+ `make-pairs.sh`).

## Configuration: fg1's, exactly

| | |
|---|---|
| chain (data) | FrameShift (`run_frameshift.fcl`, a copy of the reco1) → step 1 `wcls-img-clus-matching-data.fcl` → step 2 `wct-pr.jsonnet` (DL vertex + dump, flat tree) → merge into the flat CAF → value-by-value validation |
| builds | wire-cell-toolkit `sbnd-wc-flatcaf` `4b6853d4`, larwirecell `ad5d942`, wcp-porting-validation `88cb05aa`, wire-cell-data `9e2f4b8`, sbndcode `v10_14_02_03` `e26:prof` (CVMFS) |
| workflow | sbnd-wirecell-production `c93da2c` = fg1 + the `job.sh` fixes (`d83d26e`: copy checks, no overwrite, `EMPTY`) |
| tarball | `/exp/sbnd/data/users/yuhw/production-prep/fermigrid-dev/tar/wcgrid-run3bnb.tar.gz` = `wcgrid-fg2.tar.gz` (md5 `db37e862f147`). Its 2 "dirty" files are the pair-selection script and a doc, which the job does not use |
| job | `fermigrid/bin/job.sh`, `WC_KEEP=semiprod`, `WC_STAMP_INPUT_FILE=1`; 3 pairs per job (fg1 beam-off: 3) |
| resources | 1 CPU, 4000 MB + `FERMIHTC_AutoRelease` (+2 GB grace), 6 GB disk, 6 h, `DEDICATED,OPPORTUNISTIC`, `--maxConcurrent 2000` (736 jobs, so a plain cluster) |
| output | `/pnfs/sbnd/scratch/users/yuhw/prod-fermigrid/run3bnb/bnb-data/<id>/` (qlpctree, tracking-pr tar, merged CAF, logs, `<id>.done`); merged CAFs copied to `/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/run3bnb/` |

### Why the workflow is pinned to `c93da2c`, not `main`

`main` now carries the Aurora campaign's per-event directory naming (`a0227bc`, Aurora issue #3):
- `run_pair.py` sets `WC_EVT_SUBDIR=pr_evt{run}_{subrun}_{event}`, and `step2.sh` passes it as `evt_subdir`.
- Filling the template in needs a newer toolkit than the fg1 build.

The first local smoke test (2026-11-07, `main`) showed what happens with the fg1 build: every event of a file was written to **one directory literally named `pr_evt{run}_{subrun}_{event}`**. Each event overwrote the last, and only 1 of 50 events per file reached the merged CAF (both pairs `PARTIAL`, 49/50 events without Wire-Cell). The jobs did not fail.

The fg1 layout (`pr_evt<event>`) is safe for this sample:
- every reco1 file comes from one raw file, so one subrun;
- data event numbers are unique within a run.

fg1 itself is unaffected: none of fg1's 50,241 files repeats an event number (checked on the fg1 event lists).

## Checks done (2026-11-07)

1. **Unblinded** (wiki, above).
2. **The fg1 chain reads `v10_14_02_08` reco1:** step 1 with the `v10_14_02_03` stack, no missing products.
3. **FrameShift works on Run 3:** `frame_apply_at_caf` 1.26–1.55 µs on every event, not 0 (Run 1: 1.2–1.9 µs).
4. **Emulated grid worker** (`fermigrid/bin/emulate-worker.sh`, the run3bnb tarball, SL7, only `/cvmfs` + `/pnfs`), 2 pairs, 1 per job:

   | pair | status | events with Wire-Cell | tracking-pr.root | step 0 / 1 / 2 / 3 / validate wall | peak RSS |
   |---|---|---|---|---|---|
   | `df9801fe` (run 20586) | OK | 50 / 50 | 50 | 13 / 1106 / 186 / 6 / 20 s | 1.59 GB |
   | `dc0145fb` (run 20594) | OK | 50 / 50 | 50 | 13 / 1044 / 232 / 6 / 27 s | 1.58 GB |

   Outputs: 128 MB per pair (qlpctree 2.0 MB/event, tracking-pr 0.5 MB/event, merged CAF 12.5 MB). Validation passed.

## Estimate

- **Per event:** 27 s on sbndbuild03, in the emulated worker. fg1 ran 1.16× local on the grid (CV), plus ~4 % for reruns and setup, so **~33 s per event on the grid**.

| events | pairs | jobs (3 pairs) | per job | core-hours | scratch output | persistent (merged CAFs) | input read |
|---|---|---|---|---|---|---|---|
| 109,487 | 2,208 | 736 | ~1.4 h | **~1,000** | ~280 GB | ~28 GB | ~470 GB (reco1 450 + CAF 22) |

- **Elapsed:** a few hours at full concurrency (736 jobs < 2,000).
- **Expected losses (as fg1, ~0.03 %):** step-1 timeouts on slow nodes, the `ClusteringConnect1` recursion segfault, rare memory kills, the intermittent step-2 crash. See #1.

## Before submitting

1. A valid token. The ticket in `/tmp/krb5cc_53514_r8campaign` is valid to 2026-11-08 09:42; then `htgettoken -a htvaultprod.fnal.gov -i sbnd`.
2. **Submit from the repo checked out at `c93da2c`, or from `main` with `job.sh` as of `d83d26e`.** The job only uses the tarball's copy of the workflow; `submit.sh` and `job.sh` are the same in both:
   ```bash
   WC_GRID_MEMORY=4000MB WC_GRID_DISK=6GB WC_GRID_LIFETIME=6h WC_GRID_MAXCONCURRENT=2000 \
   WC_GRID_LINES="+FERMIHTC_AutoRelease=True;+FERMIHTC_GraceMemory=2048;+FERMIHTC_GraceLifetime=3600" \
     fermigrid/bin/submit.sh <tar>/wcgrid-run3bnb.tar.gz <run3bnb>/pairs-run3bnb.tsv 3 bnb-data run3bnb
   ```
3. Then: a status scan (`.done`), resubmission of dead jobs (`job.sh` skips finished pairs), the persistent copy (ADLER32), the README and lists, and the event list (`fg2/event-list.py`).

## Log

- 2026-11-07:
  - Sample checked (unblinded, 2,208 pairs, all ONLINE).
  - The `main` workflow's `evt_subdir` incompatibility with the fg1 build was found by the local smoke test.
  - The fg1-configuration tarball passed the emulated worker on 2 pairs (100/100 events).
  - Issue #5 opened.
  - Owner: submit, BNB only.
  - The first submit attempt failed (no token: the r8 ticket cache no longer exists); resubmitted with the session's ticket (valid to 11-08 22:07, renewable to 11-14).
  - Cluster `87458459@jobsub01`, 736 jobs, submitted 23:15.

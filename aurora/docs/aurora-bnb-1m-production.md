# Aurora production: the BNB 1M sample (gen2-wct0319, Avinay, 2026-10)

Tracking doc for running the r8 chain ([`aurora-r8-chain.md`](aurora-r8-chain.md)) on Aurora over Avinay's BNB 1M reco1 + flat-CAF sample. GitHub: HaiwangYu/sbnd-wirecell-production issue #2.

Steps (owner, 2026-10-19): (1) read the guide; (2) validate the aurora workflow against the r8 reference (gate G4); (3) a ~10k-event smoke on the new sample; (4) the 1M run only on the owner's go.

## 1. State on 2026-10-19 (before anything ran)

| item | state |
|---|---|
| toolkit | was `master b7bd2a1a`; checked out `sbnd-wc-flatcaf` `4b6853d4` (the r8 pin; it contains PR 536 = the final `dl_vtx_dump` columns), `cfg/` clean |
| larwirecell, and the MRB clone | both `sbnd-wc-flatcaf` `ad5d942` |
| wcp-porting-validation | `main` `3a9f5914` (pulled) |
| this repo | `main` `c93da2c` |
| `$OPT` | was the ai-helper #35 build (`21562551`); rebuilt `CLEAN=1` in job 8944988 (section 2) |
| wire-cell-data | `74ff57a` + the untracked XGB weights; md5 of the XGB and SCN files as pinned |
| r8 reference bundle | `$Y/production-prep/aurora-r8-reference`, `md5sum -c` 18/18 OK; `pairs.tsv` made from the template |
| uproot / awkward | installed `--user` for the UPS python 3.9 (`setup-uan-root.sh`): uproot 5.6.9, awkward 2.8.12. The UAN system python is 3.6 and cannot take uproot 5 |
| Flare project quota | 3.117 of 3.2 PB soft (3.52 hard): ~83 TB free |
| ai-helper `build-wct-lwc.pbs` | the larwirecell stage now builds whatever branch `$Y/larwirecell` has checked out (it pulled `dev-v10_14_02_02` by name before) |

## 2. Gate G4: build + the r8 reference pairs (job 8944988)

`pbs/build-and-g4.pbs`: one debug job = clean build (toolkit + larwirecell) + gates G1/G2 + `run-pairs.sh` on the 2 reference pairs with `WC_KEEP=validation` into `$R/aurora-run`. Results: section 5.

Job 8944988 (debug, 4 min queue, 22 min wall; 04:14-04:36 UTC):
- build: `WCB_RC=0`, `rpath_stripped=20`, `ldd_not_found=0`, `MRB_RC=0`, `tree_wirecell_refs=0`; larwirecell built from `sbnd-wc-flatcaf ad5d942`.
- G2: `make_RootFlatTreeVisitor_factory` 1, `T_overlap` 1, `respond_to_open_input_file` 3, `prong_trackid` 1.
- G4 run: both pairs `OK`, `validate.json` `PASS`, `dl_fail` 0; 20 events with Wire-Cell output. First run of the 2-step chain on Aurora.
- cost (2 pairs alone on the node, so no contention):

| step | wall per event [s] | CPU per event [s] | max RSS [MB] | output per event [MB] |
|---|---|---|---|---|
| step1 | 36.5 | 20.3 | 1547 | 7.99 (validation keep: tar + Bee + h5) |
| step2 | 16.7 | 14.0 | 1416 | 1.13 |
| step3 | 0.3 | 0.2 | 427 | 1.08 |
| validate | 1.0 | 0.9 | 741 | – |

  r8 at FNAL: ~29-37 s per event all steps. Aurora here: 54 s wall per event per slot, 35 s CPU.
- value-by-value comparison with r8 (`compare-outputs.py` on the UAN, ~10 min per pair; `aurora-run/<id>/compare.json`):

| pair | trees / branches / events | qlpctree tensors | differing branches |
|---|---|---|---|
| CV 0a6e (13 events) | 248 / 37,553 / 13 | 2939 = 2939, 0 array diffs, metadata = `input_file` only | `Trun.input_file` (ignored), `Trun.wct_version`, `T_dlvtx_call.payload` (2 events), `recTreeWireCell_info` |
| nueCC 86e4 (7 events) | 146 / 33,284 / 7 | 1585 = 1585, 0 array diffs, metadata = `input_file` only | the same set: `wct_version`, `payload` (7 events), `recTreeWireCell_info` |

  The payload differences: top-20 scores at the 1e-6 level (float32 across hosts); in nueCC event 12220 two voxels with score 1.0 swap rank (same voxel set). `status`, `accepted`, `rerank_row`, `dl_row`, `dl_x/y/z`, `trad_row` and every other tree are identical on all 20 events. `wct_version` is the build's `git describe` string (FNAL `sbnd-dlvtx-35-pre-master-merge-2026-09-02-424-g78f81c64`, Aurora `sbnd-wc-flatcaf-sbnd-dlvtx-35-pre-master-merge-51-g4b6853d`, the same commit). Both added to the guide's expected-differences list.

**Gate G4: PASS** (2026-10-19). The aurora workflow reproduces r8.


## 3. The new sample (inventory 2026-10-19)

`/lus/flare/projects/neutrinoGPU/abhat/sbnd/gen2-wct0319-bnb-1m-*`, sbndcode `v10_14_02_03 e26:prof`, `prodgenie_corsika_proton_rockbox0p1_sbnd`, standard gen/g4/detsim/reco1/reco2 fcls, CAFmaker `cafmakerjob_sbnd_sce_systtools_and_fluxwgt_and_g4rw.fcl`; provenance in each directory's `restartable_provenance/provenance.json` (`wct_source 0319ea67`). Layout: `reco1/NNNNNN/NNNNNN/reco1-detsim-g4-gen-<id>.root` (+ `.json` sidecar), `caf/NNNNNN/NNNNNN/reco2-reco1-detsim-g4-gen-<id>.flat.caf.root` (+ `.json`).

| directory | reco1 files | flat CAFs | events in the CAFs |
|---|---|---|---|
| restartable-20261013-shard01 | 75,640 | 3,771 | 198,803 |
| restartable-20261013-shard02 | 75,640 | 3,770 | 198,943 |
| restartable-20261013-shard03 | 74,431 (running) | 0 yet | – |
| capacity-20261016-batch01..05 | 1,280 × 4 + 1,279 | 64 × 4 + 63 | 16,982 |
| **with CAFs so far** | **156,159** | **7,796** | **414,728** |

Shards 04–05 are to come; the owner expects the full 1M after the 2-day maintenance.

**The structural difference from r8:** a reco1 file holds **~2.6 events** (r8's held 7–17), and **each flat CAF merges 20 reco2 files** (54–60 events per CAF; the CAF sidecar's `parents` lists the 20 `reco2-reco1-...root` names, and the CAF is named after one of them). So:
- the workflow's pairing rule (one CAF named after its one reco1) matches only 1 reco1 in 20, and would merge a 54-event CAF with Wire-Cell output for ~3 events;
- one `lar` per reco1 file would spend most of its time starting up (r8: ~45 s per event with 13–17 events per file, where the start-up is amortised).

Checked: `reco1-<id>.root` ↔ parent `reco2-reco1-<id>.root` by name, 20 parents on every CAF of every directory (7,796 of 7,796).

**Proposal (needs the owner's decision):** the unit becomes *one flat CAF + its 20 parent reco1 files* (from the sidecar), ~54 events. Step 1 = one `lar` over the 20 files (`-s f1 … -s f20`); steps 2 and 3 unchanged (the merge aligns by run/subrun/event whatever the number of input files). Changes: `find-pairs.py` gains a sidecar mode (reco1 column = the 20 paths), `run_pair.py` / `step1.sh` accept several reco1 paths (precheck, event count, `--nskip` slicing over the concatenation), id = the CAF stem. Alternative: ask Avinay for one CAF per reco1 (not recommended: 380k tiny CAFs and lar jobs).

**Decision (owner, 2026-10-21):** the multi-reco1 unit as proposed. Implemented in `bin/find-pairs.py --caf-sidecar-dir` (reco1 column = the parents, comma-separated, in sidecar order; id = the CAF stem; events = the sum of the reco1 sidecars' `event_count`, which must equal the CAF's), `bin/run_pair.py` (per-file precheck and event count → `reco1_files.json`; EMPTY only when every file is; one step-0 copy per file on data), `bin/step1.sh` (one `-s` per file, one `lar`), `bin/count-events.py` (several files). `pbs/run-pairs-debug.pbs` runs a pair list on one debug node with a 30 s node sampler (`node.log`: MemAvailable, our RSS, process counts, load).

### 3a. One unit's full history (gen → CAF)

Example: CAF `shard01/caf/000000/000006/reco2-reco1-detsim-g4-gen-eee3-6ab2-0cd8-4bb1.flat.caf.root` (44 events, run 2100126, subruns 20–39, POT 3.17e15 = the sum of its 20 subruns). The workflow (`runinfo/config.toml`: `subruns_per_caf = 20`, `nevts = 10`, depth-first per subrun; 3782 subrun groups per shard, 11 excluded for deterministic reco2 stalls → 3771 CAFs) is a pure 1:1 chain per subrun from gen to reco2 and a 20 → 1 merge at the CAF:

| stage | file for subrun 29 (hash 0677) | on disk | events |
|---|---|---|---|
| gen (`prodgenie_corsika_proton_rockbox0p1_sbnd.fcl`) | `gen-0677-….root` | sidecar only | 10 |
| g4 (`standard_g4_rockbox_sbnd.fcl`, the rockbox filter) | `g4-gen-0677-….root` | sidecar only | 1 |
| detsim | `detsim-g4-gen-0677-….root` | sidecar only | 1 |
| reco1 | `reco1/000000/000006/reco1-detsim-g4-gen-0677-….root` | **yes** (13 MB) | 1 |
| reco2 | `reco2-reco1-detsim-g4-gen-0677-….root` | no (no sidecar either) | 1 |
| CAF (20 reco2 → 1) | `caf/000000/000006/reco2-reco1-…-eee3-….flat.caf.root` | **yes** | 44 |

The 20 reco1 parents of this CAF (all in `reco1/000000/000006/`) hold 1, 3, 4, 1, 1, 2, 3, 3, 3, 2, 3, 1, **0**, 3, 1, 1, **0**, 2, 6, 4 events; the CAF's name comes from the empty subrun 20. About 6 % of the reco1 files are empty (117 of 2000 in that directory): they stay in the unit (art skips them) so the sidecar count and ours agree. Shard-wide search: no gen/g4/detsim/reco2 ROOT file exists anywhere; only reco1 ROOT + sidecars and the CAFs.

## 4. Sizing: the smoke jobs of 2026-10-21 (pre-fix build; step-1 numbers valid)

Two 1-node jobs, 59 min, `WC_KEEP=semiprod`, units of 32–44 events (the smallest of shard01 so that a unit fits the hour): `s104` = 104 units / 4,013 events at WC_MAXPAR 104 (job 8949343, debug-scaling), `s208` = 208 units / 8,854 events at WC_MAXPAR 208 (8949344, debug). Per-unit costs from `cost.tsv` (successful rows, medians over the 100 finished units each; `$Y/production-prep/bnb1m/smoke-analyze.py`):

| | s104 (100 running) | s208 (100 running, see below) | eq test (21 running) | G4 ref (2 running) |
|---|---|---|---|---|
| step 1 wall / event | **35.5 s** (29.8–47.0) | 35.9 s | 23.5 s | 36.5 s (bigger events) |
| step 1 CPU / event | 32.2 s | 34.3 s | 20.3 s | 20.3 s |
| step 1 CPU / wall | 0.92 | 0.94 | 0.86 | 0.56 |
| step 1 max RSS median / max | 1.57 / 3.20 GB | 1.57 / 2.33 GB | 1.6 GB | 1.55 GB |
| step 2 wall / event | 4.1 s | 4.4 s | 2.5 s | 16.7 s |
| step 2 max RSS | 1.39 / 1.75 GB | 1.40 / 2.23 GB | 1.27 GB | 1.42 GB |
| step 3 + validate / event | 0.4 s | 0.3 s | | 1.3 s |
| unit wall median (step 1) | 1,360 s (39 events) | 1,518 s (42 events) | | |
| node: our RSS max / MemAvailable min / load max | 153 GB / 967 GB / 101 | 155 GB / 968 GB / 107 | | |

So at 100 workers a node does ~**2.5 events/s ≈ 9,000 events per node-hour** in steady state (40 s per event per worker: 35.5 + 4.1 + 0.4), with memory nowhere near a limit (1.6 GB per worker; 153 GB of 1,134 GB used). The per-event CPU rises from 20 s (2–21 workers) to 32 s (100 workers): memory-bandwidth / cache contention, not I/O (CPU/wall 0.92).

**The real limit is the job cgroup's `pids.max = 8192`** (tasks = processes + threads; measured on a node: `/sys/fs/cgroup/jobs/<id>/pids.max`). Both jobs stalled at ~100 units: at 03:44:56 (104 lar running in s104, 120 in s208) the next container launches died with `runtime/cgo: pthread_create failed: Resource temporarily unavailable` (lar rc 134) or `no apptainer` from the wrapper → s104 4 FAIL, s208 104 FAIL, and both pools then ran at ~100. A step-1 unit chain is ~75 tasks (apptainer `starter` 9 threads + `squashfuse_ll` 9 + bash/time/timeout + lar's own threads, which the fix2 job measures). So 208 workers per node need ≤ 39 tasks per unit, or a larger pids.max (ALCF). `run-pairs.sh` now waits when fewer than `WC_PIDS_HEADROOM` (400) tasks are left instead of launching into the wall.

**Rough sizing at 100 workers/node:** 620k events ÷ 9,000 ≈ **69 node-hours** of steady state; with the ramp-up (2 s between launches → 3.5 min to fill a node) and the tail of a 1-hour job (units of ~52 events take ~35 min; a unit cannot be split across jobs without losing its partial step 1... it can: `--nskip` slices and DONE markers make a rerun resume) plan ~**90 node-hours**. Disk at `semiprod`: 0.96 MB/event step 2 + ~0.5 MB/event merged ≈ 1.5 TB for 1M.

### 4a. Queues and allocation (surveyed 2026-10-21)

| queue | nodes | walltime | per-user limit | note |
|---|---|---|---|---|
| debug | 1–2 | 1 h | 1 running | 14 running / 8 queued when surveyed |
| debug-scaling | 1–256 | 1 h | 1 running | 12 running / 16 queued |
| capacity | 1–16 | 168 h | 2 running (512 nodes in all) | what Avinay's "capacity" batches used |
| prod → small | **256**–1024 | 12 h | 10 queued | 1 running / 63 queued; `pbs/run-pairs.pbs` (`-q prod`, 1 node) cannot run as written |
| medium / large | 1025+ | 18 / 24 h | | |

Nodes: 208 logical CPUs (104 cores × 2), 1,056 GB, 6 GPUs; 619 free / 6989 busy when surveyed. Allocations (`sbank-list-allocations -p neutrinoGPU`, all end **2026-11-01**): `debug2` (14454, unrestricted) **303 node-hours left**; 17257 (unrestricted, Avinay's production) at **−31,740**; 16483 at −15,607; 14186 (6,725) restricted to twester. The 2 debug-node job 8944988 was charged to debug2.

## 4b. Equality of the multi-reco1 unit (job 8949403 + 8949454, the fixed build)

The eee3 unit (20 files, 44 events) as one multi-reco1 pair, and the same 20 files as 20 single pairs against the same CAF (`$Y/production-prep/bnb1m/fix2/eq-work`; `eqtest/compare-multi.py`, events keyed by run/subrun/event):

| check | result |
|---|---|
| multi unit status | **OK**: 44 of 44 CAF events merged, 0 skipped, dl_fail 0; 44 directories `pr_evt2100126_<subrun>_<event>` |
| singles | 18 PARTIAL (their 1–6 events merged, the CAF's other events `wc.valid = 0`, by design), 2 EMPTY (the 0-event files) |
| `tracking-pr.root`, multi vs single, every event | **identical**: 44 events, 811 trees, 101,085 branch comparisons, 0 differences, nothing ignored or unreadable |
| `Trun.input_file` per event | the file that holds the event, in both runs (0 mismatches): provenance survives the 20-file `lar` |
| `--nskip 10 -n 5` over the 20 files | exactly entries 10–14 of the full run (NSKIP-CHECK PASS, twice) |
| step-1 tensors by datapath | not comparable this way: a datapath carries the event ident, which collides across the single tars; the step-2 equality covers them |
| r8 reference pairs on the fixed build (default `pr_evt%1%`) | both OK / PASS; vs r8 the same expected differences as the pre-fix G4 run and nothing else (tensors 1585/1585 and 2939/2939 identical) |

Thread counts measured in these jobs (`fix2/threads.log`, `fix3/thread-names.log`): a `lar` has 1 thread while loading, then 28 (alone) to ~80 (20 running at once); `wire-cell` 25–29; apptainer `starter` 9 and `squashfuse_ll` 9 per container. All threads are unnamed, so where lar's come from is not yet known (art/TBB most likely); with `OMP_NUM_THREADS=1` already set.

## 4d. The full run (STARTED 2026-10-22 01:48 UTC on the owner's go)

- **Pair list:** `$Y/production-prep/bnb1m/full/pairs-all.tsv` = shard01–03 + batch01–09, **11,888 units / 627,205 events**, ids unique. Split round-robin by line into `pairs-A.tsv` (5,944 units / 313,538 events) and `pairs-B.tsv` (5,944 / 313,667), so both jobs get the same mix of shards.
- **Jobs:** `pbs/run-pairs-capacity.pbs`, capacity queue, allocation `debug2`, **8 nodes each**, walltime **8 h** (6 h in the proposal; 627k events over 16 nodes is 39k events per node ≈ 4.4 h at 9,000/h plus ramp, so the margin was widened; the charge is for the time used), `WC_MAXPAR=100`, `WC_KEEP=semiprod`, step-2 directories `pr_evt<run>_<subrun>_<event>`; toolkit pin d06a47d7, `$OPT` from job 8950980.
  - A: job **8952145**, WORK `$Y/production-prep/bnb1m/full/A` (`job.out`, `node<k>/{slice.tsv,pool.log,<id>/}`)
  - B: job **8952146**, WORK `$Y/production-prep/bnb1m/full/B`
- **Resume** if a job runs out of walltime or a node dies: resubmit the same `qsub` with the same PAIRS and WORK (8 nodes) — each node skips its OK/EMPTY units and resumes the rest from their DONE markers.
- **Done when:** both `job.out` end with `all pools done` and the status counts show only OK/EMPTY (PARTIAL/FAIL units get listed and looked at before any rerun); then `cost-summary.md` per WORK and the §4 cost table, the output inventory, and the deliverable paths go into this doc and issue #2.

### 4d.1 Start-up: the thread ramp broke 221 units of job A (04:46–04:48 UTC)

Both jobs started on their own after 2.9 / 3.2 h in the queue (A 04:41, B 04:58 UTC; all 8 nodes each). Five minutes into job A, **221 of the first 800 units failed** `FAIL step1 no step-1 output` (step-1 lar rc 134 = SIGABRT; `lar.log`: `runtime/cgo: pthread_create failed: Resource temporarily unavailable`), then no more failures. Cause, from `node.log` (30-s samples): a step-1 lar is **~25 tasks for its first ~90 s** (setup, single-threaded) and then jumps to **87–100 tasks per unit** (the thread pool comes up after the geometry load) — not the ~75 the smoke estimated. The pool launched 100 units 2 s apart while every one of them was still at 25 tasks (pids 2528 at 100 lar), the 400-task headroom guard saw plenty of room, and 90 s later all 100 ramped at once into the 8,192 cap: 19–38 units per node died, the survivors (81–94 per node) sit at 7,811–8,168 tasks.

Mitigation, live (05:02 UTC): `maxpar.override = 76` written into all 16 node pools (`$WORK/node<k>/maxpar.override`, re-read before every launch); the pools launch nothing new until their running count drops below 76, which puts the steady state at ~7,600 tasks (≥ 500 headroom for a few simultaneous ramps as units finish). Costs ~10 % throughput against the 85–94 per node the cap allows, buys safety for the 8-h run. Job B's ramp was already complete (100 launched, all at 25 tasks) when the override landed, so it was expected to lose a similar number at ~05:04.

Fix for the pool, drafted (not applied while 16 pools execute the script — bash reads it incrementally): a ramp-aware guard in `bin/run-pairs.sh` that counts every unit launched within the last `WC_RAMP_S` (180 s) as `WC_TASKS_PER_UNIT` (100) tasks still to come, and caps the concurrency at `(pids.max − headroom) / WC_TASKS_PER_UNIT` = 77 whatever `WC_MAXPAR` says. Applied after the jobs end, before the resume job that reruns the FAIL units (a resubmit skips OK/EMPTY and retries FAIL).

### 4d.2 Run 1 ended at walltime (12:41 / 12:58 UTC): 464k of 627k events done, 9 of 16 nodes stalled by memory

| | A (8952145) | B (8952146) |
|---|---|---|
| OK units / events | 4,149 / 218,640 | 4,652 / 245,512 |
| FAIL | 271 (221 in the ramp) | 148 (134 in the ramp) |
| PARTIAL | 112 | 27 |
| not started / killed in flight | ~1,400 | ~1,100 |
| nodes that finished their slice | 3 (node0/3/4, by 10:15 — 743 units in 5.5 h ≈ 135 units/h ≈ 7,100 events/node-hour) | 4 (node1/3/5/6, by 10:32) |

**The stall.** On 9 of the 16 nodes (A1, A2, A5, A6, A7, B0, B2, B4, B7) the pool stopped completing units for 3–4 h, starting between 06:30 and 09:15 UTC. `node.log` (30-s samples): our processes' RSS (sum over `lar`, `wire-cell`, `python3`) climbed from the usual ~110 GB at a steady **~1.1 GB/s** (A2: 110 GB at 08:14:02 → 144 at 08:14:33 → 602 at 08:23 → 1,000 at 08:31) to ~1,080 GB with `MemAvailable` ~30 GB, and stayed there until the 4-h step timeouts started killing things (A2 recovered at 12:26). The process counts did not change during the climb (A2: 61–64 lar, 7–12 wire-cell, 76 units), so it is one process, or a few, growing by ~1 GB/s — the speed of reading a file from Flare into memory.

**What it was not.** Not step 2: the largest `wire-cell` resident size in any step-2 log on A2 / B0 is 5.6 / 2.2 GB (`MEM:` lines, all units including the in-flight ones). Not a step-1 lar that reached an event: the art memory tracker's per-event rows show at most 3.2 GB — but it writes them only at job end, so the lars that were in flight at the stall left no record. The step-1 lars whose `lar.log` stops at `Geometry imported from GDML created` (two on A2 at 08:24:26, one on A7 at 09:15, …) are **victims, not the cause**: on A2 they launched at 08:19, five minutes after the climb began, and froze at their first heavy read once the node was already swapping. (The first version of this section called them the cause; corrected 2026-10-22 14:00 UTC.) The units that survived the thrash came out as step-2 segfaults (`rc 139` in the Go runtime's GC inside `wire-cell`, same on retry → PARTIAL: A5 64 in hour 12, B7 46) or step-3 / validate `rc 124` timeouts.

**So the hog is unidentified** — a `lar`, or a `python3` (merge / validate / collect), that started reading something at ~1 GB/s and kept it in memory. The sampler kept only the sum and `ssh` to a thrashing node hangs. For run 2 the driver's RSS watchdog (`WC_STEP_MAX_RSS_GB` = 48, poll 20 s, process tree from `/proc`) kills such a step at 48 GB, logs the three biggest processes of its tree (`pid comm GB`) in `run_pair.log` and writes `cost/<step>.rss_killed`; the step is then handled like a timeout (slice retry / FAIL, retried on resume). If it recurs, run 2 names it. `run-pairs.sh` additionally has the ramp-aware pids guard (commits 8e392f2, 1e4fddd). Both tested on the login node (fake 1.5 GB hog killed and named; guard arithmetic), not yet in a job.

**Run 2 found it (13:45 UTC, 7 min after start).** The RSS watchdog killed a step-1 `lar` at 54.4 GB (B node0, unit 767c…) and another at 68.7 GB (B node4) — `biggest: <pid> lar 54.5 GB`; six kills in the first 20 min. Each lar had just logged `ClusteringSeparate:apa<N>-0` for an event stamped `truth: 0 nu, 0 pf rows` with a very large cluster (`Cluster::get_hull number of points is too large: 15536–18416`), i.e. it was inside the next stage, **`ClusteringDeghost`**, and grew by ~1 GB/s (1.6 GB → 54 GB in under a minute — the run-1 climb rate). So run 1's hogs were step-1 lars in ClusteringDeghost on such events; left alone one reaches 1 TB in ~17 min and takes the node down. All six skipped events so far have no neutrino truth (`0 nu`): 2110173/11/10, 2105404/87/10, 2105189/95/9, 2110430/76/8, 2110302/66/6, 2105311/35/5. **For the toolkit owner.** The driver's response is the normal one for a bad event: skip it (`skipping event index k rse (...)`, listed in `events.json: skipped`), rerun the rest of the unit, unit = PARTIAL; the full list of skipped events will be in the final report so they can be reprocessed once the clustering is fixed.

**Run 2 (resume), submitted 13:03 UTC:** jobs **8953303** (A) and **8953304** (B), same PAIRS/WORK, 8 nodes × **4 h** (short walltime backfills within ~1–3 h; ~3,100 units ≈ 165k events ≈ 1.5 h on 16 healthy nodes), `WC_RETRY_PARTIAL=1` (the PARTIALs are node-condition artefacts, not data), `maxpar.override` files removed (the new cap of 77 applies). The 8-h run-1 outputs stay in place; the resume skips OK/EMPTY units and resumes the rest from their DONE markers.

### 4d.3 DONE 2026-10-22 17:58 UTC: 11,888 units, 627,205 events, 627,127 with Wire-Cell output

| | A | B | total |
|---|---|---|---|
| units OK / PARTIAL / FAIL | 5,935 / 9 / 0 | 5,935 / 9 / 0 | 11,870 / 18 / 0 |
| merged CAFs written | 5,944 | 5,944 | 11,888 |
| CAF events | 313,538 | 313,667 | **627,205** |
| events with `recTreeWireCell` | 313,518 | 313,609 | **627,127** (99.988 %) |
| events without | 20 | 58 | 78: 13 skipped in step 1 (ClusteringDeghost), 65 lost to the step-2 segfaults of run 1's stalled nodes (units PARTIAL after retry) |
| node-hours charged (debug2) | 64.3 + 32.2 | 64.2 + 29.8 | **190.6** (+0.1 tail); debug2 has 92.7 left |
| wall | run 1 8 h × 16 nodes (04:41–12:58), run 2 ~3.5 h × 16 (13:38–17:38), tail 7 min × 1 | | 13.3 h end to end from the first start, 16.2 h from submission |

Steady-state cost per event (cost-summary.md, both halves alike): step 1 **34 s wall / 31 s CPU**, RSS median 1.6 GB (max 6.4 GB), 8.4 MB of step-1 output; step 2 4.7–5.9 s wall, 1.4 GB; merge 0.15 s; validate 0.8 s. Per node at 77 units: ~7,000–8,000 events/node-hour when nothing stalls. The real cost was twice the plan because of run 1's nine stalled nodes.

**Outputs** (`WC_KEEP=semiprod`): `$Y/production-prep/bnb1m/full/{A,B}/node<k>/<unit>/merged/*.root` (the flat CAF with the `recTreeWireCell` branches; 11,888 files), `pr/all/` (per-event `pr_evt<run>_<subrun>_<event>/tracking-pr.root` + `mabc-pr.zip`, `wct.log.gz`), `events.json`, `cost.tsv`; `cost-summary.md` per half; `skipped-events.tsv` (the 13 below); `jobs.txt`. Disk at semiprod: 0.89 TB per half (du 18:15 UTC), **1.78 TB** for the 627k events ≈ 2.9 MB/event, of which the 11,888 merged CAFs are 386 GB (193 GB per half, 32 MB each) (step-1 tars 8.4 MB/event are removed, the step-2 per-event files 0.84 MB + merged CAF 0.67 MB + Bee zips/logs kept).

**The 13 events the toolkit cannot cluster** (step-1 lar killed by the RSS watchdog at 48 GB inside `ClusteringDeghost`, all `truth: 0 nu`; rc 137 = killed; `$Y/production-prep/bnb1m/full/skipped-events.tsv`):

| run | subrun | event | half | unit (reco2-reco1-detsim-g4-gen-…) | index in unit |
|---|---|---|---|---|---|
| 2100197 | 23 | 5 | A | -gen-c66b-68d3-da48-f711 | 36 |
| 2100465 | 19 | 8 | A | -gen-14e7-4cfa-8ed6-9be8 | 38 |
| 2105189 | 95 | 9 | A | -gen-476a-f511-0adf-2efc | 21 |
| 2105252 | 60 | 9 | B | -gen-e5fd-0f26-795a-bfd9 | 58 |
| 2105311 | 35 | 5 | B | -gen-e5e0-ceac-2a9a-ec50 | 28 |
| 2105404 | 87 | 10 | B | -gen-e3e0-3290-8946-ca65 | 16 |
| 2110053 | 20 | 3 | A | -gen-e588-8e0c-a689-da26 | 43 |
| 2110173 | 11 | 10 | B | -gen-767c-03db-5015-665f | 5 |
| 2110302 | 66 | 6 | B | -gen-6aef-1095-71f7-d0a3 | 32 |
| 2110430 | 76 | 8 | A | -gen-c673-66bc-2e23-5890 | 25 |
| 2110585 | 82 | 2 | B | -gen-31ba-8720-e633-8a0e | 56 |
| 2110649 | 26 | 10 | B | -gen-e643-6b8f-590d-2076 | 5 |
| 2110746 | 95 | 3 | A | -gen-07ff-0767-90d5-5d0d | 12 |

Reprocess them (and the 65 step-2 losses, listed per unit in `events.json`) once the clustering is fixed: `run_pair.py --nskip <index> -n 1` on the unit, or a full rerun of the 18 PARTIAL units with `WC_RETRY_PARTIAL=1`.

**Lessons recorded in the guide / code:** ramp-aware pids guard (`run-pairs.sh`), RSS watchdog (`run_pair.py`), `rse_of_flat` on truncated files (`wcflat.py`), the `TensorFileSource` equal-ident fix and `per_event_name` in the toolkit (pin d06a47d7), short walltimes backfill (35 min vs 3 h), one pool per node with resume by resubmission works (run 2 picked up 2,500 units and 437 failures with no manual bookkeeping), Lustre metadata on the UAN is slow enough that status sweeps over 12k units take minutes.

## 4c. Proposed parameters for the full run (as reviewed; superseded by 4d)

- **Unit and layout:** multi-reco1 units from the sidecars (7,861 units / 414,774 events in the 7 directories with CAFs now; ~620k when shard03's CAFs land), `WC_KEEP=semiprod`, step-2 directories `pr_evt<run>_<subrun>_<event>`.
- **Per node:** `WC_MAXPAR=100` (one per core; the cgroup's 8,192 tasks allow ~100 step-1 units; memory 153 GB of 1.1 TB), `WC_PIDS_HEADROOM=400`, `WC_STEP1_MAX_BAD` default 3 (a bad event costs one slice rerun of ≤ 50 events).
- **Throughput:** 9,000 events per node-hour → 620k events ≈ 69 node-hours steady state, **plan 90 node-hours** (3.5 min ramp per node, 35-min units leave a tail; a killed unit resumes from its DONE markers).
- **Queue:** `capacity` (1–16 nodes, ≤ 168 h, 2 running jobs per user; today's three 1-node capacity jobs started within 1–10 min; `prod` cannot take < 256 nodes). Two jobs of **8 nodes × 6 h walltime**, each node running its own `run-pairs.sh` over a 1/16 slice of the pair list (~490 units, ~26k events, ~3 h at 9,000/h, the rest is margin). That needs a multi-node launcher (`mpiexec -ppn 1` / `pbsdsh` of one pool per node) — not written yet; a 2-node × 15-min test first.
- **Allocation:** `debug2` (303 node-hours left on 2026-10-21, unrestricted) covers it; `17257` is at −31,740 node-hours. Everything ends 2026-11-01.
- **Disk:** ~1.5 MB/event kept at semiprod (0.96 MB/event step-2 files + the merged CAFs) ≈ 1 TB for 620k; 83 TB free on Flare.
- **Open items before the run:** (1) ~~the toolkit fix commit~~ done 2026-10-21: `sbnd-wc-flatcaf` d8e00500 (per_event_name) then **d06a47d7** (TensorFileSource) on the fork — d06a47d7 is the toolkit pin for this production, `$OPT` built from it (job 8950980); (2) ~~shard03's CAFs~~ complete (3,772 CAFs, exclusions finalised 2026-10-20), and batch06–09 have CAFs too, shard04 is running; (3) whether to chase lar's ~80 threads to reach 200 workers per node (hyperthreads; worth maybe 20–30 %, not needed for 90 node-hours); (4) the multi-node launcher `pbs/run-pairs-capacity.pbs` + `pbs/node-pool.sh` (one pool per node over a round-robin slice, `mpiexec -ppn 1`): 2-node test job on 12 units / 528 events (`$Y/production-prep/bnb1m/mn2`).

### 4c.1 Multi-node launcher test and the second ident bug (2026-10-21 18:17 UTC, job 8950826)

`pbs/run-pairs-capacity.pbs` + `pbs/node-pool.sh`: 2 capacity nodes (started 3 min after submission), 12 shard01 units / 528 events split round-robin, `WC_MAXPAR=6` per node. Both pools ran (`nodes.log`), the combined cost summary works, 23 min. Per-unit step 1 at 6 workers: 23.7–24.4 s/event (CPU 19–20 s), step 2 2.7–2.8 s/event, RSS 1.6 / 1.4 GB.

But only 3 of 12 units were OK: 9 PARTIAL with 1–3 of 44 events missing from step 2 (no failure anywhere: step 1 wrote all 44 tensor sets, dl_fail 0). The missing events are exactly those **immediately followed by an event with the same event number** (e.g. subrun 76 event 8 then subrun 75 event 8): `TensorFileSource` grouped tar members by ident alone, so a second set with an equal ident silently replaced the first. The eee3 unit had no consecutive duplicates, which is why the equality test passed. Fix: the reader starts a new set at every `tensorset_<ident>_metadata.json` member (`sio/src/TensorFileSource.cxx`, doctest `sio/test/doctest_tensorfilesource_dup_ident.cxx`; behaviour unchanged when idents are unique). Job 8950980 (capacity, 2 nodes): rebuild, rerun step 2 of the 9 units through the launcher (resume path), then the r8 reference pairs.

**Result (job 8950980, 19:01–19:21 UTC):** rebuild OK (doctests sio dup-ident and clus per_event_name green); the launcher's resume path reran step 2 of the 9 units on 2 nodes → **12 of 12 OK, 44/44 events each**; the r8 reference pairs OK/OK on this build and, value by value against r8, exactly the known expected differences and nothing else (tensors 1585/1585 and 2939/2939 identical; only `wct_version`, `T_dlvtx_call.payload`, the info note, `input_file` ignored). Toolkit commit on the fork: `sbnd-wc-flatcaf` **d06a47d7** (the pin for the production; `$OPT` built from it).

Expected rate of such pairs: with 10 event numbers per subrun and ~2.6 events per file, roughly 1 in 10 consecutive event pairs collide → ~2–3 % of events, as seen (12 of 528).

## 5. Log

- 2026-10-19: pins checked out, uproot installed, reference md5 OK, job 8944988 (build + G4) submitted 04:11 UTC; the sample inventoried (section 3); the 20-parents finding → question to the owner.
- 2026-10-19 04:36 UTC: job 8944988 done, both pairs OK / PASS / dl_fail 0; compare vs r8: G4 PASS (section 2). Waiting for the owner's decision on the multi-reco1 unit before the smoke.
- 2026-10-21: owner: multi-reco1 unit, smoke as several ~100-event debug jobs to size the full run (~620k events now), then propose parameters and wait. Implemented (section 3); equality test job 8949305 (debug, 1 node): the eee3 unit (20 files, 44 events) as one multi-reco1 pair plus the same 20 files as single pairs against the same CAF, WC_MAXPAR 21, plus a `--nskip 10 -n 5` step-1 run over the 20 files (must give entries 10–14 of the multi run). Queue / allocation survey (section 4a).
- 2026-10-21 03:37 UTC: job 8949305 done in 23 min. Step 1 ran all 44 events as one `lar` (rc 0, 23.5 s/event, RSS 1.6 GB), the `--nskip 10 -n 5` run gave exactly entries 10–14 of the full run (NSKIP-CHECK PASS), the 2 empty files gave EMPTY as singles and were skipped silently inside the multi unit — but the multi unit came out PARTIAL with 10 of 44 events. **Cause: Wire-Cell names an event by its set ident = the art event number alone**, and in this sample the event numbers restart at 1 in every subrun (gen makes 10 per subrun), so the 44 events of one unit share 10 idents. Step 1 wrote all 44 tensor sets (duplicate member names in the tar), step 2 processed all 44 (44 `recTreeWireCell` written, 44 events in the Bee zip) but wrote them into 10 `pr_evt<ident>` directories, each later event overwriting the earlier one. Fix (toolkit, uncommitted on `sbnd-wc-flatcaf`, for the owner to review): `Clus::per_event_name` (`clus/{inc,src}/PerEventName`), one helper for every per-event writer (both SBND tracking visitors, the tagger output, the flat tree, PrDisplayDump, the MABC's own Bee zip) that expands `{run}`, `{subrun}`, `{event}`, `{ident}` tokens before the boost::format of the ident; the default `pr_evt%1%` is untouched (r8 layout byte-identical), `run_pair.py` sets `WC_EVT_SUBDIR=pr_evt{run}_{subrun}_{event}` for multi-reco1 units and `step2.sh` passes it as `evt_subdir`. Doctest `clus/test/doctest_per_event_name.cxx`. Job 8949354 (capacity queue, 1 node): waits for the smoke jobs (they run the installed libraries), rebuilds the toolkit incrementally, reruns the equality test, then the r8 reference pairs with the default layout.
- 2026-10-21 04:20 UTC: smoke jobs done (section 4): 9,000 events per node-hour at 100 workers; the cgroup pids.max = 8192 wall found (not memory, not cores). 04:24: job 8949354 rebuilt the toolkit with the fix (WCB_RC 0, doctests clus per_event_name 9/9, root 12/12) but its equality test died because `run-pairs.sh` was edited (the pids guard) while that bash was running it — resubmitted as 8949403 (`fix2`, capacity queue): equality test + nskip check + the r8 reference pairs, with an in-job task/thread sampler.
- 2026-10-22 17:58 UTC: **production complete** (4d.3): 11,870 OK + 18 PARTIAL, 627,127 of 627,205 events with Wire-Cell output, 190.6 node-hours. Run 2 ended 17:29 (A) / 17:05 (B); the 3 collect-bug units redone in a 7-min debug job (8954111).
- 2026-10-22 14:20 UTC: run 2 running since 13:38 (8 + 8 nodes, 35-min queue wait); the ramp guard held (77/node, 0 pthread failures); the RSS watchdog identified the hog: step-1 lar in `ClusteringDeghost` on 0-nu events with huge clusters, ~1 GB/s (4d.2). `wcflat.rse_of_flat` fixed for truncated step-2 files (3 units failed the resume in 15 s; rerun in the tail).
- 2026-10-22 13:03 UTC: run 1 ended at walltime with 464k events OK; 9 nodes had stalled 3–4 h on a ~1 GB/s memory climb to 1.08 TB by an unidentified process (4d.2; the GDML-frozen lars are victims, wire-cell is exonerated). Pool guard + RSS watchdog committed (8e392f2); resume jobs 8953303/8953304 (8 × 4 h each, retry PARTIAL) queued.
- 2026-10-22 05:02 UTC: jobs running since 04:41 (A) / 04:58 (B). A lost 221 units in the thread ramp (section 4d.1); live `maxpar.override = 76` on all 16 pools; ramp-aware guard drafted for the resume job.
- 2026-10-22 01:48 UTC: **full run started** on the owner's go: jobs 8952145 (A) and 8952146 (B), 8 capacity nodes × 8 h each, 5,944 units apiece (section 4d).
- 2026-10-21 19:22 UTC: job 8950980 done: 12/12 OK after the reader fix, r8 pairs OK/OK; toolkit d06a47d7 pushed to the fork; pair lists complete: **11,888 units / 627,205 events** (shard01–03, batch01–09). Ready for the full run on the owner's go.
- 2026-10-21 18:41 UTC: launcher test done (section 4d): launcher OK, but 9 of 12 units PARTIAL → the tar reader's ident grouping; fixed, rebuild + rerun job 8950980. Pair lists: shard03 running, batch06–09 done (255 units, 13,480 events).
- 2026-10-21 ~06:00 UTC: owner: commit and push the toolkit fix to the fork (done, d8e00500), allocation debug2 agreed, check shard03 (complete), write and test the multi-node launcher (test job submitted). Pair lists for shard03 and batch06–09 being built.
- 2026-10-21 05:12 UTC: job 8949403 (29 min): equality test on the fixed build still PARTIAL — `WC_EVT_SUBDIR` never reached the container (`apptainer --cleanenv`; `PASS_ENV` now forwards it, `in-aurora-sl7.sh` forwards only set variables), NSKIP-CHECK PASS, r8 reference pairs OK/OK. Job 8949454 (step 2 of the multi unit again): **OK, 44/44**. Comparisons on the UAN: multi vs singles identical on every branch (section 4b); r8 reference pairs vs r8: the expected differences only. Driver changes committed (b439630). Proposal in section 4c; waiting for the owner.
- 2026-10-21 03:40 UTC: sizing smoke jobs started on the pre-fix build (step-1 numbers unaffected; the step-2 directories collide): 8949343 `s104` (debug-scaling, 104 units of 32–41 events = 4,013 events, WC_MAXPAR 104) and 8949344 `s208` (debug, 208 units of 41–44 events = 8,854 events, WC_MAXPAR 208), both 1 node, 59 min, WC_KEEP semiprod, `node.log` sampler. Pair lists: `$Y/production-prep/bnb1m/pairs/shard01.tsv` (3,771 units, 198,803 events, 0 skipped, 29 min to build on Lustre); the other directories are being listed.

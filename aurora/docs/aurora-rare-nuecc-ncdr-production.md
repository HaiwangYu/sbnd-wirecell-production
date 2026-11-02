# Aurora production: nueCC 269k + NC delta-radiative 27k (gen2 configL v10_14_02_05, Avinay, 2026-11)

Tracking doc for running the r8 chain ([`aurora-r8-chain.md`](aurora-r8-chain.md)) on Aurora over Avinay's validated nueCC and NC delta-radiative samples, the way the BNB 1M was run ([`aurora-bnb-1m-production.md`](aurora-bnb-1m-production.md), issue #2). GitHub: HaiwangYu/sbnd-wirecell-production issue #3.

Steps (owner, 2026-11-02): (1) issue + doc; (2) a smoke on both samples to size the run; (3) the running plan to the owner for review and approval; (4) the run on the owner's go.

## 1. The samples (Avinay, 2026-11-01)

Both are `prodgenie_corsika_proton_rockbox0p1_sbnd` gen + `run_sbnd_gen2_rare_signal_filter.fcl` (output stream `outnuecc` / the NC delta-rad stream) + rockbox g4 + standard detsim / reco1 / reco2 + `cafmakerjob_sbnd_sce_systtools_and_fluxwgt_and_g4rw.fcl`, sbndcode **v10_14_02_05** (`runinfo/config.toml`; `wct_guard_expect`: wirecell v0_32_1, larwirecell v10_01_26_01 for Avinay's reco1 stage). Avinay: "better to use the file lists so as not to include the bad files" -- the units come from the validated lists only, nothing is taken from the directories themselves.

| sample | directory (`/lus/flare/projects/neutrinoGPU/abhat/sbnd/`) | validated events | reco1 / flat-CAF files | validated lists |
|---|---|---|---|---|
| nueCC | `gen2-sbnd-ccnue-configL-300k-reco1-flatcaf-v100205-wct0319-20261027` | 268,865 | 62,050 / 62,050 | `gen2-ccnue-review-20261023/phaseC_result_20261031/ccnue_validated_{reco1,flatcaf}_files.txt` (2026-11-01 01:44) |
| NC delta-radiative (train) | `gen2-sbnd-ncdeltarad-train-configL-reco1-flatcaf-v100205-wct0319-20261029` | 26,745 (5.487e21 POT) | 29,779 / 29,779 | `ncdeltarad-review-20261029/train/result_8986828/ncdr_validated_{reco1,flatcaf}_files.txt` (2026-11-01 15:26) |

Layout: `reco1/NNNNNN/NNNNNN/reco1-detsim-g4-filter-gen-<id>.root` (+ `.json` sidecar with `event_count`, `first_event`, `last_event`, `runs`), `flatcaf/NNNNNN/NNNNNN/reco2-reco1-detsim-g4-filter-gen-<id>.flat.caf.root` (+ `.json`, `parents` = the one `reco2-reco1-...-<id>.root`), also `caf/` (the non-flat CAFs), `filter/`, `logs/`.

**Structure, unlike the BNB 1M:** `subruns_per_caf = 51` and the rare-signal filter leave one reco1 per CAF (one parent in every CAF sidecar), so the workflow's native one-CAF-per-reco1 pairing applies: **unit = 1 reco1 + 1 flat CAF**, ids match by name (`reco1-X.root` <-> `reco2-reco1-X.flat.caf.root`). The units are small: nueCC 4.3 events per file on average (0-12), NC 0.9 (39 % of the NC files hold 0 events and are `EMPTY` units: nothing runs, the CAF is left as is). A step-1 `lar` spends ~90 s in setup before its first event (the BNB units amortised that over ~53 events); the smoke measures what a 1-4-event unit costs.

Pairing: `bin/find-pairs.py --reco1-list <validated reco1 list> --caf-list <validated CAF list> --reality sim` (path mode, new `--caf-list`; the events column is the reco1 sidecar's `event_count`). Both lists pair 1:1 (0 skipped on the smoke subsets).

## 2. State on 2026-11-02

| item | state |
|---|---|
| toolkit | `sbnd-wc-flatcaf` **d06a47d7** (the BNB 1M pin: r8 + `per_event_name` + the `TensorFileSource` equal-ident fix), `cfg/` clean |
| larwirecell | `sbnd-wc-flatcaf` `ad5d942` |
| `$OPT` | the BNB 1M build (job 8950980, 2026-10-21; `libWireCellSio.so` 19:04) on sbndcode `v10_14_02_03` from the Flare UPS tree -- the new reco1 were written by `v10_14_02_05`; the smoke checks that step 1 reads them |
| this repo | `main` 8f28e2a + this campaign's changes (section 4) |
| allocation | `debug2` ended 2026-11-01. **17779** (2026-11-01 to 2027-07-01), 235,000 node-hours, one primary unrestricted suballocation (no subname) -> `-A neutrinoGPU`; the PBS scripts default to it now |
| Flare | project quota 3.50 of 3.76 PB soft (4.13 hard): ~260 TB free |
| capacity queue (2026-11-02 04:05 UTC) | 57 running / 54 queued / 21 held; debug 8 / 4 |

## 3. Smoke (submitted 2026-11-02 04:10 UTC)

Capacity queue, 1 node each, `pbs/run-pairs-capacity.pbs` (`select=1`), `WC_MAXPAR=100` (-> the pids cap of 77), **`WC_RAMP_S=0`**, **`WC_LAUNCH_GAP_S=1`**, `WC_KEEP=semiprod`, allocation 17779. `$Y/production-prep/rare/{nuecc,ncdr}/smoke-pairs.tsv`, WORK `.../smoke`, `smoke-job.out`.

| | nueCC (job **9031754**, 1:45 walltime) | NC delta-rad (job **9031755**, 1:00) |
|---|---|---|
| units | every 50th line of the validated list: 1,241 units | every 25th line: 1,192 units |
| events | 5,448 (10 units with 0, 64 with 1, 163 with 2, 217 with 3, 241 with 4, 203 with 5, 154 with 6, 84 with 7, 60 with 8, 25 with 9, 20 with 10-12) | 1,094 (469 units with 0, 458 with 1, 184 with 2, 61 with 3, 20 with 4-6) |
| expected if a unit costs 90 s + 40 s/event | ~70 min at 77 workers | ~35 min (launch-limited at 1 unit/s) |

Why `WC_RAMP_S=0`: the pool counts every unit launched in the last `WC_RAMP_S` (180) s as 100 tasks still to come; with 2-4-minute units every running unit is "ramping" and the term would hold the node at ~40 units. The cap (`(pids.max - 400) / 100` = 77) alone is what held the BNB run 2 at 0 pthread failures; it stays. Why the 1-s gap: 77 workers on ~2-minute units need ~0.6 launches/s; the default 2 s would cap a node at 30 units/min.

What the smoke must tell us: (a) step 1 reads `v10_14_02_05` reco1 (status OK, `validate.json` PASS, `dl_fail` 0); (b) the per-unit wall and CPU with 1-4 events per `lar` -> the cost per event and the node-hours for 62k + 30k units; (c) whether 1-s launches of apptainer hold on a node (the container start reads the `.sif` from Flare); (d) the step-2 crash rate on nueCC (FNAL: ~1 per 550 events, retried once; a deterministic one leaves the event out -> PARTIAL); (e) RSS per step (the watchdog at 48 GB stays on; the BNB `ClusteringDeghost` hog was on 0-nu events).

### 3a. Smoke results (both jobs ran to their walltime, 2026-11-02 04:32-06:41 UTC)

| | nueCC (9031754: 44 min queue, 04:54-06:41, killed at 1:45) | NC delta-rad (9031755: 22 min queue, 04:32-05:33, killed at 1:00) |
|---|---|---|
| finished / in flight / not started | 1,051 / 77 / 113 of 1,241 | 930 / 77 / 185 of 1,192 |
| OK / PARTIAL / EMPTY / FAIL | 990 / **53** / 8 / 0 | 542 / 4 / 384 / 0 |
| throughput per node | **593 units/h, 2,568 events/h** | 923 units/h, 795 events/h |
| unit wall (fit over the OK/PARTIAL units) | **156 s + 67 s x events**; median 406 s at 4 events | 381 s + 36 s x events; 1-event units 395 s, EMPTY units 53 s |
| step 1 | 33 s + 36 s x events; 40 s wall / 39 s CPU per event; RSS 1.5 GB (max 2.8) | a 1-event unit: 267 s wall / 82 s CPU; RSS 1.5 GB (max 2.5) |
| step 2 / 3 / validate per event | 26 s / 1.2 s / 2.6 s; RSS 1.3 GB (max 3.0) | 26 s / 8 s / 10 s |
| precheck container (`count-events`) | 4.7 s median, 48 s max | 9.4 s median, 48 s max |
| outside any container per unit (apptainer start + UPS setup, 5 containers) | 94 s | 270 s |
| node | our RSS 114 GB, load 82, pids 6,542 of 8,192; 77 lar | 111 GB, 83, 7,589; 77 lar |
| watchdog kills | 0 | 0 |
| step-2 crashes | 12 x rc 139 (1 per 450 events; 11 recovered on the retry, 1 died again rc 134 -> PARTIAL) + 1 incomplete file | 0 |

The step-1 reads of `v10_14_02_05` reco1 work (status OK, dl_fail 0 everywhere). The ramp-free guard (`WC_RAMP_S=0`) and the 1-s launch gap held: 77 units per node, pids <= 7,589, 0 pthread failures.

**Finding 1 -- 51 of the 53 nueCC PARTIALs and all 4 NC ones are the event-number collision.** Each has exactly one CAF event without Wire-Cell output and no failure anywhere: e.g. unit `00b3-84d7` holds subrun 43 event 50 and subrun 87 event 50, step 2 wrote both to `pr_evt50` and the second overwrote the first. Single-file units kept the r8 layout `pr_evt<event>`; the event numbers restart per subrun in every gen2 sample, and a file of ~5 events from up to 51 subruns repeats one ~5 % of the time (the 20-subrun BNB units had the same problem and already used the run/subrun/event layout). Fix: `run_pair.py` now defaults every unit to `WC_EVT_SUBDIR=pr_evt{run}_{subrun}_{event}`; `pbs/build-and-g4.pbs` sets `pr_evt{ident}` so the G4 comparison with r8 keeps its layout (`compare-outputs.py` keys on the directory name).

**Finding 2 -- the cost is the start-ups, not the events.** A unit runs 5 containers (precheck, step 1, step 2, merge, validate), each paying apptainer + the UPS `setup` (~20-50 s under load) and then its own program start-up: a step-1 `lar` took **277 s to reach its first event** (`lar.log`: container start 04:33:39, first `OpHitSource` 04:38:16) against ~90 s in the BNB run, because 77 lars per node now start every few minutes and contend for the same library / fcl / geometry / model loads from Flare (CPU 82 s of a 267 s step). The BNB units amortised one start-up over 53 events; here it is over 4.3 (nueCC) or 0.9 (NC). Per event that is 40 s of step-1 compute plus ~110 s of start-ups.

**At the smoke rates the full samples cost:** nueCC 62,050 / 593 = **105 node-hours**, NC 29,779 / 923 = **32 node-hours**; 137 in all (235,000 available). Cheap reductions, applied for the confirmation job: (a) `WC_TRUST_EVENTS=1`: the event count comes from the pair list (the sidecar) instead of a container -- one container start less per unit, and an EMPTY unit (12,175 of the NC units) costs nothing; (b) nothing else. Expected ~75 + ~22 = ~100 node-hours. Bigger reductions need design work and are the owner's call (section 6).

**Inventory of the full samples** (`sidecar-sweep.py`, 2 h on the UAN):

| | units | events | empty units | events per unit | reco1 on disk | flat CAFs on disk |
|---|---|---|---|---|---|---|
| nueCC | 62,050 | 268,865 | 798 | 0: 798, 1: 3,539, 2: 7,704, 3: 11,016, 4: 11,903, 5: 10,320, 6: 7,577, 7: 4,628, 8: 2,538, 9: 1,230, 10-15: 797 | 6.66 TB (107 MB per file) | 0.29 TB (4.7 MB) |
| NC delta-rad | 29,779 | 26,745 | 12,175 | 0: 12,175, 1: 10,889, 2: 4,814, 3: 1,473, 4-7: 428 | 0.67 TB (22.5 MB) | 0.07 TB (2.4 MB) |

### 3b. Confirmation job 9032035 (debug, 1 node, 59 min; submitted 06:57 UTC)

505 units / 1,541 events / 87 empty into `$Y/production-prep/rare/confirm/work`: the 53 PARTIAL nueCC units (must come out OK with the run/subrun/event layout), 200 unrun nueCC units and 300 unrun NC units (the cost without the precheck container, `WC_TRUST_EVENTS=1`); otherwise the smoke settings.

## 4. Workflow changes for this campaign (this repo)

- `bin/run_pair.py`: the per-event directory layout `pr_evt{run}_{subrun}_{event}` is the default for every unit (finding 1); `WC_TRUST_EVENTS=1` takes a single-file unit's event count from the pair list (`WC_PAIR_EVENTS`, exported by `run-pairs.sh` from the 5th column) instead of the precheck container.
- `pbs/build-and-g4.pbs`: `WC_EVT_SUBDIR=pr_evt{ident}` for the r8 comparison.

- `bin/find-pairs.py`: path mode takes `--caf-list <file>` as well as `--caf-dir`, and fills the events column from `<reco1>.json` `event_count` when there is a sidecar.
- `bin/run-pairs.sh`: `WC_LAUNCH_GAP_S` (default 2) = the seconds between launches; the header explains `WC_RAMP_S=0` for short units.
- `pbs/*.pbs`: `#PBS -A neutrinoGPU` (17779) instead of `neutrinoGPU::debug2`.
- `$Y/production-prep/rare/sidecar-sweep.py`: the inventory of both samples from the sidecars (`{nuecc,ncdr}/inventory.tsv`: id, reco1 events, reco1 MB, CAF MB).

## 5. Log

- 2026-11-02 07:00 UTC: both smokes ran to their walltime: nueCC 593 units/h/node (2,568 events/h), NC 923 units/h (795 events/h): the start-ups dominate (3a). 51 + 4 PARTIALs are the event-number collision in the single-file layout -> run/subrun/event layout for every unit; `WC_TRUST_EVENTS=1` drops the precheck container. Confirmation job 9032035 (debug) queued with both; the plan (section 6) goes to the owner after it.
- 2026-11-02 04:10 UTC: samples inspected (1:1 pairing, small units), allocation found (17779), workflow changes above, smoke lists built (29 s each from the lists), smoke jobs 9031754 (nueCC) and 9031755 (NC) queued in capacity; issue #3 opened. Sidecar inventory of both full samples running on the UAN.

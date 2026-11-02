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

## 4. Workflow changes for this campaign (this repo)

- `bin/find-pairs.py`: path mode takes `--caf-list <file>` as well as `--caf-dir`, and fills the events column from `<reco1>.json` `event_count` when there is a sidecar.
- `bin/run-pairs.sh`: `WC_LAUNCH_GAP_S` (default 2) = the seconds between launches; the header explains `WC_RAMP_S=0` for short units.
- `pbs/*.pbs`: `#PBS -A neutrinoGPU` (17779) instead of `neutrinoGPU::debug2`.
- `$Y/production-prep/rare/sidecar-sweep.py`: the inventory of both samples from the sidecars (`{nuecc,ncdr}/inventory.tsv`: id, reco1 events, reco1 MB, CAF MB).

## 5. Log

- 2026-11-02 04:10 UTC: samples inspected (1:1 pairing, small units), allocation found (17779), workflow changes above, smoke lists built (29 s each from the lists), smoke jobs 9031754 (nueCC) and 9031755 (NC) queued in capacity; issue #3 opened. Sidecar inventory of both full samples running on the UAN.

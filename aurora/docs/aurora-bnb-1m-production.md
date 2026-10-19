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

## 4. Sizing (to fill after G4 gives the Aurora s/event)

1M events × s/event ÷ 100 slots per node = node-hours; disk at `semiprod` ~3.5 MB/event = ~3.5 TB for 1M (4 % of the free quota).

## 5. Log

- 2026-10-19: pins checked out, uproot installed, reference md5 OK, job 8944988 (build + G4) submitted 04:11 UTC; the sample inventoried (section 3); the 20-parents finding → question to the owner.

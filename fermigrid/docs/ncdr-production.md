# ncdr: MC NC Δ-radiative on FermiGrid, with the fg1 configuration

- Tracking: [sbnd-wirecell-production #6](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/6). The same configuration as fg1 ([#1](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/1)) and run3bnb ([#5](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/5)).
- **Status:** submitted 2026-11-09 11:42 CST, cluster `87460684@jobsub01`, 158 jobs.

## The sample

| | |
|---|---|
| reco1 | `aurora_SBND2026A_gen2_BNBLight_prodgenie_corsika_proton_rockbox0p1_sbnd_EX_ncdeltarad_v10_14_02_05_reco1_sbnd`: 16,505 files (sbndcode `v10_14_02_05`, a filter on generated subruns of 12,500 events) |
| flat CAF | `..._EX_ncdeltarad_v10_14_02_05_flat_caf_sbnd`: 15,777 files; CAF `<reco1 dir with /reco1/ → /caf/>/reco2-<stem>.flat.caf.root` |
| pairs | **15,776**, all ONLINE (`make-pairs-bulk.py --relation name`, 2026-11-09); 729 reco1 files have no CAF (`pairs-ncdr.tsv.skipped`) |
| events | **13,772**: every CAF read (`fg2/event-list.py`). They agree with SAM's `event_count` file by file; files without a SAM count are exactly the empty ones |

**Events per file:**

| events per file | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| files | 6,626 | 5,721 | 2,487 | 740 | 163 | 31 | 6 | 2 |

- **Empty files:** run anyway (owner, 2026-11-09). They end as `EMPTY` in a few seconds, with a `.done` marker.
- **Labels:** no run/subrun/event label is repeated across files.
- **Not the Aurora sample:** Aurora's NC Δ-radiative training campaign (prod#3) used Avinay's private sample on Flare, not this SAM definition.
- **Lists:** `/exp/sbnd/data/users/yuhw/production-prep/fermigrid-dev/ncdr/`: `pairs-ncdr.tsv` (+ `.skipped`), `events-ncdr.tsv.gz` (every event: run, subrun, event, CAF), `make-pairs.sh`.

## Configuration

The fg1 configuration, as for run3bnb:
- **Code:** tarball `fermigrid-dev/tar/wcgrid-ncdr.tar.gz` = `wcgrid-run3bnb.tar.gz` (md5 `db37e862f147`): toolkit `4b6853d4`, larwirecell `ad5d942`, workflow `c93da2c`.
- **Chain (MC):** step 1 → step 2 with the DL-vertex dump, the flat tree and the truth match → merge → validation.
- **Job:** `WC_KEEP=semiprod`, **100 pairs per job** (the files hold ~0.9 events on average), 1 CPU, 4000 MB + auto-release, 6 GB, 6 h, onsite.
- **Output:** `/pnfs/sbnd/scratch/users/yuhw/prod-fermigrid/ncdr/mc-ncdr/<id>/`; the merged CAFs are copied to persistent `prod-fermigrid/ncdr/` at the end.

## Smoke test and estimate

**Emulated worker (2026-11-09), one job of 12 pairs: 6 with 1–3 events, 6 empty.**
- 6 `OK`, 10 / 10 events with Wire-Cell output; 6 `EMPTY` in 3 s each.
- A one-event pair takes 60 s: step 1 27 s, step 2 16 s (with the DL-vertex load), merge + validate 4.5 s, plus the event count and setup.
- Outputs ~5 MB per event; a merged CAF ~3 MB.

**Estimate:**

| | |
|---|---|
| CPU | ~95 s per non-empty pair on the grid (×1.2 local) × 9,150 + ~15 s × 6,626 empty → **~270 core-hours** |
| jobs | 158 × ~1.7 h; ~2 h elapsed |
| input read | ~470 GB (27.5 MB reco1 + 2.5 MB CAF per pair) |
| output | ~70 GB on scratch; ~27 GB of merged CAFs (9,150) on persistent |

## Log

- 2026-11-09:
  - Pairs made; events counted (13,772); smoke test passed.
  - Owner: include the empty files, submit.
  - Submitted at 11:42 (cluster `87460684@jobsub01`, 158 jobs). All 158 showed held for a moment (jobsub attaching credentials), then idle.

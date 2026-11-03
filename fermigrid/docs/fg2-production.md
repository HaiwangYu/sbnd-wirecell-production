# fg2: a second FermiGrid production, disjoint from fg1

fg1: [#1](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/1). No fg2 issue was opened.

> **PAUSED (owner, 2026-11-03): fg2 may not be needed.** Nothing was submitted.
>
> **Where the preparation stopped:**
> - **fg1 event lists, done:** `/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/lists/events-<sample>.tsv.gz` (500,000 CV, 100,003 nueCC, 49,970 beam-off; ADLER32-checked). They are useful on their own, e.g. to exclude fg1 events from anything else.
> - **Selection script, done:** `fermigrid/bin/make-pairs-bulk.py` `--exclude` / `--check-events`.
> - **nueCC selection, done:**
>   - pairs: `/exp/sbnd/data/users/yuhw/production-prep/fermigrid-dev/fg2/fg2-mc-nuecc.tsv` (2,023 pairs, 17,690 events), with `.skipped` and `.events.tsv.gz`;
>   - checked: 0 events or files shared with fg1, no duplicates.
> - **CV selection, NOT done:** `make-pairs-cv.sh` stopped on 2026-10-28, when the session ended, at 4,800 of 711,587 files (63k of 500k events).
>   - It was far too slow (~35 files/min): the CAF event reads in the 32 threads do not scale.
>   - To resume, read the CAF events with processes (as `fg2/event-list.py` does, ~2 s per file with 12 processes), then rerun the selection.
> - **Tarball:** `tar/wcgrid-fg2.tar.gz` is built from the same builds as fg1, but with 2 uncommitted workflow files. Rebuild it after any workflow change.
> - **fg1 incident found during the preparation:** 32 fg1 merged CAFs on persistent had been truncated to 0 bytes by dCache (2026-10-18 05–07 h and 2026-10-21 00–04 h). They were restored from scratch and ADLER32-checked on 2026-10-28.
> - **Placeholders left below:** CV pair counts, estimate totals, issue number.

## Request (owner, 2026-10-27)

- Same configuration as fg1: the same chain and the same FermiGrid job.
- 500k MC BNB CV events and 100k MC nueCC events.
- **No event of fg2 may be in fg1.**

**Decisions (owner, 2026-10-28):**
- **nueCC:** SAM has one nueCC sample, and fg1 used most of it. fg2 takes **every unused nueCC file that has a CAF**: 2,023 pairs, 17,690 events, not 100k (see "Selection").
- **CV:** fg2 **continues fg1's file order**.

## Same configuration as fg1

| | fg1 | fg2 |
|---|---|---|
| chain | MC: step 1 `wcls-img-clus-matching.fcl` → step 2 `wct-pr.jsonnet` (DL vertex + dump, flat tree, reco↔truth match) → merge into the CAF → value-by-value validation | the same |
| wire-cell-toolkit | fork `sbnd-wc-flatcaf` `4b6853d4` | the same build (`libWireCellClus.so` md5 `017adf362cdf`, checked 2026-10-28) |
| larwirecell | fork `sbnd-wc-flatcaf` `ad5d942` | the same |
| step-1 fcls | wcp-porting-validation `88cb05aa` | the same |
| wire-cell-data | `9e2f4b8` | the same |
| UPS | sbndcode `v10_14_02_03` `e26:prof` from CVMFS, SL7 image `fnal-dev-sl7` | the same |
| job | `fermigrid/bin/job.sh`, `WC_KEEP=semiprod`, `WC_STAMP_INPUT_FILE=1` | the same script after `d83d26e`, which changes only bookkeeping: input copies checked by size, nothing overwritten at the destination (`<id>.done`), `EMPTY` status for reco1 files without events |
| resources | 1 CPU, 4000 MB + `FERMIHTC_AutoRelease` (+2 GB grace), 6 GB disk, 6 h, `DEDICATED,OPPORTUNISTIC`, `--maxConcurrent 2000` per sample | the same |
| pairs per job | CV 8, nueCC 10 | the same |
| output | `/pnfs/sbnd/scratch/users/yuhw/prod-fermigrid/fg1/<sample>/<id>/`; merged CAFs copied to `/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/` | `.../prod-fermigrid/fg2/...` likewise |

The code tarball for fg2 is rebuilt with `bin/make-tarball.sh` from the same builds: TARBALL.

## Selection: how fg1 and fg2 events are chosen

**Input definitions (both productions):**

| sample | reco1 definition | CAF definition | files |
|---|---|---|---|
| CV | `aurora_SBND2026A_gen2_BNBLight_prodgenie_corsika_proton_rockbox0p1_sbnd_CV_v10_14_02_03_reco1_sbnd` | `..._CV_v10_14_02_03_flatcaf_sbnd` | 749,329 reco1 |
| nueCC | `aurora_SBND2026A_gen2_BNBLight_prodgenie_corsika_proton_rockbox0p1_sbnd_EX_nuecc_v10_14_02_05_reco1_sbnd` | `..._EX_nuecc_v10_14_02_05_flat_caf_sbnd` | 14,231 reco1, 13,479 CAFs |

**fg1** (`fermigrid/bin/make-pairs-bulk.py`, 2026-10-16):
1. The definition's reco1 files are put in one order: r8's files first (`--include`), then all others shuffled with `random.Random(20261016)`.
2. Walking that order, a file is taken if its CAF exists (`<reco1 dir with /reco1/ → /caf/>/reco2-<stem>.flat.caf.root`) and both files are ONLINE in dCache.
3. This stops when the SAM event counts reach the target.

Result: CV 37,742 pairs (500,000 events) from the first 38,409 files of the order; nueCC 11,445 pairs (100,003 events).

**fg2** (the same script with `--exclude` and `--check-events`, added for fg2):
1. **The same order:** the same definition, `--include` (r8) and seed. Every fg1 file is removed from the order without reordering it (`--exclude` fg1's pairs list), so fg2 continues where fg1 stopped. For CV, the fg1 files form exactly the first ORDER_CHECK positions of the regenerated order, which shows the order is reproduced.
2. **The same pairing rules:** a CAF must exist, and both files must be ONLINE.
3. **Event-level exclusion:** each candidate's CAF events (run, subrun, event from `recTree` `rec.hdr`) are read. A pair whose CAF shares any event with fg1 (`--exclude-events` fg1's event list) or with a pair fg2 already took is skipped.
   - File-level exclusion alone is not enough: run.subrun is not unique per file in these filtered samples. Among the unused nueCC files, 84 run.subrun values are shared by two files, whose event ranges interleave.
4. **Targets:** CV stops at 500,000 events. nueCC runs to the end of the definition.

**Result:**

| sample | pairs | events | skipped (reason) |
|---|---|---|---|
| CV | CV_PAIRS | CV_EVENTS | CV_SKIPPED |
| nueCC | 2,023 | 17,690 | 763: 753 reco1 files without a CAF, 10 sharing an event label with fg1 or with a pair fg2 already took |

Overlap with fg1: 0 events, by construction. After the production, the merged CAFs' events are checked against fg1's list once more (see "After the run").

### Where the full event lists are

One line per CAF event: pair id, run, subrun, event, CAF path.

| list | file |
|---|---|
| fg1, per sample | `/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/lists/events-<sample>.tsv.gz`, from the fg1 merged CAFs (the events that were actually reconstructed) |
| fg2, per sample | `/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg2/lists/events-<sample>.tsv.gz`, from the input CAFs at selection; after the run, from the merged CAFs |
| pairs (files) | `.../fg1/lists/pairs-<sample>.tsv`, `.../fg2/lists/pairs-<sample>.tsv`, and `pairs-<sample>.skipped.tsv` with the reason for each skipped file |

Copies are kept in `/exp/sbnd/data/users/yuhw/production-prep/fermigrid-dev/fg2/`.

## Estimate

From fg1's measured costs (`cost.tsv` of 3,000 CV and 1,500 nueCC pairs, calibrated against the nueCC job logs; reruns and setup add about 4 %):
- **CV:** 44 s per event on the grid, 13.2 events per pair.
- **nueCC:** 75 s per event, 8.8 events per pair.

The fg1 grid test (7 pairs) suggested 70 s per event for CV; the full run was faster.

| sample | events | pairs | jobs (pairs per job) | per job | core-hours | scratch output | persistent (merged CAFs) | input read |
|---|---|---|---|---|---|---|---|---|
| CV | 500,000 | ~37,900 | ~4,740 (8) | ~1.3 h | **~6,100** | ~1.65 TB | ~450 GB | ~14 TB |
| nueCC | 17,690 | 2,023 | 203 (10) | ~1.8 h | **~370** | ~76 GB | ~22 GB | ~0.6 TB |
| **total** | | | | | **TOTAL_HOURS** | | | |

- **Elapsed:** about 4–8 h at `--maxConcurrent 2000` (fg1: all three samples finished overnight).
- **CPU:** fg1 used about 8,900 core-hours for 650k events.
- **Memory:** 99.9 % of fg1 pairs stayed under 2.5 GB per step. About 10 per 50k pairs exceed 4 GB (auto-released with 2 GB more, or killed in rare events).

**Expected losses, as in fg1** (about 0.03 % of events, `wc.valid = 0`; see #1 for the analysis):
- step-1 timeouts on slow nodes (skipped events);
- deterministic segfaults in `ClusteringConnect1` (k-d tree recursion);
- rare memory kills in `ChargeSolving`, `TensorSetLabeler` and `CreateSteinerGraph`.

The same configuration means the same failure modes. No fix is applied in fg2 (owner: same configuration as fg1).

## Before submitting (checklist)

1. **A valid Kerberos ticket and a token.** The r8 ticket's renewable lifetime ended 2026-10-23; run `kinit`, then `htgettoken -a htvaultprod.fnal.gov -i sbnd`.
2. **Tarball:** `bin/make-tarball.sh <tar>/wcgrid-fg2.tar.gz`. Check `TARBALL-PROVENANCE.txt`: the same commits as above, and `libWireCellClus.so` md5 `017adf362cdf`.
3. **Pairs lists:** `fg2-mc-cv.tsv`, `fg2-mc-nuecc.tsv` (section "Selection").
4. **Dry run:** `bin/submit.sh ... --dry-run` for each sample.
5. **Submit** (the same settings as fg1):
   ```bash
   WC_GRID_MEMORY=4000MB WC_GRID_DISK=6GB WC_GRID_LIFETIME=6h WC_GRID_MAXCONCURRENT=2000 \
   WC_GRID_LINES="+FERMIHTC_AutoRelease=True;+FERMIHTC_GraceMemory=2048;+FERMIHTC_GraceLifetime=3600" \
     bin/submit.sh <tar>/wcgrid-fg2.tar.gz fg2-mc-cv.tsv 8 mc-cv fg2
   ... the same for fg2-mc-nuecc.tsv 10 mc-nuecc fg2
   ```

## After the run

1. A status scan of every pair (`<id>.done` makes this direct).
2. Resubmit the pairs of dead jobs. `job.sh` skips finished pairs, so a whole list can simply be resubmitted.
3. Copy the merged CAFs to `/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg2/`, checked by ADLER32.
4. Build `events-<sample>.tsv.gz` from the merged CAFs, and check: 0 events shared with fg1, 0 duplicates within fg2.
5. Write the README and `lists/` on persistent, as for fg1, and report on the issue.

## Log

- 2026-10-28: prepared. The fg1 event lists were built, the selection made, and the estimate written. Waiting for the owner.

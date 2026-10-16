# SBND Wire-Cell production into the flat CAF

This folder turns SBND reco1 artROOT into flat CAFs that carry the Wire-Cell reconstruction as an extra tree, `recTreeWireCell`, next to the CAF's own `recTree`.

Development and validation are tracked in [ai-helper #39](https://github.com/HaiwangYu/wire-cell-toolkit-ai-helper/issues/39). AI agents: read [`AGENTS.md`](AGENTS.md) first.

## The three steps

```
                (data only: step 0 = run_frameshift.fcl, a local copy with FrameShift)
reco1 artROOT ──step 1──▶ qlpctree.tar.gz ──step 2──▶ pr_evt<E>/tracking-pr.root ──step 3──▶ <caf>.wc.flat.caf.root
  (lar, larwirecell)        (one per reco1)  (wire-cell, standalone)   (one per event)      (merge)  (flat CAF + recTreeWireCell)
                                                                                     ▲
                                                               existing flat CAF ────┘
```

| step | what | program | output |
|---|---|---|---|
| 0 | data only: copy the reco1 with the FrameShift product (Gen2 data needs it for the light matching) | `bin/step0-frameshift.sh` → `lar -c run_frameshift.fcl` | `<id>/fs/<reco1>_frameshift.root` (intermediate) |
| 1 | imaging, clustering, charge-light matching, all-APA clustering; MC truth tables; the art input file name as metadata | `bin/step1.sh` → `lar -c wcls-img-clus-matching{,-data}.fcl` | `qlpctree.tar.gz`, `mabc.zip` (Bee), `nugraph.h5` |
| 2 | pattern recognition, taggers, BDT scores, DL vertex (with the dump), the reco↔truth match on MC (`truth_match`, ai-helper #41), and the per-event flat tree | `bin/step2.sh` → `wire-cell -c pgrapher/experiment/sbnd/wct-pr.jsonnet --tla-code flat_tree=true --tla-code truth_match=<sim>` | `pr_evt<E>/tracking-pr.root` (row trees + `recTreeWireCell`), `mabc-pr.zip` |
| 3 | copy the flat CAF unchanged and add `recTreeWireCell`, aligned with `recTree` by run / subrun / event | `bin/merge-caf.py` | `<name>.wc.flat.caf.root` |
| check | merged tree vs `tracking-pr.root`, every value; original CAF objects untouched | `bin/validate-merge.py` | `validate.json` |
| driver | precheck, the steps, retries, slicing, partial merge, cost | `bin/run_pair.py` (one pair), `bin/run-pairs.sh` (a pool) | `status`, `cost.tsv` |

## Quick start

```bash
cd sbnd-wirecell-production/aurora
# 1. find pairs: by SAM definition (the CAF is the reco1's child) ...
bin/find-pairs.py --reco1-samdef <reco1 def> --caf-samdef <flatcaf def> --reality sim --limit 100 -o pairs.tsv
#    ... or by path (CAF named reco2-<reco1 stem>.flat.caf.root or .caf.root)
bin/find-pairs.py --reco1-dir <dir> --caf-dir <dir> --reality sim -o pairs.tsv
# 2. run every pair through steps 1-3 + validation
bin/run-pairs.sh site/<site>.sh pairs.tsv <workdir>
# 3. look
cat <workdir>/pool.log <workdir>/cost-summary.md
```
- Sites: `site/fnal-sbndbuild03.sh` (FNAL, SL7 via `in-gpvm-sl7.sh`) and `site/aurora.sh` (ALCF Aurora compute node; `pbs/run-pairs.pbs`).
- Keep modes (`WC_KEEP`): `all` (default), `minimal` (qlpctree + merged CAF + logs), `semiprod` (+ every `tracking-pr.root`), `validation` (+ the Bee zips). Details in `bin/run_pair.py`.
- Pairs: `find-pairs.py --reco1-names <file>` pairs a given list of reco1 files through SAM; `--caf-relation sibling` pairs data whose CAF was made from the raw file in one job (MCP2025C, gen2 InTime): reco1 and CAF are children of one raw file. Skipped reco1 files go to `<pairs>.skipped`.
- Shared node, load-governed: `site/fnal-sbndbuild03-governed.sh` + `bin/load-governor.sh <control dir>`. The governor sets the budget every minute from the other users' load: 60 % of CPU and memory while they use < 20 % of both, 30 % otherwise. All pools sharing the control dir count against one budget (`WC_GLOBAL=1`).
- Disk (#40): `WC_KEEP=minimal bin/run-pairs.sh …` keeps only `ql/<tag>/qlpctree.tar.gz`, `merged/` and the logs of each validated pair (the FrameShift copy, `mabc.zip`, `nugraph.h5`, `pr_evt*/`, `mabc-pr.zip` are deleted); the default `all` keeps everything. A `FAIL` pair always keeps everything.
- `site/fnal-sbndbuild03-60pct.sh`: 60 % of sbndbuild03 (cores 26–63, 38 pairs at night and on weekends, 19 in the weekday daytime, 70 GB guard), owner-approved for the open-data run only.
- Rerunning `run-pairs.sh` on the same work dir resumes: pairs with `status` `OK` or `PARTIAL` are skipped, and a `FAIL` pair reuses its finished step-1 slices and step-2 tars.

## When something goes wrong (`bin/run_pair.py`)

| situation | what happens | `status` |
|---|---|---|
| data: `run_frameshift.fcl` fails, or the copy lacks FrameShift / lost events (`WC_TIMEOUT_STEP0`, 1800 s) | stops before step 1 | `FAIL step0 …` |
| CAF or reco1 missing, empty, or on tape (dCache locality not `ONLINE`) | stops before any compute | `FAIL precheck …` |
| step 1 (`lar`) crashes or exceeds `WC_TIMEOUT_STEP1_BASE` + `_PER_EVENT` × events (900 + 300 s) | the failing event is found from the log (the last `<OpHitSource:tpc0> run R subrun S event E` line). It is skipped, and the rest is rerun as two slices with `--nskip`/`-n`, recursively, up to `WC_STEP1_MAX_BAD` (3) skipped events per file | `PARTIAL` (skipped events in `events.json`) |
| step 2 (`wire-cell`) crashes, exceeds `WC_TIMEOUT_STEP2_BASE` + `_PER_EVENT` × events (600 + 300 s), has a DL failure or misses a flat tree | retried, `WC_STEP2_ATTEMPTS` (2) tries per tar | `OK` if a try succeeds |
| step 2 fails every try | the complete per-event files of ALL tries (`collect-good.py`: `recTreeWireCell` present; crash stubs have none) are merged; the other CAF events get `wc.valid = 0` | `PARTIAL` |
| no complete event at all | not merged | `FAIL step2 …` |
| merge or validation fails, or exceeds `WC_TIMEOUT_STEP3` (1800 s) / `WC_TIMEOUT_VALIDATE` (3600 s) | | `FAIL step3` / `FAIL validate` |

- Every step runs under `timeout -k 60`.
- Every failed try is moved to `<pair>/attempts/<step>-<tag>-try<k>/` and kept, never overwritten.
- `cost.tsv` has one row per try (`step, tag, attempt, rc, …`). `cost-summary.md` lists the failed tries separately as wasted compute.

## `recTreeWireCell`

One entry per CAF event. The layout follows the flat CAF's own convention for nested vectors (`..length`, `..idx`, `..totarraysize`), with prefix `wc`:

| branch | meaning |
|---|---|
| `wc.run`, `wc.subrun`, `wc.evt` | the event, equal to `recTree`'s `rec.hdr.run/subrun/evt` of the same entry |
| `wc.valid` | 1 if Wire-Cell output exists for the event, 0 otherwise (all row counts then 0) |
| `wc.<T>..length` | rows of tree `T` of `tracking-pr.root` in this event (`T_kine`, `T_tagger`, `T_cluster`, `T_dlvtx_call`, …) |
| `wc.<T>.<b>[wc.<T>..length]` | a scalar branch `b` of `T`, one value per row, same type |
| `wc.<T>.<b>..length`, `..idx` (per row), `..totarraysize`, `wc.<T>.<b>[…]` | a vector or string branch: row *i* is `wc.<T>.<b>[idx[i] : idx[i] + length[i]]` |
| `wc.<T>.<b>.v…` | the inner level of a `vector<vector<>>` branch |

Its branch set is fixed by `schema/recTreeWireCell.schema.json`: 2,401 branches, 20 trees (md5 `d4396a3490ea`; the #39 schema without the truth-match trees is kept as `recTreeWireCell.schema.v1-c845fe94fbe5.json`). A tree an event did not write has 0 rows. With uproot, `t.arrays(filter_name='wc.T_kine.*')` gives jagged arrays directly.

The merged file also holds `recTreeWireCell_info`, a TNamed with JSON provenance: the input CAF, the schema md5, and the event counts.

### Reco↔truth matching (MC, ai-helper #41)

On MC, step 1's labeler writes each blob's true-particle label with its purity, and a table of every true particle (`truth_track`). Step 2 turns them into five trees, which reach `recTreeWireCell` like every other tree:

| tree | one row is |
|---|---|
| `T_truth_track` | a G4 particle with charge in the readout window: `nu_idx` (−1 not from a beam neutrino), `bee_trackid` (Michel merged), `ancestor_trackid`, `prong_trackid` (a shower is one prong), `pdg`, `q_readout`, `q_in_blobs` |
| `T_overlap` | a (reco piece, true particle) pair and the imaging points / charge they share; a piece is a candidate's segment (`nu_index`, `segment_id`, `kine_index`, `in_enu`, `in_pf`) or the rest of a cluster; `trackid` −1 = unlabeled (ghost) points; `n_pure`/`q_pure` from blobs of purity ≥ 0.5 |
| `T_match` | a reco or truth object at one `level` (0 cluster, 1 particle = `T_kine` row vs prong, 2 candidate = `T_kine` particles vs interaction, 3 candidate = particle-flow tree vs interaction), `side` 0 reco / 1 truth, sizes, and up to 3 partners by point IoU (`match_obj`, `match_iou_n`, `match_iou_q`, shared counts), `mutual` |
| `T_pf` | a node of a candidate's reco particle-flow tree, with `parent_id`, `pdg`, `ke_mev`, `kine_index` |
| `T_blob_truth` | (only with `--tla-code blob_truth=true`) a blob: its label, purity, runner-up |

`T_overlap` is everything needed to redo the match with other choices (charge weight, pure blobs, other object definitions). `WC_TRUTH_MATCH=0` turns it off. Data gets none of these trees.

## Software

| component | version |
|---|---|
| wire-cell-toolkit | `HaiwangYu/wire-cell-toolkit` branch `sbnd-wc-flatcaf` (from master `b7bd2a1a`): `RootFlatTreeVisitor`, `Trun.input_file`, the `flat_tree` TLA; `229b7aab`: the `truth_match` trees |
| larwirecell | `HaiwangYu/larwirecell` branch `sbnd-wc-flatcaf` (from `189ad26`): the art input file name as set metadata `input_file`; `73c79bc`: the labeler's `truth_detail` |
| wcp-porting-validation | `WireCell/wcp-porting-validation` `main`: the step-1 fcls |

Environment: `env/fnal/` (FNAL) and `env/aurora/` (copies of ai-helper #29's Aurora scripts).

## Layout of a work dir

```
<workdir>/pairs.tsv, schema.json, pool.log, RUN-RECORD.txt, cost-summary.md, maxpar.override (optional)
<workdir>/<id>/ql/<tag>/  pr/<tag>/  attempts/  merged/<name>.wc.flat.caf.root  merged/merge.json  good.txt  events.json  validate.json  cost.tsv  status  run_pair.log
  (<tag> = all, or s<a>-<b> for an event slice of the reco1 file)
```

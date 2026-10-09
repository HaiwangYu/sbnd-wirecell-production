# SBND Wire-Cell production into the flat CAF

This folder turns SBND reco1 artROOT into flat CAFs that carry the Wire-Cell reconstruction as an extra tree, `recTreeWireCell`, next to the CAF's own `recTree`.

Development and validation are tracked in [ai-helper #39](https://github.com/HaiwangYu/wire-cell-toolkit-ai-helper/issues/39). AI agents: read [`AGENTS.md`](AGENTS.md) first.

## The three steps

```
reco1 artROOT ──step 1──▶ qlpctree.tar.gz ──step 2──▶ pr_evt<E>/tracking-pr.root ──step 3──▶ <caf>.wc.flat.caf.root
  (lar, larwirecell)        (one per reco1)  (wire-cell, standalone)   (one per event)      (merge)  (flat CAF + recTreeWireCell)
                                                                                     ▲
                                                               existing flat CAF ────┘
```

| step | what | program | output |
|---|---|---|---|
| 1 | imaging, clustering, charge-light matching, all-APA clustering; MC truth tables; the art input file name as metadata | `bin/step1.sh` → `lar -c wcls-img-clus-matching{,-data}.fcl` | `qlpctree.tar.gz`, `mabc.zip` (Bee), `nugraph.h5` |
| 2 | pattern recognition, taggers, BDT scores, DL vertex (with the dump), and the per-event flat tree | `bin/step2.sh` → `wire-cell -c pgrapher/experiment/sbnd/wct-pr.jsonnet --tla-code flat_tree=true` | `pr_evt<E>/tracking-pr.root` (row trees + `recTreeWireCell`), `mabc-pr.zip` |
| 3 | copy the flat CAF unchanged and add `recTreeWireCell`, aligned with `recTree` by run / subrun / event | `bin/merge-caf.py` | `<name>.wc.flat.caf.root` |
| check | merged tree vs `tracking-pr.root`, every value; original CAF objects untouched | `bin/validate-merge.py` | `validate.json` |

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
- Rerunning `run-pairs.sh` on the same work dir resumes: pairs with `status` `OK` are skipped.

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

Its branch set is fixed by `schema/recTreeWireCell.schema.json`: 2,283 branches, 15 trees. A tree an event did not write has 0 rows. With uproot, `t.arrays(filter_name='wc.T_kine.*')` gives jagged arrays directly.

The merged file also holds `recTreeWireCell_info`, a TNamed with JSON provenance: the input CAF, the schema md5, and the event counts.

## Software

| component | version |
|---|---|
| wire-cell-toolkit | `HaiwangYu/wire-cell-toolkit` branch `sbnd-wc-flatcaf` (from master `b7bd2a1a`): `RootFlatTreeVisitor`, `Trun.input_file`, the `flat_tree` TLA |
| larwirecell | `HaiwangYu/larwirecell` branch `sbnd-wc-flatcaf` (from `189ad26`): the art input file name as set metadata `input_file` |
| wcp-porting-validation | `WireCell/wcp-porting-validation` `main`: the step-1 fcls |

Environment: `env/fnal/` (FNAL) and `env/aurora/` (copies of ai-helper #29's Aurora scripts).

## Layout of a work dir

```
<workdir>/pairs.tsv, schema.json, pool.log, RUN-RECORD.txt, cost-summary.md, maxpar.override (optional)
<workdir>/<id>/ql/  pr/  pr-try1/  merged/<name>.wc.flat.caf.root  merged/merge.json  validate.json  cost.tsv  status
```

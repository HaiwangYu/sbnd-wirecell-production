# Running the r8 chain on Aurora: an experience guide for the agent

This guide is for an AI agent working on ALCF Aurora. The task: take new SBND simulation at the reco1 stage (on Flare) through the same chain as r8, and produce the same kind of output r8 produced at FNAL.

Read first: [`../README.md`](../README.md) (the steps), [`../AGENTS.md`](../AGENTS.md) (the rules and the traps). This guide adds what is specific to Aurora and to r8. It is written from:
- the FNAL r8 run (ai-helper #42, 2026-10-16: 2,400 pairs);
- the FermiGrid production fg1 (sbnd-wirecell-production #1: 50,241 pairs);
- the Aurora port of the 1-step chain (ai-helper #29, 2026-09-16/17).

The 2-step chain (r8) has **not yet run on Aurora**. Its first run there is a validation (section 4), not a production.

## 1. What "the r8 chain" is

Per reco1 / flat-CAF pair (`bin/run_pair.py`):

| step | program | r8 setting |
|---|---|---|
| 1 | `bin/step1.sh` → `lar -c wcls-img-clus-matching.fcl` (MC) | imaging, clustering, Q/L matching; labeler with `truth_detail` (blob truth + `truth_track` table, ai-helper #41) |
| 2 | `bin/step2.sh` → `wire-cell -c pgrapher/experiment/sbnd/wct-pr.jsonnet` | `flat_tree=true`, `dl_vtx_dump=true` (DL vertex on, with the dump), `truth_match=true` on sim |
| 3 | `bin/merge-caf.py` | the flat CAF + `recTreeWireCell` (schema `schema/recTreeWireCell.schema.json`, md5 `d4396a3490ea`, 2,401 branches) |
| check | `bin/validate-merge.py` | every merged value vs `tracking-pr.root` |

**Pins.** r8 ran these; build exactly them:

| component | where | r8 pin |
|---|---|---|
| wire-cell-toolkit | `HaiwangYu/wire-cell-toolkit` branch `sbnd-wc-flatcaf` | `4b6853d4`. Its `cfg/` is used LIVE: it holds both steps' configuration, including the step-1 jsonnet that the `sbnd/` wrapper imports |
| larwirecell | `HaiwangYu/larwirecell` branch `sbnd-wc-flatcaf` | `73c79bc`, or the branch head `ad5d942`, which adds only the `WCLS_INPUT_FILE` override (inactive unless set) |
| wcp-porting-validation | `WireCell/wcp-porting-validation` `main` | the step-1 fcls `sbnd/wcls-img-clus-matching{,-data}.fcl` and `wcls-img-clus-matching-pr-hits.fcl` (unchanged since r8) |
| this repo | `HaiwangYu/sbnd-wirecell-production` `main` | the workflow; pull the latest |
| wire-cell-data | `WireCell/wire-cell-data` | plus `uboone/weights/XGB_nue_seed2_0923.xml` (md5 `2bdb5cec111bf6cb6dd828cd59fe7ea0`, not in git) and `uboone/scn_vtx/t48k-m16-l5-lr5d-res0.5-CP24.pth` (md5 `9cc1413e053c09534edc2d37cdfdc1d4`) |
| UPS | sbndcode `v10_14_02_03` `e26:prof` | Aurora: twester's Flare tree + the `$Y/products` overlay (spdlog v1_14_1, fmt v11_0_2, scn v01_00_00) |

**What r8 kept** (`WC_KEEP`):
- `semiprod`: per pair `ql/<tag>/qlpctree.tar.gz`, every `pr/<tag>/pr_evt<E>/tracking-pr.root`, `merged/<caf>.wc.flat.caf.root`, and the logs.
- `validation`: the same plus the Bee zips. r8 ran ~100 events per sample this way.

Ask the owner which mode to use for the new sample (rule 6) if the request does not say.

## 2. Aurora facts that bite (from #29)

- **Containers only run in PBS jobs.** Login nodes (UANs) have `user.max_user_namespaces=0`. Every lar / wire-cell / PyROOT step, and therefore `run_pair.py` and `run-pairs.sh`, must run on a compute node: `pbs/run-pairs.pbs`.
  - UANs have direct internet: use them for `git`, `pip --user`, and editing.
  - Compute nodes reach the internet only through `http://proxy.alcf.anl.gov:3128`. `env/aurora/in-aurora-sl7.sh` sets it.
- **`module load apptainer` works in batch only when not piped:** `module load apptainer | tail` runs it in a subshell, and then `apptainer: command not found`. `in-aurora-sl7.sh` handles it; do not wrap it in a pipe.
- **Paths:**
  - `$Y=/lus/flare/projects/neutrinoGPU/yuhw`;
  - `$OPT=$Y/opt` (the WCT install; larwirecell libs under `$OPT/larwirecell/v10_01_28/slf7.x86_64.e26.prof/lib`);
  - `$WCT_SRC=$Y/wire-cell-toolkit`;
  - `$WCP_SBND=$Y/wcp-porting-validation/sbnd`;
  - `$WCD=$Y/wire-cell-data`;
  - the MRB area `$Y/larsoft-wct/v10_14_02` (its `srcs/larwirecell` is a clone of `$Y/larwirecell`).
- **The UPS tree** is `/lus/flare/projects/neutrinoGPU/scisoft/larsoft` (no CVMFS). `in-aurora-sl7.sh` binds it at `/cvmfs/sbnd.opensciencegrid.org/products/sbnd`, because `clus.jsonnet` hard-codes the SCE map's CVMFS path (#29 smoke 1: `lar` exit 9).
- **Build image:** `$Y/images/fnal-dev-sl7.sif`. The bare `slf7.sif` lacks the `-devel` headers.
- **`/tmp` on a compute node is a RAM tmpfs** (504 GB of the 1.1 TB): no node-local disk. Work dirs go on Flare.
- **Node:** 104 cores (208 threads), 1.1 TB. `site/aurora.sh` runs `WC_MAXPAR=100` pairs per node (r8 RSS is ~1.5–2.5 GB per pair; rare peaks to 5.3 GB).
- **Account and queues:**
  - production: `-A neutrinoGPU -q prod`;
  - short tests: `-A neutrinoGPU::debug2 -q debug -l walltime=00:59:00`, as #29 used;
  - `qstat -Qf` lists the others (`debug-scaling` 1–256 nodes, `capacity` 1–16 nodes).
- **The project's Flare quota was at 95 % in September** (3.045 / 3.2 PB). Check `df`/quota before writing TBs: r8 `semiprod` keeps ~3.5 MB per event, and `validation` adds ~2 MB per event of Bee.
- **SL7 git is 1.8:** no `git -C`. Run git on the UAN, or `cd` first.

## 3. Bring Aurora to the r8 pins

On a UAN:
```bash
Y=/lus/flare/projects/neutrinoGPU/yuhw
cd $Y/wire-cell-toolkit && git fetch fork && git checkout sbnd-wc-flatcaf && git reset --hard fork/sbnd-wc-flatcaf   # only if the tree is clean: check git status first
git log -1 --format=%h          # must be 4b6853d4 (or a later head the owner names)
git status --short cfg          # must be empty: cfg/ is read live by every job
cd $Y/larwirecell && git fetch && git checkout sbnd-wc-flatcaf && git pull --ff-only   # head ad5d942 (or 73c79bc)
cd $Y/larsoft-wct/v10_14_02/srcs/larwirecell && git fetch && git checkout sbnd-wc-flatcaf && git pull --ff-only   # the MRB clone builds from HERE
cd $Y/wcp-porting-validation && git pull --ff-only    # main
cd $Y/sbnd-wirecell-production && git pull --ff-only  # main
cd $Y/wire-cell-toolkit-ai-helper && git pull --ff-only
md5sum $Y/wire-cell-data/uboone/weights/XGB_nue_seed2_0923.xml $Y/wire-cell-data/uboone/scn_vtx/t48k-m16-l5-lr5d-res0.5-CP24.pth
```
- Check the remote names (`git remote -v`): in #29 the toolkit had `origin` = WireCell and `fork` = HaiwangYu.
- Never `reset --hard` over local changes you did not make. If a tree is dirty, stop and ask the owner.

**Build:** use ai-helper `issues/29-aurora-production/scripts/build-wct-lwc.pbs`. It builds whatever is checked out:
- toolkit: a clean wcb install into `$OPT`, with the RPATH strip;
- larwirecell: `mrb b`, then the libs and fcl copied into `$OPT/larwirecell/...`.

```bash
cd $Y/aurora-build-logs && qsub -v CLEAN=1 $Y/wire-cell-toolkit-ai-helper/issues/29-aurora-production/scripts/build-wct-lwc.pbs
```
`CLEAN=1` is needed: the toolkit moved from `polaris-build-fixes` to `sbnd-wc-flatcaf`, and stale objects must not survive.

**Gates G1–G2 after the build** (inside a job, or on the UAN for `nm`/`strings`):
```bash
nm -D --defined-only $OPT/lib/libWireCellRoot.so | grep -c make_RootFlatTreeVisitor_factory        # >= 1
strings $OPT/lib/libWireCellRoot.so | grep -c '^T_overlap$'                                        # >= 1 (#41 truth match)
L=$OPT/larwirecell/v10_01_28/slf7.x86_64.e26.prof/lib
nm -DC $L/libWireCellLarsoft.so | grep -c respond_to_open_input_file                                # >= 1
strings $L/libWireCellAIML.so | grep -c prong_trackid                                               # >= 1 (labeler truth_detail)
```
Also check the build log: `WCB_RC=0`, `ldd_not_found=0`, `rpath_stripped` > 0.

## 4. Gate G4: reproduce r8 on Aurora before touching the new sample

A reference bundle was made at FNAL for this (2026-10-18): `/exp/sbnd/data/users/yuhw/production-prep/aurora-r8-reference/` (615 MB). It holds:
- 2 r8 validation MC pairs: CV `reco1-detsim-g4-gen-Gen2_2026-0a6e-4cdb-c277-9be4` (13 events) and nueCC `reco1-detsim-g4-filter-gen-86e4-db18-f201-d962_nuecc` (7 events);
- their inputs, r8's outputs in the layout `fermigrid/bin/compare-outputs.py` reads, `pairs-template.tsv`, `md5sums.txt`, and a README.

Transfer it to `$Y/production-prep/aurora-r8-reference/` (Globus, as #29 did for its references; ask the owner if no endpoint is at hand), then `md5sum -c md5sums.txt`.

```bash
R=$Y/production-prep/aurora-r8-reference; cd $R
sed "s|INPUTS|$R/inputs|g" pairs-template.tsv > pairs.tsv
cd $Y/sbnd-wirecell-production/aurora
qsub -A neutrinoGPU::debug2 -q debug -l walltime=00:59:00 \
     -v REPO=$PWD,PAIRS=$R/pairs.tsv,WORK=$R/aurora-run,WC_KEEP=validation pbs/run-pairs.pbs
```
`WC_KEEP=validation` reaches `run_pair.py`, because `run-pairs.pbs` → `run-pairs.sh` passes the environment on.

**Pass:**
- both pairs end `OK` in `$R/aurora-run/<id>/status`;
- `validate.json` is `PASS`;
- `pr/*/dl_fail` is `0` (a DL-vertex failure is silent otherwise);
- `compare-outputs.py` finds no difference beyond the expected ones (below).

Compare each pair, on the UAN (`pip install --user uproot awkward` once) or at FNAL after copying `aurora-run/` back:
```bash
for id in $(awk 'NR>1 {print $1}' $R/pairs.tsv); do
  python3 $Y/sbnd-wirecell-production/fermigrid/bin/compare-outputs.py $R/ref/$id $R/aurora-run/$id \
      --ignore Trun.input_file recTreeWireCell.wc.Trun.input_file | tail -1
done
```

**Expected differences, and only these:**
- `Trun.input_file` / `wc.Trun.input_file`: the reco1 path, a `/pnfs` path in the reference;
- `merged CAF: recTreeWireCell_info (TNamed)`: creation time and schema path.

The qlpctree tensors must be identical (`array_diffs` 0). Their metadata may differ by the input-file name only.

Why it should pass:
- The same code ran identically on FermiGrid (7 pairs, 108 events, 2,070 trees, 24.4k tensors).
- The 1-step chain was "exact" between Aurora and FNAL (#29, 2026-09-17): 19/19 data events, 18/18 and 50/50 MC events.

**If it does not pass,** do not start the production. Look first at the configuration search order. The Aurora `WIRECELL_PATH` (`env/aurora/setup-aurora-ap.sh`) puts these ahead of the toolkit `cfg/`:
1. `$WCP_SBND`;
2. `$WCP_SBND/sbnd_xin`;
3. `photodet`.

The FNAL r8 order is:
1. `wire-cell-data/sbnd/photodet`;
2. the toolkit `cfg`;
3. `wcp-porting-img/sbnd/standalone-sample`;
4. `wcp-porting-img/sbnd`;
5. `opt/share/wirecell`;
6. the sbndcode cfg;
7. `wire-cell-data`.

No file name collides between those directories today (checked 2026-10-18), but a new file in `sbnd/` or `sbnd_xin/` could shadow one. Also check the bundle's `cost.tsv` against yours for a step that took a different number of tries. Report to the owner with the `compare-outputs.py` verdicts.

Record the gate's timing: `cost-summary.md`, seconds per event per step. The 2-step chain has no Aurora timing yet. The 1-step chain took 57 s per event at 49 pairs per node, vs ~29–37 s at FNAL for r8.

## 5. The new sample

1. **Inventory.**
   - Where are the reco1 files? Are there flat CAFs made from them (`reco2-<reco1 stem>.flat.caf.root` or `*.caf.root`)?
   - Which sbndcode made them, and how many files and events are there?
2. **Products.** Step 1 reads, among others, `simtpc2d:dnnsp` wires (+ badmasks, wienersummary), `opflashtpc0/1`, `ionandscint:priorSCE` SimEnergyDeposits, MCTruth and MCParticle. In a job, compare the product list of one new file with the reference reco1 (`lar -c eventdump.fcl -s <file> -n 1`, both files). A missing or renamed label means the chain does not apply as is: ask the owner.
3. **No CAF?** `run_pair.py` needs one (precheck `FAIL precheck`, and step 3 merges into it). Steps 1–2 alone can run with `bin/step1.sh` / `bin/step2.sh` through `$WC_WRAP`, but that is not r8: ask the owner before choosing this.
4. **Pairs list:**
   ```bash
   bin/find-pairs.py --reco1-dir <reco1 tree> --caf-dir <caf tree> --reality sim -o pairs.tsv
   ```
   - Path mode runs on a UAN (no samweb on Aurora).
   - Check `pairs.tsv.skipped`. Every reco1 without a CAF is listed there, and the count goes in the report.
   - The 5th column (events) is `-` in path mode, which is fine.
5. **Smoke:** 2–3 pairs of the new sample in the `debug` queue, as in section 4. All `OK`, `validate.json` `PASS`, `dl_fail` 0, the truth trees (`T_truth_track`, `T_overlap`, `T_match`, `T_pf`) present in `tracking-pr.root`.
   - Look at one event in Bee if the keep mode is `validation`: upload `ql/<tag>/mabc.zip` / `pr/<tag>/mabc-pr.zip` as #29 did.
6. **Size it.**
   - Events × measured s/event ÷ 100 slots = node-hours.
   - Disk = events × ~3.5 MB (`semiprod`).
   - Tell the owner before a run above a few hundred node-hours, or one that needs more than ~10 % of the free Flare quota.

## 6. Production

- **One PBS job = one node = one chunk of the pairs list = its own work dir:**
  ```bash
  split -n l/<N> -d --additional-suffix=.tsv <(grep -v '^#' pairs.tsv) chunk-    # N chunks
  for c in chunk-*.tsv; do
    qsub -v REPO=$PWD,PAIRS=$PWD/$c,WORK=<out>/${c%.tsv},WC_KEEP=semiprod pbs/run-pairs.pbs
  done
  ```
  - Size a chunk so it finishes inside the walltime (6 h in `run-pairs.pbs`): pairs × events per pair × s per event ≤ ~0.7 × 6 h × 100 slots.
  - One slow pair holds the node until it ends: the timeouts (`WC_TIMEOUT_*`, README) bound it.
- **Resume = submit the same chunk again** with the same `WORK`:
  - `OK`, `EMPTY` (and `PARTIAL`) pairs are skipped;
  - a `FAIL` pair reuses its finished step-1 slices and step-2 tars.
  - A job killed at the walltime loses only its running pairs.
- **No load rule on Aurora:** the node is ours. The FNAL sbndbuild03 rules (half the machine, governor) do not apply here; `site/aurora.sh` has no day/night switch.
- **Monitoring:**
  - `qstat -u $USER`;
  - `tail <WORK>/pool.log` (one line per finished pair with its status);
  - `cat <WORK>/*/status | sort | uniq -c`.

## 7. After the run: check and report

Per chunk, and summed:
- pairs `OK` / `PARTIAL` / `EMPTY` / `FAIL <stage>`;
- the `PARTIAL` pairs with their `events.json` (skipped events, failed step-2 tars);
- every `validate.json` that is not `PASS`;
- `dl_fail` > 0 anywhere (must be none);
- `cost-summary.md` (time, CPU, RSS, disk per step, per event);
- the reco1 files without a CAF;
- the output size.

Put this where the owner says: a new ai-helper issue folder `issues/<n>-<slug>/` (doc + scripts only; data and logs are git-ignored), or a comment on the existing issue. Then add the new lessons to this guide.

## 8. What went wrong before, and what to expect

| seen | where | what to do |
|---|---|---|
| step 2 segfaults now and then (`TrackFitting::update_association`, `SteinerGrapher`; RSS to ~4.5 GB): ~1 per 550 nueCC events, ~1 per 13,000 CV | FNAL r6–r8, fg1 | handled: a retry, then a partial merge → `PARTIAL` (CV 22 and nueCC 20 of fg1's 49k pairs) |
| a deterministic step-1 crash, MC CV run 471 / subrun 18 / event 33 | r8 | handled: the event is skipped by slicing → `PARTIAL` |
| reco1 files with an empty `Events` tree (SAM can still list events) | fg1: 38 InTime data and 4 nueCC files | `EMPTY no events in the reco1 file` (workflow 2026-10-18); nothing to do |
| the DL vertex silently falls back to the geometric vertex without scn / `SCN_Vertex.py` on `PYTHONPATH` | #38 | `step2.sh` refuses to start and fails on `dl_fail` > 0; on Aurora the scn copy is `$Y/products/scn/v01_00_00` |
| `unsetup wirecell` also unsetups root, python, boost … (system python 3.6, f-string `SyntaxError` in `wscript`) | #29 build | `unsetup -j` (in `setup-aurora-opt.sh`) |
| `wscript` needs `git describe --tags`; a fork clone has no tags | #29 build | `git fetch origin --tags` (the build script does it) |
| `mrb newDev` needs `MRB_PROJECT=larsoft` | #29 build | exported in `setup-aurora-opt.sh` |
| a CVMFS path in the compiled config (`clus.jsonnet` SCE map) | #29 smoke | the Flare UPS tree is bound at that path by `in-aurora-sl7.sh` |
| `--nskip` counts in art's FileIndex (run/subrun/event) order, not tree order | #38 | matters only for files merged out of order; slicing in `run_pair.py` already relies on it |
| `pkill -f <pattern>` / `pgrep -f` match your own shell | FNAL, twice | kill by PID, or `pkill -x <comm>` |
| comparing ROOT or zip files by bytes | #29 | never; use `compare-outputs.py` (values) |

Peak RSS per pair seen in r8 and fg1:
- median ~1.6 GB;
- step 1 rarely to 3.0 GB, step 2 rarely to 5.3 GB (one beam-off event);
- the step-2 crash runaway reaches 4.2–4.5 GB.

100 pairs per 1.1 TB node is far from the limit.

# Instructions for AI agents running this workflow

Read [`README.md`](README.md) first for what the three steps do.

The development record is ai-helper issue 39 (`wire-cell-toolkit-ai-helper/issues/39-sbnd-wc-flatcaf/`). The production lessons behind every rule below are in ai-helper issues 26, 33, 35 and 38, and in `docs/sbnd-1step-build-run-validate.md` there.

## Rules

1. **Never commit or push on your own** to the toolkit, larwirecell or wcp-porting-validation. Leave changes for the owner, Haiwang. Pushing to this repo and to the ai-helper repo is fine when asked.
2. **Everything builds and runs inside the SL7 container**: `env/fnal/` or `env/aurora/`, through the site's `WC_WRAP`. A host build links the wrong glibc and fails only at plugin load.
3. **Shared machines (FNAL sbndbuild03):** never more than half the machine, and half again in the day (08:00–20:00). `site/fnal-sbndbuild03.sh` encodes this: cores 32–63, 14 pairs in the day and 28 at night, a 50 GB RSS guard, a 15 GB machine-available guard. Do not raise these without the owner. The exceptions the owner approved: `site/fnal-sbndbuild03-60pct.sh` (2026-10-10, the open FixedDev BNB data run) and `site/fnal-sbndbuild03-governed.sh` with `bin/load-governor.sh` (2026-10-15, ai-helper #42): 60 % while the other users take < 20 % of CPU and memory, else 30 %.
4. **Never edit anything under `sbnd_xin/`** (Xin's area): read and run only.
5. **Blinded data:** the SBND2026A `gen2_BNB-Run1` set is blinded. Never use it.
6. **Ask the owner** when a choice changes what gets produced.

## Before a production run: the gates

| gate | how | pass |
|---|---|---|
| G1 builds are the pinned branches | `git -C <toolkit> log -1`, `git -C <larwirecell> log -1`; the toolkit `cfg/` must be clean (it is used live via `WIRECELL_PATH`) | toolkit `sbnd-wc-flatcaf` head, larwirecell `sbnd-wc-flatcaf` head |
| G2 the binary knows the new code | `nm -D --defined-only $OPT/lib/libWireCellRoot.so \| grep make_RootFlatTreeVisitor_factory`; `nm -DC <larwirecell lib>/libWireCellLarsoft.so \| grep respond_to_open_input_file`; `strings $OPT/lib/libWireCellRoot.so \| grep -c '^T_overlap$'`; `strings <larwirecell lib>/libWireCellAIML.so \| grep -c prong_trackid` | all found |
| G3 compiled config | with `flat_tree` off, every SBND job compiles byte-identically to the previous pin; with `--tla-code flat_tree=true`, the step-2 config gains exactly `RootFlatTreeVisitor:pr`, last in the `clus_pr` pipeline (ai-helper `issues/38-*/scripts/cfg-proof.py`) | as stated |
| G4 smoke | `bin/run-pairs.sh` on 1–2 pairs | `status` `OK`, `validate.json` `PASS`, `pr/dl_fail` 0 |
| G5 schema | an unknown branch makes `merge-caf.py` fail loudly. After a toolkit change that adds branches, rebuild with `bin/make-schema.py` from an MC event with a neutrino candidate plus a data event, commit the new schema, and say so | `merge-caf.py` never fails on the schema |

## Traps (each one has cost a run before)

- **The DL vertex fails silently.** Without the scn product and `SCN_Vertex.py` on `PYTHONPATH`, every candidate logs `DL vertex failed: … No module named …`, falls back to the traditional vertex, and the job exits 0.
  - `step2.sh` refuses to start without the imports and fails if `pr/dl_fail` > 0.
  - On FNAL the setup must be sourced in the same shell as the job (`env/fnal/setup-fnal-run.sh` as `SL7_SETUP`), because `setup-dlvtx.sh` needs a shell function.
- **Data needs FrameShift.** Gen2 data reco1 must go through `run_frameshift.fcl` first. Without the product, step 1 silently uses a shift of 0, and the light matching is wrong. `run_pair.py` now does this itself for `data` pairs (step 0, `bin/step0-frameshift.sh`; `WC_FRAMESHIFT=0` turns it off for input that already has it). `step1.sh` still warns when every event has `frame_apply_at_caf 0 ns` on data. MC has no product by design.
- **Data pairs by SAM:** for the MCP2025C data, the CAF that is a direct child of the reco1 is the gen2 Respin one (`data_SBND2026A_SBND2026A_gen2_run1_BNBLight_Data_FixedDev_Respin_v10_14_02_04_flatcaf_sbnd`). The MCP2025C `..._flatcaf_sbnd` CAFs were made from the raw file in one job and are siblings, which `find-pairs.py` does not match.
- **The intermittent PR crash.** Step 2 segfaults now and then (`TrackFitting::update_association`, `SteinerGrapher`; peak RSS ~4.5 GB), much more often on nueCC (~1 per 550 events) than on BNB CV (~1 per 13,000).
  - A crash also leaves the previous event's `tracking-pr.root` as a stub.
  - `run_pair.py` retries a failed tar once (`WC_STEP2_ATTEMPTS`) and keeps every failed try under `attempts/`. If all tries fail, it still merges the complete events of all tries, giving `PARTIAL`.
- **A deterministic step-1 crash:** MC CV run 471 / subrun 18 / event 33 (`clustering_connect1` recursion). `run_pair.py` finds the failing event from the log and reruns the file in slices around it, giving `PARTIAL` with the event listed in `events.json`.
- **`--nskip` counts in art's FileIndex order** (sorted by run / subrun / event), not tree order.
- **Kerberos (FNAL):** a run longer than the ticket dies with rc 126. Use a renewable ticket in a fixed cache, renewed hourly. `run-pairs.sh` waits rather than fails while there is no ticket (`WC_KRB_WAIT=1`).
- **`pgrep -f` / `pkill -f <pattern>` match your own shell's command line.** Use `pkill -x <comm>` or explicit PIDs.
- **bash 4.2 in SL7:** `"${arr[@]}"` on an empty array is an unbound-variable error under `set -u`; write `${arr[@]+"${arr[@]}"}`. There is no `wait -n` inside the container either (the pool runs on the host).
- **Never compare ROOT or zip files by bytes**, only by content.

## What to report after a run

Report the `PARTIAL` pairs with their `events.json` (skipped events, failed tars), as well as `pool.log`, `cost-summary.md` (time, CPU, RSS and disk per step, per event), and the number of pairs `OK` / `FAIL` with their failing step. Also report every `validate.json` that is not `PASS`, with its first problems, and any `pr-try1/` (crash) units. Append it to the tracking issue.

## Deploying on Aurora

Follow [`docs/aurora-r8-chain.md`](docs/aurora-r8-chain.md). It covers:
- the r8 pins and how to build them on Aurora;
- gate G4 against an r8 reference bundle made at FNAL;
- pairing and sizing a new sample, and production in PBS chunks;
- what to report;
- the Aurora traps from ai-helper #29.

The 2-step chain has not yet run on Aurora: its first run there is the G4 validation.

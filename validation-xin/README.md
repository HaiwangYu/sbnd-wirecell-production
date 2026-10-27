# Xin's evaluation events: the hold-out list for model training

Created 2026-10-26. These are the SBND events Xin Qian (`/home/xqian/toolkit-dev/wcp-porting-img/sbnd/sbnd_xin`)
has used to evaluate the reconstruction chain. **Leave all of them out of any ML training set** so that his
evaluation numbers stay unbiased.

## Files

All in this directory:

| file | contents |
|---|---|
| `xin-eval-rse-mc.tsv` | **4,048 MC events**: the list to exclude from MC training |
| `xin-eval-rse-data.tsv` | 4,067 real-data events (matters only if data is ever used for training or tuning) |
| `xin-eval-rse-all.tsv` | both lists together (8,115 rows) |
| `xin-eval-files.tsv` | the 388 input art files with event counts and absolute paths, for excluding whole files |
| `tools/` | `rse_list.C` (Xin's `scripts/d115/rse_list.C`), `one.sh`, and `jobs.tsv` (sample, kind, path) used to build the lists |

TSV columns: `sample  kind(mc|data)  file  entry  run  subrun  event`. `file` is the basename of the reco1 art
file and `entry` is the entry index in that file.

## The samples

| sample | kind | events | files | runs | source | where Xin used it |
|---|---|---:|---:|---|---|---|
| `mc-cv` | MC | 2,017 | 154 | 711–720 | `aurora_SBND2026A_gen2_BNBLight_prodgenie_corsika_proton_rockbox0p1_sbnd_CV_v10_14_02_03_reco1_sbnd` → `xin-round3-samples/mc-cv/reco1/` | round-3 truth baseline (his doc 115), `work-r3cv-*` (all 154 files) |
| `mc-nuecc` | MC | 2,001 | 225 | 291–300 | `aurora_SBND2026A_gen2_BNBLight_prodgenie_corsika_proton_rockbox0p1_sbnd_EX_nuecc_v10_14_02_05_reco1_sbnd` → `xin-round3-samples/mc-nuecc/reco1/` | doc 115, `work-r3nue-*` (all 225 files) |
| `r1qlmc` | MC | 17 | 2 | 31, 32 | MCP2025C_FallProduction CV, `round1-qlmatch/mc_paths-10files/` (files `6548848c…`, `c7d2311d…`) | valfast set, docs 67 and 71 |
| `r2mc` | MC | 13 | 1 | 713 | Gen2_2026 CV v10_14_02_03, first file of `round2-patrec/mc_paths-v10_14_02_03-100files-wcgpu1.lst` (`…7b1f-18f4-1bfb-4f0c`) | valfast set, docs 67 and 71 |
| `beam-off` | data | 1,000 | 1 | 21 runs, 18265–18587 | `data_SBND2026A_gen2_InTime-Run1_v10_14_02_02_reco1_sbnd`, frameshift-merged (`xin-round3-samples/beam-off/`) | doc 115, `work-r3off-*` |
| `mcp1k` | data | 1,000 | 1 | 18255, 18259 | `round2-patrec/data_MCP2025C_reco1_frameshift_first1000ev.root` | "numu 1k" (docs 59, 102, many PR rounds) |
| `mcp2k` | data | 2,000 | 2 | 18255, 18259 | `/nfs/data/1/yuhw/production-prep/add-frameshift-data-2nd-2k-2026-08-15/…_2nd1k_part{1,2}.root` | "numu 2k" (doc 102 onward) |
| `nuecc48` | data | 48 | 1 | 12 runs | `sbnd_xin/input_files_reco1/data_filtered_decoded_reco1-fe6033f3-…_eventidfiltered_frameshift.root` | "nueCC-48" hand-scan set |
| `ncpi0` | data | 19 | 1 | 5 runs | `nc-sideband-lynn/filtered-reco1/nc-sideband_filtered_frameshift.root` | "NCpi0-19" NC-sideband set |

### About "~3000 MC events"

The ~3,000-event set Xin runs most often is **`mcp1k` + `mcp2k`**, but those are **real data**. They come from the
MCP2025C *data* stream, and doc 102 says so directly: *"no MC truth … no efficiency or purity number can be built
from these samples"*. They are in `xin-eval-rse-data.tsv`. His MC with truth is the round-3 pair `mc-cv` + `mc-nuecc`
(4,018 events), plus 30 older MC events in the valfast set. Every MC event above is in `xin-eval-rse-mc.tsv`.

Out of scope: Xin's newer `work-t19/t20/t29` arms use events he simulated himself (e.g. `r24000_s0_e*`, or
resimulations named `Xr296_s86_e1150`), not production files. They do not collide with a production training set.

## How to apply the exclusion

- **Use the right key.** Real data has globally unique (run, subrun, event). Production MC does not: each reco1
  file is one (run, subrun), and event numbers repeat across subruns (`mc-cv` has only 50 distinct event numbers),
  so (run, event) is not enough. Different MC productions can also reuse run numbers. Match on
  **(run, subrun, event) within the same production / SAM definition**, or simply drop whole files using
  `xin-eval-files.tsv`. For these samples the two give the same result, because every staged file was evaluated
  in full.
- **Same-production training samples.** If the training MC is drawn from the two `aurora_SBND2026A_gen2…` SAM
  definitions above, remove those 379 files (or their run/subrun pairs). Any other file from those definitions is
  safe to use.
- **Resimulated events.** If training re-simulates from GENIE/G4 truth of production events, the generator event
  carries the same (run, subrun, event), so the same list applies.

## Checks

- Each sample is internally unique on (run, subrun, event). Across samples there is one collision:
  `18255/1/69314` appears in both `mcp2k` and `nuecc48`, because nueCC-48 was hand-picked from the same data stream.
- The `mc-cv`, `mc-nuecc` and `beam-off` lists match Xin's own census
  (`sbnd_xin/products/d115/{cv,nuecc,off}/file_rse.tsv`) row for row. `mcp1k` matches
  `sbnd_xin/input_files_reco1/staged-mcp2025c-1000evt/entry_event_map.tsv`.

## Reproduce

The lists come from `EventAuxiliary` read with bare ROOT, using the ROOT in `/home/xqian/toolkit-dev/local/bin`:

```bash
cd validation-xin/tools && mkdir -p rows
awk -F'\t' '{printf "%04d\t%s\t%s\t%s\n", NR, $1,$2,$3}' jobs.tsv \
  | xargs -P 16 -L1 bash -c './one.sh "$0" "$1" "$2" "$3"'
cat rows/*.tsv | cut -f1 | sort | uniq -c     # per-sample event counts as in the table above
```

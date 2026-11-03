# The two Aurora campaigns (BNB 1M, nueCC + NC delta-radiative): what was produced, where it is, how to use it for DL-vertex and BDT-tagger training, and what failed

Written 2026-11-03 after the second campaign completed. The per-campaign records are
[`aurora-bnb-1m-production.md`](aurora-bnb-1m-production.md) (issue [#2](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/2))
and [`aurora-rare-nuecc-ncdr-production.md`](aurora-rare-nuecc-ncdr-production.md) (issue [#3](https://github.com/HaiwangYu/sbnd-wirecell-production/issues/3));
this guide is the summary for the people who read the outputs. `$Y` = `/lus/flare/projects/neutrinoGPU/yuhw` on Aurora (ALCF).

## 1. The campaigns at a glance

| | BNB 1M (issue #2) | nueCC (issue #3) | NC delta-radiative (issue #3) |
|---|---|---|---|
| input sample (Avinay) | `/lus/flare/projects/neutrinoGPU/abhat/sbnd/gen2-wct0319-bnb-1m-*`: BNB neutrinos + CORSIKA cosmics, `prodgenie_corsika_proton_rockbox0p1_sbnd` (the CV sample) | `.../abhat/sbnd/gen2-sbnd-ccnue-configL-300k-reco1-flatcaf-v100205-wct0319-20261027/`, the validated-file lists `.../gen2-ccnue-review-20261023/phaseC_result_20261031/ccnue_validated_{flatcaf,reco1}_files.txt` | `.../abhat/sbnd/gen2-sbnd-ncdeltarad-train-configL-reco1-flatcaf-v100205-wct0319-20261029/`, lists `.../ncdeltarad-review-20261029/train/result_8986828/ncdr_validated_{flatcaf,reco1}_files.txt` (5.487e21 POT) |
| sbndcode of the inputs | v10_14_02_03 | v10_14_02_05 (read by the v10_14_02_03 chain) | v10_14_02_05 |
| unit | one flat CAF + its 20 parent reco1 files (~54 events) | one reco1 file + its flat CAF (1:1; 0-15 events, 4.3 on average) | one reco1 file + its flat CAF (1:1; 0-7 events, 0.9 on average; 41 % of the units are empty) |
| units | 11,888 | 62,050 (798 EMPTY) | 29,779 (12,175 EMPTY) |
| CAF events | 627,205 | 268,865 | 26,745 |
| events with Wire-Cell output | **627,127** (99.988 %) | **268,619** (99.91 %) | **26,744** |
| events without | 78 (section 6) | 246 (section 6) | 1 (section 6) |
| ran | 2026-10-22 (two 16-node runs + a tail) | 2026-11-02, jobs 9032475 / 9032476 (8 nodes x 6.3 h each) | 2026-11-02, job 9032556 (8 nodes x 3.5 h) |
| node-hours | 190.6 | ~101 | ~28 |
| outputs | `$Y/production-prep/bnb1m/full/{A,B}/` | `$Y/production-prep/rare/nuecc/full/{A,B}/` | `$Y/production-prep/rare/ncdr/full/work/` |
| merged CAFs | 11,888 (every unit) | 61,242 (every non-EMPTY unit), 361 GB | 17,603, 59 GB |
| disk (`WC_KEEP=semiprod`) | 1.78 TB | 1.13 TB | 0.13 TB |
| pair list (unit -> reco1, CAF, events) | `bnb1m/full/pairs-all.tsv` | `rare/nuecc/full/pairs-all.tsv` (`pairs-A/B.tsv` = the two halves) | `rare/ncdr/full/pairs-all.tsv` |

Software, identical for the three: the Aurora r8 chain of [`aurora-r8-chain.md`](aurora-r8-chain.md) with
wire-cell-toolkit `HaiwangYu/wire-cell-toolkit` branch `sbnd-wc-flatcaf` at **`d06a47d7`**, larwirecell `sbnd-wc-flatcaf` `ad5d942`,
sbndcode `v10_14_02_03 e26:prof` (Flare UPS tree + the `$Y/products` overlay: scn v01_00_00 for the DL vertex),
wire-cell-data `74ff57a` plus the BDT weights `uboone/weights/XGB_nue_seed2_0923.xml` and the SCN vertex model
`uboone/scn_vtx/t48k-m16-l5-lr5d-res0.5-CP24.pth`. The DL-vertex dump (`dl_vtx_dump=true`) was **on** in both campaigns,
so every event carries `T_dlvtx_call` / `T_dlvtx_cloud` (section 4).

The chain, per unit: step 1 = one `lar` job (larwirecell: signal processing, imaging, clustering, flash matching -> `qlpctree.tar.gz`);
step 2 = the standalone Wire-Cell pattern recognition `wct-pr.jsonnet` (trajectory fitting, neutrino pattern, nue/numu taggers,
DL vertex, kinematics) -> one `tracking-pr.root` per event; step 3 = `merge-caf.py` adds the `recTreeWireCell` tree to a byte copy
of the flat CAF; then `validate-merge.py` checks every branch of every row against the per-event files (every unit of both
campaigns is `PASS`).

## 2. Where the files are: the unit directory

Every unit has one directory `<outputs>/node<k>/<unit>/` (`k` = the node that ran it, 0-7 or 0-15; meaningless for the reader).
`<unit>` is the reco1 stem for nueCC / NC (`reco1-detsim-g4-filter-gen-<id>`) and the CAF stem for BNB (`reco2-reco1-detsim-g4-gen-<id>`).

```
<unit>/status                      OK | PARTIAL | EMPTY | FAIL
<unit>/merged/reco2-<...>.wc.flat.caf.root   THE MAIN OUTPUT: the flat CAF + recTreeWireCell (absent for EMPTY and FAIL)
<unit>/merged/merge.json           n_caf_events, n_wirecell_events, n_caf_events_without_wirecell
<unit>/pr/all/pr_evt<run>_<subrun>_<event>/tracking-pr.root   step-2 output per event (the unflattened trees)
<unit>/pr/all/wct.log.gz           the step-2 log
<unit>/ql/all/qlpctree.tar.gz      the step-1 tar (imaging + clustering point clouds, truth tables): step 2 can be rerun from it
<unit>/ql/all/lar.log.gz           the step-1 log (the event order of the unit: OpHitSource "run R subrun S event E" lines)
<unit>/events.json                 per unit: reco1 events, CAF events, events with / without Wire-Cell output, skipped events (rse)
<unit>/validate.json               verdict PASS, rows / values / trees checked
<unit>/good.txt, cost.tsv, run_pair.log, attempts/   bookkeeping; attempts/ keeps the logs of failed step tries
```

`status` meanings: **OK** every CAF event has Wire-Cell output; **PARTIAL** the merged CAF exists but some events have none
(`wc.valid = 0` for them, section 3); **EMPTY** the reco1 file has 0 events (the rare-signal filter), nothing was produced;
**FAIL** no merged file (the step-2 crash hit the unit's first event). Counts per campaign are in section 1 and 6.

To list the merged CAFs without walking the Lustre tree (a `find` over 92k unit directories takes many minutes on the login nodes),
go through the pair lists and the status files:

```bash
# all merged CAFs of the nueCC campaign (two halves)
for W in $Y/production-prep/rare/nuecc/full/A $Y/production-prep/rare/nuecc/full/B; do
  grep -v '^#' $W/pairs.tsv | cut -f1 | while read id; do
    f=$(ls $W/node*/$id/merged/*.wc.flat.caf.root 2>/dev/null); [ -n "$f" ] && echo "$f"; done; done > nuecc-merged.txt
# the same for BNB: $Y/production-prep/bnb1m/full/{A,B}; for NC: $Y/production-prep/rare/ncdr/full/work
```

`pairs.tsv` columns: `id  real  reco1  caf  events` (BNB: `reco1` is the 20 parent paths, comma-separated). The `events` column is the
reco1 sidecar's `event_count`; for nueCC / NC it was trusted as the CAF event count and `validate.json` confirmed it on every unit.

## 3. What is in a merged CAF

The flat CAF is copied byte for byte (all its trees, `recTree` included, untouched), and one tree is added, **`recTreeWireCell`**,
with exactly one entry per `recTree` entry in `recTree`'s order, matched by (run, subrun, event). Its branches carry the prefix `wc.`:

| branches | what |
|---|---|
| `wc.run`, `wc.subrun`, `wc.evt`, `wc.valid` | the event key and **`wc.valid` = 1 if the event has Wire-Cell output, 0 if not** (then every row count is 0) |
| `wc.Trun.*` (48) | the step-2 run record: the BDT and DL weights used (`Trun.bdt_weights_dir`, `Trun.nue_xgboost_xml`, `Trun.dl_*`), trackfitting / nue / numu knobs, beam window |
| `wc.T_tagger.*` (1,862) | one row per neutrino candidate (`nu_index`): the nue and numu tagger variables (every BDT input, by family: `ssm_*` / `ssmsp_*` single-shower, `shw_*` showers, `cosmict_*`, `mip_*`, `br1_*`..`br4_*` / `brm_*` bad reconstruction, `tro_*`, `stw_*`, `vis_*`, `lol_*` / `hol_*`, `pio_*`, `act_*`, `stem_*`, `sig_*`, `spt_*`, `gap_*`, `mgt_*` / `mgo_*`, `anc_*` / `cme_*`, `lem_*`), the flags and scores (`nue_score`, `numu_score`, `numu_1/2/3_score`, `numu_cc_flag*`, `cosmict_score`, `cosmict_*_score`, one `*_score` per family), flash / cluster ids, `match_isFC`, `neutrino_type`, `nu_x/y/z` |
| `wc.T_kine.*` (72) | per candidate: `kine_reco_Enu`, per-particle energies and types, pi0 reconstruction, the SCE-corrected vertex |
| `wc.T_match.*` (40), `wc.T_pf.*` (23), `wc.T_overlap.*` (17) | reco <-> truth matching (`truth_nu_idx`, `truth_trackid`, level / side / obj) and the particle-flow tree |
| `wc.T_truth_nu.*` (16), `wc.T_truth_pf.*` (23), `wc.T_truth_track.*` (26), `wc.T_blob_truth.*` (12) | MC truth: every interaction of the event (`nu_idx`, `pdg`, `ccnc`, `mode`, `int_type`, `E`, `vtx_x/y/z`, `t`, `edep`), truth particles, per-blob truth |
| `wc.T_dlvtx_call.*` (103), `wc.T_dlvtx_cloud.*` (13) | the DL-vertex dump (section 4) |
| `wc.T_cluster`, `T_rec_charge`, `T_segment`, `T_bundle`, `T_flash`, `T_proj`, `T_proj_data`, `T_bad_ch` | the reconstructed clusters, fitted trajectory points with charge, segments, flash bundles, projections, bad channels |

The exact list (2,401 branches, with types and array lengths) is `aurora/schema/recTreeWireCell.schema.json`. Every per-row tree is
flattened as variable-length arrays per event (`..length` / `..idx` companion branches), so a reader that wants plain TTrees per event should
open the per-event `tracking-pr.root` instead: it holds the same trees unflattened (`Trun`, `T_kine`, `T_tagger`, `T_cluster`, `T_rec_charge`,
`T_bad_ch`, `T_proj`, `T_proj_data`, `T_bundle`, `T_flash`, `T_segment`, `T_match`, `T_pf`, `T_overlap`, `T_truth_nu`, `T_truth_pf`,
`T_truth_track`, `T_blob_truth`, `T_dlvtx_call`, `T_dlvtx_cloud`), ~0.9 MB per event.

## 4. DL-vertex training: `T_dlvtx_call` and `T_dlvtx_cloud`

(The full description, with the validation of the dump against standalone inference, is section 6 of
`wire-cell-toolkit-ai-helper/docs/sbnd-r7-dlvtx-campaign.md`; this is the short form.)

Per neutrino candidate (flash bundle), `TaggerCheckNeutrino` calls the SCN vertex network up to twice: the dual-chain OFF pass
(`pass = 1`, exclusion-free) and the production pass (`pass = 0`). With the dump on, every call is recorded as it happened; nothing
recorded feeds back into the reconstruction. Units are cm and GeV; positions are in the reconstructed (cloud) frame, i.e. after the
cluster t0 correction and including the space-charge displacement.

- **`T_dlvtx_call`**, one row per network call, key (`runNo`, `subRunNo`, `eventNo`, `nu_index`, `call_index`): `pass`, `status`
  (0 ok), `n_points`, `n_vertex_rows` (the first `n_vertex_rows` cloud points are PR-graph vertices, the rest segment-interior fit
  points), `q_scale` / `q_offset`, the raw network `payload` ([x, y, z, score] x K), the traditional vertex `trad_*`, this call's pick
  `rerank_*`, the accepted DL vertex `dl_*` (`accepted`), the candidate's final vertex `final_*`, and the MC labels `truth_*`
  (raw true vertex, no SCE), **`truth_reco_*`** (the same vertex moved by the TrueFwd SCE map into the cloud frame), plus every
  interaction of the event as vectors `truth_all_*` / `truth_all_reco_*` with `truth_all_edep`.
- **`T_dlvtx_cloud`**, one row per network-input point: the call key, `ipoint`, `is_vertex`, and the **exact float32 `x`, `y`, `z`, `q`
  the network received**. (The final fit points in `T_rec_charge` are not the network input: they come after the refit around the
  chosen vertex.)

Recipe (what `dlvtx-truth-eval.py` of ai-helper issue 35 does):
1. keep calls with `status == 0`, `truth_valid == 1`, `truth_sce_applied == 1`;
2. **the target is `truth_reco_x/y/z`**, in the active volume (|x| < 200, |y| < 200, 0 < z < 500 cm);
3. events hold several interactions (rockbox / dirt neutrinos) and may hold several candidates: keep a candidate only if the label belongs
   to it, e.g. its production cloud has a point within ~3 cm of `truth_reco_*`, or pick per candidate the closest `truth_all_reco_*`
   entry with `truth_all_edep > 0`;
4. both clouds of a candidate (`pass` 0 and 1) take the same label;
5. join the two trees on (`runNo`, `subRunNo`, `eventNo`, `nu_index`, `call_index`).

```python
import ROOT
f = ROOT.TFile.Open('.../pr_evt<run>_<subrun>_<event>/tracking-pr.root')
calls = {}
for c in f.T_dlvtx_call:                      # PyROOT reuses the entry object: copy the fields you need
    calls[(c.nu_index, c.call_index)] = dict(pass_=c.__getattr__('pass'), status=c.status,
                                             target=(c.truth_reco_x, c.truth_reco_y, c.truth_reco_z), valid=c.truth_valid)
pts = {}
for p in f.T_dlvtx_cloud:
    pts.setdefault((p.nu_index, p.call_index), []).append((p.x, p.y, p.z, p.q))
```

Which sample for what: **nueCC** gives 268,619 events of CC nu-e interactions (the vertex is the electron-shower start; the sample the
tagger must accept); **BNB CV** gives 627,127 events of the beam mix with cosmics (numu CC, NC, and events with no neutrino in
the TPC: the `truth_n` / `truth_all_*` vectors tell which); **NC delta-radiative** gives 26,744 events of the single-photon background to nue.
The `payload` scores differ at the 1e-6 level between hosts (float32) and two voxels with equal score can swap rank, so do not compare
payloads bit for bit across productions.

## 5. BDT-tagger training: `T_tagger`, `T_kine` and the truth

The nue tagger in these files is the ported MicroBooNE one, run with `XGB_nue_seed2_0923.xml` (`Trun.nue_xgboost_xml`); its scores
(`T_tagger.*_score`, `nue_score`-like branches) are the output of **that** BDT and are not labels. For a retraining on SBND:

- **Inputs:** the ~1,800 per-candidate variables of `T_tagger` (the exact set the MicroBooNE BDTs consume, one row per candidate
  `nu_index`), with `T_kine` for the reconstructed energy (`kine_reco_Enu`, per-particle energies, pi0 variables). Read them from the
  merged CAFs (`wc.T_tagger.*`, flattened per event with `..length`) or the per-event files (one `T_tagger` row per candidate).
- **Labels:** `T_truth_nu` (per interaction: `pdg`, `ccnc`, `mode`, `E`, `vtx_*`, `edep`) joined to the candidate through `T_match`
  (`nu_index` <-> `truth_nu_idx`, with `level` / `side` / `obj` telling how the match was made) or, simpler, through the vertex
  distance as in section 4. The CAF's own `recTree` truth (`rec.mc.nu`) is in the same file and keyed by the same event.
- **Classes:** signal = nueCC candidates matched to the true nu-e CC interaction; backgrounds = BNB CV candidates (numu CC, NC, cosmic-only
  events) and NC delta-radiative candidates (single photon). Weights: BNB CV is 627k events of the beam mix with the rockbox cosmics;
  nueCC and NC delta-rad are filtered rare-signal samples (POT in the reco1 sidecars' `mc.pot`; NC delta-rad 5.487e21 POT in total).
- **Containment and flash:** `T_tagger.match_isFC`, `matched_flash_gid`, and `T_flash` / `T_bundle` for the flash match; `T_kine`
  for the SCE-corrected vertex.

## 6. What failed, where, and what to do about it

Nothing is silently missing: every CAF event is in the merged CAF, and `wc.valid = 0` marks the ones without Wire-Cell output.
The complete list of those events, with run / subrun / event, the cause and the input files, is
[`aurora-campaigns-lost-events.tsv`](aurora-campaigns-lost-events.tsv) (built by `$Y/production-prep/rare/lost-events.py`
from the unit logs; the BNB 13 step-1 events are also in [`aurora-bnb-1m-skipped-events.tsv`](aurora-bnb-1m-skipped-events.tsv)).

| campaign | events without Wire-Cell output | cause |
|---|---|---|
| BNB 1M | 78 of 627,205 | 13: step-1 `lar` killed by the RSS watchdog (48 GB) inside `ClusteringDeghost`, all events with 0 neutrinos (section 6a); 65: step-2 crashes on nodes that were swapping in run 1 (18 PARTIAL units; environmental, not reproduced in run 2) |
| nueCC | 246 of 268,865 | 183 in 75 PARTIAL units + 55 in 10 FAIL units: the step-2 crash (section 6b); 7: step-1 RSS watchdog, same signature as BNB; 1: step-2 timeout (4 h, both tries) |
| NC delta-rad | 1 of 26,745 | the step-2 crash on a 1-event unit (FAIL) |

### 6a. Step 1: the memory runaway in `ClusteringDeghost` (13 + 7 events)

Signature (identical in both campaigns): the step-1 `lar` log ends with the `MABC timing: ClusteringSeparate:apa<N>-0` line, i.e. the
next algorithm, **`ClusteringDeghost`**, is running when the resident size climbs at ~1 GB/s from 1.6 GB to the 48 GB watchdog limit
(54-69 GB when it was first seen in BNB run 2, where it took nine nodes into swap before the watchdog existed). In BNB the events had
`truth: 0 nu` and a very large cluster (`get_hull ... 15,000-18,000 points`, the quick-hull of the cluster boundary). The driver skips
the event (`events.json: skipped[].rse`, rc 137), reruns the other events of the unit and the unit ends PARTIAL. The 20 events are
listed in the tsv with cause `step1-rss-watchdog`. This is deterministic in the event (BNB run 2 reproduced run 1's events) and a
toolkit issue (`clus` `ClusteringDeghost` / `get_hull`), not yet filed upstream.

### 6b. Step 2: the crash in the pattern-recognition stage (~1 per 320 nueCC events)

Step 2 (`wire-cell` running `wct-pr.jsonnet`) crashed **831 times in 61,170 nueCC runs** (rc 139 SIGSEGV 663, rc 134 abort 162,
rc 133 2, rc 124 timeout 2), twice in 17,603 NC runs, and only on run-1's swapping nodes in BNB. The pool retries a crashed step 2 once:
659 units crashed once and completed on the retry; the 86 units that crashed twice lost the events from the (later) crash point onward.

Where it crashes (`$Y/production-prep/rare/crash-sites.tsv`, built by `crash-sites.py` from all 831 logs):

| last toolkit log line before the crash | tries |
|---|---|
| `clus.TrackFitting fit_blob_coverage` | 390 |
| `clus.NeutrinoPattern pr55` (`do_rough_path`, ...) | 112 |
| `CreateSteinerGraph` (`pr` / `prrefresh`, `create_steiner_tree`) | 83 |
| `clus.TrackFitting do_multi_tracking` | 31 |
| `clus.NeutrinoPattern examiner` / `mvga` | 36 |
| `MultiAlgBlobClustering:clus_pr` (MABC timing / loading tensor set) | 34 |
| `TaggerCheckNeutrino:pr` (`nue_tagger` volume) | 15 |
| `raygrid activity::subspan`, `SbndPrMagnifyTrackingVisitor`, other | 22 |

The C++ backtrace is readable in only ~36 logs (see the Go note below); where it is, the frames are
`PatternAlgorithms::break_segment_into_two < break_segments < find_other_segments` (16),
`TrackFitting::do_multi_tracking < examine_vertices_1 < examine_vertices < find_proto_vertex` (12),
`Graphed::descriptor_valid < bad_reconstruction < multiple_showers < nue_tagger` (6), `crawl_segment < examine_segment` (2),
all under `TaggerCheckNeutrino::run_dual_chain_off_pass` / `visit`. **So the crash is in the PR stage (trajectory fitting, Steiner
graph, neutrino pattern / taggers), not in deghosting or the quick hull** (those are the step-1 problem of 6a). The failed tries' peak
RSS is 4.2 GB (median; max 4.4) against 1.3 GB for a normal step 2: the same "runaway allocation reached through
`improve_vertex` / `do_multi_tracking`" signature that `sbnd-r7-dlvtx-campaign.md` section 9 found on sbndbuild03 (crash sites
`TrackFitting::update_association`, `Steiner::Grapher::find_peak_point_indices`), at a similar rate on nueCC (1 per 550 events there).

Deterministic or not: of the 86 twice-crashed units, 63 died on the same event both times and 23 on different events; the r7 study
found the same tar crashing in 3 of 4 runs. So it is partly reproducible, partly not, and the nueCC rate (1 per 320 events) is ten
times the NC rate (2 per 26,744): big showers trigger it.

Two reading aids for the logs:
- `wire-cell` on Aurora links **go-jsonnet** (`gojsonnet v0_18_0`, `libjsonnet.so`), so the Go runtime's signal handler also reacts to
  the C++ SIGSEGV and prints `fatal error: unknown caller pc` with a Go stack; in 85 % of the logs that is all there is (the ROOT
  `*** Break *** segmentation violation` backtrace is printed in the other 15 %). The Go text is a symptom, not a second crash. For a
  crash study, set `GOTRACEBACK=none` or build against the C++ jsonnet.
- `attempts/step2-all-try<N>/wct.log.gz` keeps every failed try; `loading tensor set ident=<N>` is the last event started (ident =
  the event's index within the unit's tensor file, not the art event number).

### 6c. Suggested check: run the lost events on FermiGrid

Before anyone debugs the toolkit on these, run the same events through the same chain on FermiGrid / sbndgpvm (same code pins, no
Aurora contention, the ordinary memory) and see whether they still fail:

1. Units: `aurora-campaigns-lost-events.tsv` gives per lost event the unit, its reco1 and CAF; the reco1 / CAF files are on Flare under
   Avinay's directories (section 1) and were produced on Polaris / FermiGrid with the same sbndcode, so the FermiGrid side needs the
   same files staged (or the equivalent SAM-declared copies). A pairs file for them in `find-pairs.py` format (`id  real  reco1  caf  events`) is the matching lines of the campaign's
   `pairs-all.tsv`: `grep -v '^#' <tsv> | cut -f3 | sort -u | grep -F -f - <outputs>/pairs-all.tsv`, one unit per job.
2. Submit with `fermigrid/bin/submit.sh <tarball> <pairs.tsv> 1 <sample> <tag>` (`fermigrid/README.md`); the job runs
   `aurora/bin/run_pair.py` unchanged, so a crash leaves the same `attempts/`, `events.json` and `status` as on Aurora. For a single
   event interactively, run step 1 on it alone with lar's `--nskip <index> -n 1` (what the driver does when it slices around a bad
   event; index = the event's position in the unit's event order, from the `lar.log.gz` OpHitSource lines), then `step2.sh` on the tar.
3. Read the outcome per event: completes on FermiGrid and not on Aurora -> environmental (memory / contention / the Go handler); fails
   the same way -> a deterministic reproducer for the toolkit (`clus`), to be filed with the `qlpctree.tar.gz` of the unit (kept in
   `ql/all/`, so step 2 can be replayed anywhere without `lar`: `aurora/bin/step2.sh <tar> <outdir> sim`).
4. The 20 step-1 events (6a) need `lar` and the reco1 file; `qlpctree.tar.gz` does not exist for them.

Separately, the events lost after a crash point (183 + 1 + 7 of the 246 + 1) can be recovered on Aurora by a step-2 rerun of the 94 units
one event at a time from their `ql/all/qlpctree.tar.gz`, skipping the crashing event; this was deferred together with the multi-pair
optimisation (issue #3) and is not started.

## 7. Reading the outputs without getting bitten

- **Key everything on (run, subrun, event).** Gen2 event numbers restart in every subrun, so an event number alone is not unique inside
  a unit (BNB units span 20 files; nueCC units span several subruns). The per-event directories are named `pr_evt<run>_<subrun>_<event>`
  for that reason.
- **Expect events with `wc.valid = 0`** (section 6) and units with no `merged/` (EMPTY: 798 nueCC, 12,175 NC; FAIL: 10 nueCC, 1 NC).
  `events.json` of a unit tells which events are affected.
- **Do not compare ROOT or zip files byte for byte** (timestamps, compression, float32 network scores); compare trees and values.
- **The CAF part is untouched**: everything the CAF had (`recTree`, `globalTree`, POT trees, `rec.mc.*`, `rec.slc.*`) is there as Avinay
  produced it; `recTreeWireCell` is purely additional. Nothing in the input directories was modified.
- **Lustre is slow at metadata on the login nodes**: do not `find` or `du` across the unit trees casually; use `pairs.tsv`, the node
  `pool.log` files (one line per finished unit) and the per-unit `status` files.
- **Per-event files vs merged CAF:** the per-event `tracking-pr.root` are the simplest for training (plain trees, one event, ~0.9 MB);
  the merged CAFs are for the CAF-based analysis flow. Both carry the same numbers.

## 8. Change log

- 2026-11-03: first version, after the nueCC / NC campaign (issue #3) completed; `aurora-campaigns-lost-events.tsv` added.

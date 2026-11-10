// SBND Wire-Cell productions catalog -- the single data file behind docs/index.html.
// Sources: HaiwangYu/sbnd-wirecell-production issues and HaiwangYu/wire-cell-toolkit-ai-helper issues.
// To update: edit this file only (see docs/README.md). Keep facts traceable to an issue comment.
window.CATALOG = {
  updated: "2026-11-10",

  // Where a production sits. "training" = Aurora, Avinay's privately generated gen2 MC, plus the
  //   training half of the FNAL beam-off data (real data cannot be regenerated, so fg1 beam-off is split by run).
  // "evaluation" = FNAL (FermiGrid, sbndbuild03), official Gen2 SAM definitions.
  sides: {
    training: {
      title: "Training (Aurora MC + fg1 beam-off odd runs)",
      blurb: "MC: run on ALCF Aurora over samples generated privately by Avinay (gen2, wct 0319), not drawn from the official SAM definitions. Beam-off data: real data cannot be regenerated, so the FNAL fg1 beam-off production is split by run number; the odd-run half is the training sample (the even-run half is on the evaluation side)."
    },
    evaluation: {
      title: "Evaluation (FNAL: FermiGrid + sbndbuild03)",
      blurb: "Run at Fermilab over the official Gen2 SAM definitions (MC and data)."
    }
  },

  species: [
    { key: "mc-bnb",     name: "MC BNB (CV / inclusive)" },
    { key: "mc-nuecc",   name: "MC nueCC" },
    { key: "mc-ncdr",    name: "MC NC Δ-radiative" },
    { key: "beam-on",    name: "Beam-on data (BNB)" },
    { key: "beam-off",   name: "Beam-off data (off-beam / InTime)" }
  ],

  // A configuration = chain + builds + key knobs. Productions that share one share a label.
  configs: {
    "aurora-r2": {
      side: "training",
      summary: "aurora-r1 step 1 reused; step 2 rerun with T_dlvtx_space (Bee space points for DL vertex training) and the WCT PR #544 review fixes.",
      chain: "step 1: not rerun (aurora-r1 qlpctree tars, hardlinked) → step 2 wct-pr.jsonnet (DL vertex + dump + T_dlvtx_space, flat tree, MC truth match) → merge into the flat CAF → value-by-value validation",
      toolkit: "fork sbnd-dlvtx-space-44 55177882 (= sbnd-wc-flatcaf d5bd7851 + T_dlvtx_space)",
      larwirecell: "ad5d942 (step 1 of aurora-r1)",
      workflow: "sbnd-wirecell-production 9959484",
      schema: "af9c87c8 (2,416 branches; production schema + 15 new)",
      keep: "semiprod (merged CAF + per-event tracking-pr.root, no Bee)",
      knobs: "DLVTX_SPACE=true, dl_vtx_dump=true, flat_tree=true, truth_match=true",
      issues: ["prod#4"]
    },
    "aurora-r1": {
      side: "training",
      summary: "The Aurora 2-step chain, validated against r8 (gate G4), with the per-event naming and TensorFileSource fixes.",
      chain: "step 1 lar wcls-img-clus-matching.fcl → step 2 wct-pr.jsonnet (DL vertex + dump, flat tree, MC truth match) → merge into the flat CAF → validation",
      toolkit: "fork sbnd-wc-flatcaf d06a47d7 (= 4b6853d4 + Clus::per_event_name + TensorFileSource fix)",
      larwirecell: "sbnd-wc-flatcaf ad5d942",
      workflow: "sbnd-wirecell-production aurora/ (BNB: b439630 + 8e392f2/1e4fddd fixes; nueCC/NC: a0227bc layout pr_evt{run}_{subrun}_{event})",
      schema: "production schema (as fg1)",
      keep: "semiprod (qlpctree, tracking-pr.root, merged CAF, logs)",
      knobs: "dl_vtx_dump=true, truth match on; step-1 RSS watchdog 48 GB; units: BNB = 1 CAF + its 20 parent reco1, nueCC/NC = 1 reco1 + 1 CAF",
      issues: ["prod#2", "prod#3"]
    },
    "fg1": {
      side: "evaluation",
      summary: "The r8 workflow run on FermiGrid with jobsub_lite; grid test identical value by value to r8 (7 pairs, 108 events).",
      chain: "data: FrameShift → step 1 wcls-img-clus-matching{,-data}.fcl → step 2 wct-pr.jsonnet (DL vertex + dump, flat tree, MC truth match) → merge into the flat CAF → validation",
      toolkit: "fork sbnd-wc-flatcaf 4b6853d4",
      larwirecell: "sbnd-wc-flatcaf ad5d942",
      workflow: "fg1: 44af3b7 / 1bacc54; run3bnb: c93da2c (= fg1 + job.sh bookkeeping fixes d83d26e)",
      schema: "d4396a3490ea (2,401 branches, 20 trees)",
      keep: "semiprod; merged CAFs copied to dCache persistent, the rest stays on scratch",
      knobs: "cfg wcp-porting-validation 88cb05aa, wire-cell-data 9e2f4b8, sbndcode v10_14_02_03 e26:prof (CVMFS), SL7 image; 1 CPU, 4000 MB + auto-release",
      issues: ["prod#1", "prod#5"]
    },
    "r8": {
      side: "evaluation",
      summary: "2-step + truth match + CAF merge on sbndbuild03. Same toolkit as fg1; fg1's grid test reproduced it exactly.",
      chain: "as fg1",
      toolkit: "sbnd-wc-flatcaf 4b6853d4",
      larwirecell: "73c79bc",
      workflow: "load-governed run on sbndbuild03 (ai-helper #42)",
      schema: "d4396a3490ea",
      keep: "semiprod; validation mode (~100 events per sample) adds Bee",
      knobs: "",
      issues: ["aih#42"]
    },
    "opendata": {
      side: "evaluation",
      summary: "A configuration similar to fg1; the main difference is that tracking-pr.root was not saved. 2-step + CAF merge over every FixedDev BNB reco1 file, paired with the gen2 FixedDev Respin flat CAF.",
      chain: "as fg1 for data: FrameShift → step 1 → step 2 → merge into the flat CAF → validation",
      toolkit: "f6fd2209",
      larwirecell: "3b54651",
      workflow: "ai-helper #39/#40 workflow on sbndbuild03",
      schema: "c845fe94fbe5 (2,283 branches, 15 trees; a strict subset of fg1's)",
      keep: "minimal (qlpctree, merged CAF, logs; no tracking-pr.root — the per-event trees are inside the merged CAF)",
      knobs: "",
      issues: ["aih#40"]
    },
    "r7": {
      side: "evaluation",
      summary: "2-step with dl_vtx_dump on WCT master b7bd2a1a (Xin's match_isFC + new prompt-time flash rule). Before the CAF merge existed.",
      chain: "step 1 lar → qlpctree.tar.gz → step 2 wct-pr.jsonnet; no CAF merge",
      toolkit: "master b7bd2a1a", larwirecell: "not stated", workflow: "", schema: "—", keep: "tracking-pr.root + qlpctree",
      knobs: "dl_vtx_dump=true, T_truth_* on MC", issues: ["aih#38"]
    },
    "r6": {
      side: "evaluation", summary: "r7's samples on toolkit 21562551; stopped after a machine crash.",
      chain: "2-step", toolkit: "21562551", larwirecell: "189ad26", workflow: "", schema: "—", keep: "", knobs: "dl_vtx_dump=true", issues: ["aih#38"]
    },
    "r5": {
      side: "evaluation", summary: "First run of our larwirecell 2-step chain with dl_vtx_dump, over the #30 samples prepared for Xin.",
      chain: "step 1 lar wcls-img-clus-matching{,-data}.fcl → step 2 wct-pr.jsonnet", toolkit: "sbnd-dlvtx-35 78f81c64", larwirecell: "189ad26",
      workflow: "wcp-porting-validation 072505ce", schema: "—", keep: "ql + pr", knobs: "dl_vtx_dump=true, T_truth_* on MC", issues: ["aih#38"]
    },
    "r3": {
      side: "evaluation", summary: "Round 3: the 1-step chain validated against Xin's 2-step (#24) at the 09-08 operating point.",
      chain: "1-step img-clus-match-tag-PR (wcls-img-clus-matching-xin{,-data}.fcl)", toolkit: "master-2026-09-08+yuhw 0ad64223",
      larwirecell: "not stated", workflow: "cfg wcp-porting-img e100a631", schema: "—", keep: "Bee + tracking-pr",
      knobs: "DL vertex CP24, nugraph off, OpFlash light", issues: ["aih#26"]
    },
    "sync": {
      side: "evaluation", summary: "1-step + PR with the operating point synchronised to Xin's 2-step (2026-08-30).",
      chain: "1-step img/clus/match/tag/PR + nugraph h5", toolkit: "ap-yuhw + apply-pointcloud (hashes in the #20 doc §6)",
      larwirecell: "", workflow: "", schema: "—", keep: "Bee, tracking-pr, nugraph", knobs: "", issues: ["aih#19", "aih#20"]
    },
    "preflip": {
      side: "evaluation", summary: "1-step + PR ('Route A') with the 160 PR knobs at their defaults, before the #17 sync.",
      chain: "1-step img/clus/match/tag/PR + nugraph h5", toolkit: "ap-yuhw + apply-pointcloud merge (opt built 2026-08-20)",
      larwirecell: "", workflow: "", schema: "—", keep: "Bee, tracking-pr, nugraph", knobs: "", issues: ["aih#16", "aih#18"]
    },
    "tag": {
      side: "evaluation", summary: "1-step imaging/clustering/matching/taggers, no pattern recognition.",
      chain: "1-step img/clus/match/tag", toolkit: "ap-yuhw 06a02ccb", larwirecell: "dev-v10_14_02_02 3b07b85",
      workflow: "wcp-porting-img b3efbd3", schema: "—", keep: "mabc.zip", knobs: "no PR", issues: ["aih#11"]
    }
  },

  // status: "available" (merged outputs present, <1% of events without Wire-Cell output;
  //         evictable scratch products are noted in status_note), "running",
  //         "partial" (>=1% of events failed, or main outputs deleted),
  //         "deleted", "unverified" (not checked; issue says nothing about deletion).
  productions: [
    // ---------------- training: Aurora ----------------
    { id: "aurora-r2-bnb", species: "mc-bnb", side: "training", config: "aurora-r2", site: "Aurora",
      title: "BNB CV 1M reprocessed with T_dlvtx_space", date: "2026-11-05", issues: ["prod#4"],
      input: "Avinay's gen2-wct0319 BNB CV (sbndcode v10_14_02_03); same 11,888 units as aurora-r1",
      events: 627205, events_wc: 627114, units: "11,888: 11,872 OK, 16 PARTIAL",
      output: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/dlspace/bnb/node<k>/<unit>/merged/",
      list: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/dlspace/lists/bnb-merged-cafs.txt",
      size: "merged CAFs 421.0 GB", status: "available", status_note: "checked on Flare 2026-11-09",
      note: "Same events as aurora-r1 BNB. 91 events without Wire-Cell output (13 step-1 skips + 78 in 3 units); production lost 78." },
    { id: "aurora-r1-bnb", species: "mc-bnb", side: "training", config: "aurora-r1", site: "Aurora",
      title: "BNB CV 1M", date: "2026-10-22", issues: ["prod#2"],
      input: "Avinay's gen2-wct0319 BNB CV, shard01–03 + batch01–09 (1 CAF + 20 parent reco1 per unit)",
      events: 627205, events_wc: 627127, units: "11,888: 11,870 OK, 18 PARTIAL",
      output: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/bnb1m/full/{A,B}/node<k>/<unit>/merged/",
      size: "~1 TB at semiprod (pre-run estimate)", status: "available", status_note: "checked on Flare 2026-11-09",
      note: "78 events without Wire-Cell output: 13 skipped in step 1 (ClusteringDeghost), 65 step-2 segfaults." },
    { id: "aurora-r2-nuecc", species: "mc-nuecc", side: "training", config: "aurora-r2", site: "Aurora",
      title: "nueCC reprocessed with T_dlvtx_space", date: "2026-11-08", issues: ["prod#4"],
      input: "Avinay's gen2-sbnd-ccnue-configL-300k (sbndcode v10_14_02_05, wct0319); same non-empty units as aurora-r1",
      events: 268865, events_wc: 268789, units: "61,252: 61,225 OK, 23 PARTIAL, 4 FAIL",
      output: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/dlspace/nuecc/node<k>/<unit>/merged/",
      list: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/dlspace/lists/nuecc-merged-cafs.txt",
      size: "merged CAFs 374.9 GB", status: "available", status_note: "checked on Flare 2026-11-09",
      note: "76 events without Wire-Cell output (aurora-r1: 246); every remaining bad unit also failed in aurora-r1." },
    { id: "aurora-r1-nuecc", species: "mc-nuecc", side: "training", config: "aurora-r1", site: "Aurora",
      title: "nueCC 269k", date: "2026-11-03", issues: ["prod#3"],
      input: "/lus/flare/projects/neutrinoGPU/abhat/sbnd/gen2-sbnd-ccnue-configL-300k-reco1-flatcaf-v100205-wct0319-20261027 (validated list, 62,050 files)",
      events: 268865, events_wc: 268619, units: "62,050: 61,159 OK, 798 EMPTY, 83 PARTIAL, 10 FAIL",
      output: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/rare/nuecc/full/{A,B}/node<k>/<unit>/merged/",
      size: "merged CAFs 361 GB; 1.13 TB at semiprod", status: "available", status_note: "checked on Flare 2026-11-09", note: "" },
    { id: "aurora-r2-ncdr", species: "mc-ncdr", side: "training", config: "aurora-r2", site: "Aurora",
      title: "NC Δ-rad reprocessed with T_dlvtx_space", date: "2026-11-05", issues: ["prod#4"],
      input: "Avinay's NC Δ-rad train sample; same non-empty units as aurora-r1",
      events: 26745, events_wc: 26744, units: "17,604: 17,603 OK, 1 FAIL",
      output: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/dlspace/ncdr/node<k>/<unit>/merged/",
      list: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/dlspace/lists/ncdr-merged-cafs.txt",
      size: "merged CAFs 59.7 GB", status: "available", status_note: "checked on Flare 2026-11-09", note: "" },
    { id: "aurora-r1-ncdr", species: "mc-ncdr", side: "training", config: "aurora-r1", site: "Aurora",
      title: "NC Δ-radiative 27k (train)", date: "2026-11-03", issues: ["prod#3"],
      input: "/lus/flare/projects/neutrinoGPU/abhat/sbnd/gen2-sbnd-ncdeltarad-train-configL-reco1-flatcaf-v100205-wct0319-20261029 (29,779 files, 5.487e21 POT)",
      events: 26745, events_wc: 26744, units: "29,779: 17,603 OK, 12,175 EMPTY, 1 FAIL",
      output: "/lus/flare/projects/neutrinoGPU/yuhw/production-prep/rare/ncdr/full/work/node<k>/<unit>/merged/",
      size: "merged CAFs 59 GB; 127 GB at semiprod", status: "available", status_note: "checked on Flare 2026-11-09", note: "" },

    { id: "fg1-beamoff-train", species: "beam-off", side: "training", config: "fg1", site: "FermiGrid",
      title: "Beam-off (InTime) training subset: odd runs of fg1 beam-off", date: "2026-11-09", issues: ["prod#1"],
      input: "fg1 beam-off (SAM data_SBND2026A_gen2_InTime-Run1_v10_14_02_02_reco1_sbnd), files of odd run numbers: 80 runs, 18253–18591",
      events: 27076, events_wc: 27067, units: "572 pairs: 569 OK, 3 PARTIAL",
      output: "/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/beam-off-train/<id> -> ../beam-off/<id> (relative symlinks to the merged-CAF folders; README.md and lists/)",
      size: "merged CAFs 4.40 GB (persistent); the pairs' tracking-pr tars and qlpctrees are listed in lists/ (dCache scratch, evictable)", status: "available",
      status_note: "checked 2026-11-10 (prod#1 comment 2026-11-10): 572 links, every one resolves to a non-empty merged CAF",
      note: "Split of fg1 beam-off by run parity (owner, 2026-11-09): disjoint from fg1-beamoff-eval in runs and files. Every file of this sample has art subrun 1, so a subrun split was not possible. 123 of its files are r8 beam-off files (r7 events)." },
    // ---------------- evaluation: FNAL ----------------
    { id: "fg1-cv", species: "mc-bnb", side: "evaluation", config: "fg1", site: "FermiGrid",
      title: "MC BNB CV 500k", date: "2026-10-18", issues: ["prod#1"],
      input: "SAM aurora_SBND2026A_gen2_BNBLight_prodgenie_corsika_proton_rockbox0p1_sbnd_CV_v10_14_02_03_reco1_sbnd / ..._flatcaf_sbnd (seeded random, r8 files first)",
      events: 500000, events_wc: 499899, units: "37,742 pairs: 37,720 OK, 22 PARTIAL",
      output: "/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/mc-cv/<id>/ (merged CAFs, 447 GB)",
      size: "tracking-pr 276 GB + qlpctree 912 GB on scratch only", status: "available",
      status_note: "checked 2026-11-09 (prod#1 comment 2026-11-09): 37,742 merged CAFs on persistent (447.3 GB, none empty); scratch still holds all 37,742 tracking-pr tars (276.2 GB) and 37,761 qlpctrees (912.0 GB). 30 merged CAFs that dCache had emptied (2026-10-18/21) were restored from scratch 2026-10-28.",
      note: "Event list: prod-fermigrid/fg1/lists/events-mc-cv.tsv.gz." },
    { id: "r8-cv", species: "mc-bnb", side: "evaluation", config: "r8", site: "sbndbuild03",
      title: "MC BNB CV (r7 events)", date: "2026-10-16", issues: ["aih#42"],
      input: "the 1000-file CV list of #16/#26 (990 pairs)", events: 13113, events_wc: 13112, units: "990: 989 OK, 1 PARTIAL",
      output: "/exp/sbnd/data/users/yuhw/production-prep/r8-r26-truth-caf/{validation,semiprod}/mc-cv/", size: "98 GB for all r8 samples",
      status: "available", status_note: "checked 2026-11-09 on sbndbuild03 (prod#1 comment 2026-11-09): semiprod: 990 merged CAFs (989 OK + 1 PARTIAL, 11.7 GB) + 13,112 tracking-pr.root (7.2 GB); validation: 7 pairs / 113 events with Bee; none empty. r8 total 98 GB.", note: "Every r8 pair is also in fg1." },
    { id: "fg1-nuecc", species: "mc-nuecc", side: "evaluation", config: "fg1", site: "FermiGrid",
      title: "MC nueCC 100k", date: "2026-10-18", issues: ["prod#1"],
      input: "SAM aurora_SBND2026A_gen2_BNBLight_prodgenie_corsika_proton_rockbox0p1_sbnd_EX_nuecc_v10_14_02_05_reco1_sbnd / ..._flat_caf_sbnd",
      events: 100003, events_wc: 99946, units: "11,445 pairs: 11,421 OK, 20 PARTIAL, 4 EMPTY",
      output: "/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/mc-nuecc/<id>/ (merged CAFs, 123 GB)",
      size: "tracking-pr 102 GB + qlpctree 202 GB on scratch only", status: "available",
      status_note: "checked 2026-11-09 (prod#1 comment 2026-11-09): 11,441 merged CAFs on persistent (122.5 GB, none empty); scratch still holds all 11,441 tracking-pr tars (102.3 GB) and 11,456 qlpctrees (202.0 GB). 2 merged CAFs that dCache had emptied were restored 2026-10-28.",
      note: "SAM has one nueCC sample; fg1 used most of it (only 2,023 unused files with a CAF remain)." },
    { id: "r8-nuecc", species: "mc-nuecc", side: "evaluation", config: "r8", site: "sbndbuild03",
      title: "MC nueCC (r7 events with a CAF)", date: "2026-10-16", issues: ["aih#42"],
      input: "the 1000-file nueCC list of #19/#26 (944 pairs; 55 files without a CAF skipped)", events: 8145, events_wc: 8145, units: "944 OK",
      output: "/exp/sbnd/data/users/yuhw/production-prep/r8-r26-truth-caf/{validation,semiprod}/mc-nuecc/", size: "",
      status: "available", status_note: "checked 2026-11-09 on sbndbuild03 (prod#1 comment 2026-11-09): semiprod: 944 merged CAFs (10.0 GB) + 8,145 tracking-pr.root (8.3 GB); validation: 11 pairs / 103 events with Bee; none empty. r8 total 98 GB.", note: "Every r8 pair is also in fg1." },
    { id: "run3bnb", species: "beam-on", side: "evaluation", config: "fg1", site: "FermiGrid",
      title: "Run 3 BNB data (Fixed Dev, unblinded)", date: "2026-11-08", issues: ["prod#5"],
      input: "SAM data_SBND2026A_Gen2_Run3_BeamLight_Fixed_Dev_Data_v10_14_02_08_reco1_sbnd / ..._flatcaf_sbnd (runs 20586–20597, 5e18 POT)",
      events: 109487, events_wc: 109415, units: "2,208 pairs: 2,204 OK, 4 PARTIAL (736 jobs, cluster 87458459@jobsub01)",
      output: "/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/run3bnb/bnb-data/<id>/ (merged CAFs, 26.6 GB, ADLER32-checked; README.md and lists/)",
      size: "qlpctree, tracking-pr tar and logs on scratch only (/pnfs/sbnd/scratch/users/yuhw/prod-fermigrid/run3bnb/bnb-data/)", status: "available",
      status_note: "checked 2026-11-09 (prod#1 comment 2026-11-09): 2,208 merged CAFs on persistent (26.6 GB, none empty); scratch still holds all 2,208 tracking-pr tars (43.3 GB) and 2,210 qlpctrees (216.3 GB).",
      note: "Campaign finished 2026-11-09; the 72 events without Wire-Cell output are kept with wc.valid = 0 in the merged CAFs. 70 are in 2 pairs whose step 2 was killed for memory in CreateSteinerGraph (70075734: 48, 13d07c95: 22); 2 are step-1 ClusteringConnect1 segfaults. The 70 are recoverable by rerunning step 2 without the grid memory cap from the scratch qlpctrees (copy them to persistent first). Workflow pinned to c93da2c: main's per-event naming needs a newer toolkit than the fg1 build." },
    { id: "opendata", species: "beam-on", side: "evaluation", config: "opendata", site: "sbndbuild03",
      title: "Open FixedDev BNB data (Run 1, runs 18255/18259)", date: "2026-10-10", issues: ["aih#40"],
      input: "SAM data_MCP2025C_Fall25-Run1_BNB_FixedDev_bnblight_v10_14_02_reco1_sbnd + data_SBND2026A_SBND2026A_gen2_run1_BNBLight_Data_FixedDev_Respin_v10_14_02_04_flatcaf_sbnd",
      events: 89946, events_wc: 89921, units: "1,817 pairs: 1,816 OK, 1 PARTIAL",
      output: "/pnfs/sbnd/persistent/users/yuhw/prod-sbndbuild03/opendata-fixeddev/bnb-data/<id>/ (merged CAFs, 22 GB; qlpctree 180 GB)",
      size: "merged CAFs 22.4 GB + qlpctree 179.8 GB, both on persistent", status: "available", status_note: "moved to dCache persistent 2026-10-19 (ADLER32-checked; /exp copy deleted); checked 2026-11-09 (prod#1 comment 2026-11-09): 1,817 merged CAFs, 1,817 qlpctrees, 1,817 .done, none empty",
      note: "FixedDev reco1 and the Respin CAF are the same events (ai-helper #28)." },
    { id: "ncdr", species: "mc-ncdr", side: "evaluation", config: "fg1", site: "FermiGrid",
      title: "MC NC Δ-radiative (all of the SAM sample)", date: "2026-11-10", issues: ["prod#6"],
      input: "SAM aurora_SBND2026A_gen2_BNBLight_prodgenie_corsika_proton_rockbox0p1_sbnd_EX_ncdeltarad_v10_14_02_05_reco1_sbnd / ..._flat_caf_sbnd (15,776 pairs; 729 reco1 without a CAF not run)",
      events: 13772, events_wc: 13772, units: "15,776 pairs: 9,150 OK, 6,626 EMPTY (files without events) (158 jobs, cluster 87460684@jobsub01; 2 pairs rerun)",
      output: "/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/ncdr/mc-ncdr/<id>/ (merged CAFs, 32.4 GB, ADLER32-checked; README.md and lists/)",
      size: "qlpctree, tracking-pr tar and logs on scratch only (/pnfs/sbnd/scratch/users/yuhw/prod-fermigrid/ncdr/mc-ncdr/)", status: "available",
      status_note: "checked 2026-11-10 (prod#6 comment 2026-11-10): 9,150 merged CAFs on persistent, none empty; the rest on dCache scratch (evictable)",
      note: "1-7 events per file (mean 1.5). Not the sample of the Aurora NC Δ-rad training campaigns (Avinay's private MC on Flare). The fg1 job.sh cannot replace a leftover file of an interrupted copy on the grid (no delete right); 1 pair needed a manual cleanup (prod#6)." },
    { id: "fg1-beamoff-eval", species: "beam-off", side: "evaluation", config: "fg1", site: "FermiGrid",
      title: "Beam-off (InTime) evaluation subset: even runs of fg1 beam-off", date: "2026-11-09", issues: ["prod#1"],
      input: "fg1 beam-off (SAM data_SBND2026A_gen2_InTime-Run1_v10_14_02_02_reco1_sbnd), files of even run numbers: 76 runs, 18250–18592",
      events: 22894, events_wc: 22850, units: "486 pairs: 485 OK, 1 PARTIAL",
      output: "/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/beam-off-eval/<id> -> ../beam-off/<id> (relative symlinks to the merged-CAF folders; README.md and lists/)",
      size: "merged CAFs 3.72 GB (persistent); the pairs' tracking-pr tars and qlpctrees are listed in lists/ (dCache scratch, evictable)", status: "available",
      status_note: "checked 2026-11-10 (prod#1 comment 2026-11-10): 486 links, every one resolves to a non-empty merged CAF",
      note: "Split of fg1 beam-off by run parity (owner, 2026-11-09): disjoint from fg1-beamoff-train in runs and files. 89 of its files are r8 beam-off files (r7 events)." },
    { id: "fg1-beamoff", species: "beam-off", side: "evaluation", config: "fg1", site: "FermiGrid",
      title: "Beam-off (InTime) 50k", date: "2026-10-18", issues: ["prod#1"],
      input: "SAM data_SBND2026A_gen2_InTime-Run1_v10_14_02_02_reco1_sbnd / ..._flatcaf_sbnd (sibling CAF)",
      events: 49970, events_wc: 49917, units: "1,096 pairs: 1,054 OK, 4 PARTIAL, 38 EMPTY",
      output: "/pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/beam-off/<id>/ (merged CAFs, 8 GB)",
      size: "tracking-pr 8 GB + qlpctree 103 GB on scratch only", status: "available",
      status_note: "checked 2026-11-09 (prod#1 comment 2026-11-09): 1,058 merged CAFs on persistent (8.1 GB, none empty); scratch still holds all 1,058 tracking-pr tars (7.7 GB) and 1,060 qlpctrees (103.0 GB).", note: "The full sample = fg1-beamoff-train (odd runs, training side) + fg1-beamoff-eval (even runs). For ML, use the two subsets; do not evaluate a model trained on fg1-beamoff-train on this full sample." },
    { id: "r8-beamoff", species: "beam-off", side: "evaluation", config: "r8", site: "sbndbuild03",
      title: "Beam-off (r7's 10k events)", date: "2026-10-16", issues: ["aih#42"],
      input: "InTime-Run1 reco1, r7's 10,000 events recovered from SAM (212 pairs, sibling CAF)", events: 10071, events_wc: 10048, units: "212 OK",
      output: "/exp/sbnd/data/users/yuhw/production-prep/r8-r26-truth-caf/{validation,semiprod}/beam-off/", size: "",
      status: "available", status_note: "checked 2026-11-09 on sbndbuild03 (prod#1 comment 2026-11-09): semiprod: 212 merged CAFs (1.6 GB) + 10,048 tracking-pr.root (1.6 GB); validation: 2 pairs / 100 events with Bee; none empty. r8 total 98 GB.", note: "Every r8 pair is also in fg1." },

    // ---------------- history (older than the latest two per species and side) ----------------
    { id: "r7-all", species: ["mc-bnb", "mc-nuecc", "beam-on", "beam-off"], side: "evaluation", config: "r7", site: "sbndbuild03",
      title: "r7: CV 13,112 · nueCC 8,877 · beam-on 10,000 · beam-off 10,000", date: "2026-10-08", issues: ["aih#38"],
      events: 41990, events_wc: 41989, output: "/exp/sbnd/data/users/yuhw/production-prep/r7-r26-master-b7bd2a1a/", size: "275 GB",
      status: "available", status_note: "checked 2026-11-09 (prod#1 comment 2026-11-09): tracking-pr.root for every event of events.tsv (CV 13,099, nueCC 8,877, beam-on 10,000, beam-off 10,000), none empty; step 2 only, no merged CAF", note: "Sne's r7_cloud / r7_space DL-vertex models use r7 events (results quoted on 12,693 held-out r7 events)." },
    { id: "r6-all", species: ["mc-bnb"], side: "evaluation", config: "r6", site: "sbndbuild03",
      title: "r6: MC CV only (stopped after a machine crash)", date: "2026-10-07", issues: ["aih#38"],
      events: null, events_wc: null, output: "/exp/sbnd/data/users/yuhw/production-prep/r6-dlvtx-r26-samples/", size: "~119 GB",
      status: "deleted", status_note: "outputs deleted when r6 was stopped (ai-helper #38); checked 2026-11-09 (prod#1 comment 2026-11-09): 0 tracking-pr.root, 40 MB of logs/lists/scripts remain", note: "" },
    { id: "r5-all", species: ["mc-bnb", "mc-nuecc", "beam-off"], side: "evaluation", config: "r5", site: "sbndbuild03",
      title: "r5: CV 2,017 · nueCC 2,001 · beam-off 1,000 (#30 samples for Xin)", date: "2026-10-07", issues: ["aih#38", "aih#30"],
      events: 5018, events_wc: 5018, output: "/exp/sbnd/data/users/yuhw/production-prep/r5-dlvtx-xin-samples/", size: "40 GB",
      status: "deleted", status_note: "deleted 2026-10-09, owner-approved (production-prep/CLEANUP-2026-10-09.md; prod#1 comment 2026-11-09)",
      note: "Input reco1 + truth TSVs also on wcgpu1:/nfs/data/1/yuhw/2025-fall-prod-sample/xin-round3-samples/." },
    { id: "r3-all", species: ["mc-bnb", "mc-nuecc", "beam-on", "beam-off"], side: "evaluation", config: "r3", site: "FNAL",
      title: "Round 3: CV 13,216 · nueCC 8,877 · beam-on 10,000 · beam-off 10,000", date: "2026-09-11", issues: ["aih#26"],
      events: 42094, events_wc: 42093, output: "/exp/sbnd/data/users/yuhw/production-prep/r3-{mc-cv,nuecc,beam-on,beam-off}-*/run/", size: "162 GB",
      status: "deleted", status_note: "not found 2026-11-09 (prod#1 comment 2026-11-09): the r3 run directories are absent from /exp/sbnd/{data,app}/users/yuhw and /pnfs/sbnd/{persistent,scratch}/users/yuhw; the deletion date is not recorded in any issue or doc", note: "Colleague guide: ai-helper docs/sbnd-r3-data-guide.md." },
    { id: "sync-all", species: ["mc-bnb", "mc-nuecc", "beam-on", "beam-off"], side: "evaluation", config: "sync", site: "FNAL",
      title: "sync: CV 13,211 · nueCC 8,866 · beam-on 1,000 · beam-off 1,000", date: "2026-08-30", issues: ["aih#19", "aih#20"],
      events: null, events_wc: 24077, output: "/exp/sbnd/data/users/yuhw/production-prep/img-clus-match-tag-pr-{mc-1000file-sync,data-1000evt-sync,nuecc-1000file}-2026-08-*/", size: "~156 GB",
      status: "deleted", status_note: "not found 2026-11-09 (prod#1 comment 2026-11-09): the img-clus-match-tag-pr-*-sync directories are absent from /exp/sbnd/{data,app}/users/yuhw and /pnfs/sbnd/{persistent,scratch}/users/yuhw; the deletion date is not recorded in any issue or doc", note: "" },
    { id: "preflip-all", species: ["mc-bnb", "beam-on", "beam-off"], side: "evaluation", config: "preflip", site: "FNAL",
      title: "preflip: CV 13,213 · beam-on 1,000 · beam-off 1,000", date: "2026-08-21", issues: ["aih#16", "aih#18"],
      events: null, events_wc: 15213, output: "/exp/sbnd/data/users/yuhw/production-prep/img-clus-match-tag-pr-{mc-1000file,data-1000evt}-2026-08-2*/", size: "84.7 + 4.8 GB",
      status: "deleted", status_note: "outputs deleted 2026-09-09 (ai-helper #20); run records kept", note: "" },
    { id: "tag-cv", species: ["mc-bnb"], side: "evaluation", config: "tag", site: "sbndbuild03",
      title: "1-step img/clus/match/tag (no PR): CV 13,211", date: "2026-08-15", issues: ["aih#11"],
      events: 13217, events_wc: 13211, output: "/exp/sbnd/data/users/yuhw/production-prep/img-clus-match-tag-mc-1000file-2026-08-14/ (ai-helper #11)", size: "64 GB (mabc.zip)",
      status: "deleted", status_note: "deleted 2026-10-09, owner-approved (production-prep/CLEANUP-2026-10-09.md; prod#1 comment 2026-11-09)", note: "" }
  ],

  // Overlap / leakage facts worth keeping in view.
  overlaps: [
    "Training (Aurora) and evaluation (FNAL) MC come from different productions: Avinay's private gen2 samples vs the official SBND2026A Gen2 SAM definitions. No event-level cross-check has been done.",
    "All FNAL MC CV / nueCC / beam-off rounds (tag, preflip, sync, r3, r5, r6, r7, r8) reuse the same 1000-file lists, and every r8 pair (= r7's events) is inside fg1. A model trained on r7, r3 or r8 events has seen part of fg1.",
    "Sne's r7_cloud / r7_space DL-vertex models were trained on r7 events (ai-helper #44 reports results on '12,693 held-out r7 events'). Evaluate them on fg1 only after removing the r8/r7 files (fg1 event lists: /pnfs/sbnd/persistent/users/yuhw/prod-fermigrid/fg1/lists/events-<sample>.tsv.gz).",
    "Beam-on: r3 (10k) and the #12 FrameShift stagings were drawn from FixedDev, so they are inside the open-data production. FixedDev reco1 and the Respin CAF are the same events (ai-helper #28).",
    "fg1 beam-off: fg1-beamoff-train (odd runs, 27,076 events) and fg1-beamoff-eval (even runs, 22,894) are disjoint in runs and files; fg1-beamoff (the full 50k) contains both. r8's 212 beam-off files (= r7's beam-off events) fall in both subsets (123 train, 89 eval), so a model trained on r7/r8/r3 beam-off events has seen part of the evaluation subset.",
    "aurora-r2 and aurora-r1 process the same events (r2 reruns step 2 only); fg2 (prepared, not run) would have been event-disjoint from fg1 by construction."
  ],

  repos: {
    "prod": "https://github.com/HaiwangYu/sbnd-wirecell-production/issues/",
    "aih":  "https://github.com/HaiwangYu/wire-cell-toolkit-ai-helper/issues/"
  }
};

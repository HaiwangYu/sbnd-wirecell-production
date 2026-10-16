#!/usr/bin/env python3
"""Find reco1 / flat-CAF pairs and write pairs.tsv for run-pairs.sh.

    # by SAM definition (FNAL, or anywhere samweb works): the CAF is the reco1's child
    find-pairs.py --reco1-samdef <def> --caf-samdef <flatcaf def> --reality sim [--limit N] [--offset K] -o pairs.tsv
    # ... or a list of reco1 file NAMES (SAM still finds the CAFs), e.g. a past production's selection
    find-pairs.py --reco1-names names.txt --caf-samdef <flatcaf def> --reality data -o pairs.tsv
    # --caf-relation sibling: the CAF was made from the raw file in one job (decode -> reco1 -> reco2 ->
    # caf), so it is the reco1's SIBLING through their common raw parent (MCP2025C and gen2 InTime data)
    # by path: list or directory of reco1 files, CAFs found by name in a directory tree
    find-pairs.py --reco1-dir <dir> | --reco1-list <file> --caf-dir <dir> --reality sim [--limit N] -o pairs.tsv
    # samweb file locations can be rewritten to a local mirror (e.g. Aurora's copy of /pnfs):
    #   --path-map /pnfs/sbn/data_add/sbn_nd/aurora/mc/v10_14_02_03/prodgenie_corsika_proton_rockbox0p1_sbnd=/lus/flare/projects/neutrinoGPU/yuhw

Name rule (path mode): reco1 "X.root"  <->  CAF "reco2-X.flat.caf.root" (FNAL dCache)
                                        or  "reco2-X.caf.root"       (the Aurora copies).
pairs.tsv columns: id, reality, reco1 path, caf path, reco1 events (SAM "Event Count", else
sbn_dm.event_count, else "-").
A reco1 without exactly one CAF is reported and skipped.
"""
import argparse
import os
import subprocess
import sys

ap = argparse.ArgumentParser()
src = ap.add_mutually_exclusive_group(required=True)
src.add_argument('--reco1-samdef')
src.add_argument('--reco1-dir')
src.add_argument('--reco1-list')
src.add_argument('--reco1-names', help='file with reco1 file names, one per line (SAM mode)')
ap.add_argument('--caf-relation', choices=['child', 'sibling'], default='child',
                help='child: the CAF is a child of the reco1; sibling: both are children of one raw file')
ap.add_argument('--caf-samdef', help='SAM definition the CAF must belong to (SAM mode; a reco1 has several CAF-like children)')
ap.add_argument('--caf-dir', help='directory tree holding the CAFs (path mode)')
ap.add_argument('--reality', required=True, choices=['sim', 'data'])
ap.add_argument('--limit', type=int, default=0)
ap.add_argument('--offset', type=int, default=0)
ap.add_argument('--path-map', action='append', default=[], help='PREFIX=REPLACEMENT for located paths')
ap.add_argument('-o', '--output', required=True)
a = ap.parse_args()


def samweb(*args):
    return subprocess.run(['samweb', '-e', 'sbnd'] + list(args), capture_output=True, text=True, check=True).stdout


def remap(p):
    for m in a.path_map:
        old, new = m.split('=', 1)
        if p.startswith(old):
            return new + p[len(old):]
    return p


def locate(name):
    locs = [l.strip() for l in samweb('locate-file', name).splitlines() if l.strip()]
    for l in locs:
        d = l.split(':', 1)[1] if ':' in l else l
        d = d.split('(')[0]
        p = remap(os.path.join(d, name))
        if os.path.exists(p):
            return p
    return remap(os.path.join(locs[0].split(':', 1)[-1].split('(')[0], name)) if locs else None


def cafname_candidates(reco1):
    stem = os.path.basename(reco1)[:-len('.root')]
    return ['reco2-%s.flat.caf.root' % stem, 'reco2-%s.caf.root' % stem]


pairs, skipped = [], []
if a.reco1_samdef or a.reco1_names:
    if not a.caf_samdef:
        sys.exit('--caf-samdef is required in SAM mode (a reco1 has several CAF-like children)')
    if a.reco1_samdef:
        names = samweb('list-files', 'defname: %s' % a.reco1_samdef).split()
    else:
        names = [l.strip() for l in open(a.reco1_names) if l.strip() and not l.startswith('#')]
    names = sorted(names)[a.offset:]
    for n in names:
        if a.limit and len(pairs) >= a.limit:
            break
        if a.caf_relation == 'child':
            kids = samweb('list-files', 'defname: %s and ischildof:( file_name %s )' % (a.caf_samdef, n)).split()
        else:
            raw = samweb('file-lineage', 'parents', n).split()
            if len(raw) != 1:
                skipped.append((n, '%d parents (sibling mode needs one raw file)' % len(raw)))
                continue
            kids = samweb('list-files', 'defname: %s and ischildof:( file_name %s )' % (a.caf_samdef, raw[0])).split()
        if len(kids) != 1:
            skipped.append((n, '%d CAF %s in %s' % (len(kids), 'children' if a.caf_relation == 'child' else 'siblings', a.caf_samdef)))
            continue
        r1, cf = locate(n), locate(kids[0])
        if not r1 or not cf:
            skipped.append((n, 'cannot locate'))
            continue
        # SAM "Event Count" is None for the data reco1; sbn_dm.event_count is filled for MC and data
        nev, nev_dm = '-', '-'
        for line in samweb('get-metadata', n).splitlines():
            k, _, v = line.strip().partition(':')
            if k == 'Event Count' and v.strip().isdigit():
                nev = v.strip()
            elif k == 'sbn_dm.event_count' and v.strip().isdigit():
                nev_dm = v.strip()
        if nev == '-':
            nev = nev_dm
        pairs.append((r1, cf, nev))
else:
    if not a.caf_dir:
        sys.exit('--caf-dir is required in path mode')
    if a.reco1_dir:
        reco1s = [os.path.join(dp, f) for dp, _, fs in os.walk(a.reco1_dir) for f in fs if f.endswith('.root')]
    else:
        reco1s = [l.strip() for l in open(a.reco1_list) if l.strip() and not l.startswith('#')]
    reco1s = sorted(reco1s, key=os.path.basename)[a.offset:]
    cafs = {}
    for dp, _, fs in os.walk(a.caf_dir):
        for f in fs:
            cafs.setdefault(f, []).append(os.path.join(dp, f))
    for r1 in reco1s:
        if a.limit and len(pairs) >= a.limit:
            break
        hits = [p for c in cafname_candidates(r1) for p in cafs.get(c, [])]
        if len(hits) != 1:
            skipped.append((r1, '%d CAFs by name' % len(hits)))
            continue
        pairs.append((r1, hits[0], '-'))

with open(a.output, 'w') as f:
    f.write('#id\treality\treco1\tcaf\treco1_events\n')
    for r1, cf, nev in pairs:
        pid = os.path.basename(r1)[:-len('.root')]
        f.write('%s\t%s\t%s\t%s\t%s\n' % (pid, a.reality, r1, cf, nev))
print('%s: %d pairs, %d skipped' % (a.output, len(pairs), len(skipped)))
for n, why in skipped[:20]:
    print('  skipped %s: %s' % (n, why))
if skipped:
    with open(a.output + '.skipped', 'w') as f:
        for n, why in skipped:
            f.write('%s\t%s\n' % (n, why))
    print('  all skipped reco1 files: %s.skipped' % a.output)

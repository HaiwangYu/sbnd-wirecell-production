#!/usr/bin/env python3
"""Pairs list for a large production, with bulk SAM queries (bin/find-pairs.py asks SAM file by
file: ~4 calls per reco1, ~12 h for 38k files).

    make-pairs-bulk.py --reco1-def <def> --caf-def <def> --relation name|sibling --reality sim|data \\
        --target-events N [--include <pairs.tsv or names>] [--seed S] -o pairs.tsv

1. every reco1 location of the def: one `samweb list-file-locations`;
2. the order: the --include files first (in the def), then the rest of the def shuffled with --seed;
3. metadata in batches of 400 (`samweb get-metadata --json`): sbn_dm.event_count and parents;
4. the CAF:
     name     (MC)   <reco1 dir with /reco1/ -> /caf/>/reco2-<reco1 stem>.flat.caf.root, must exist;
     sibling  (data) the CAF of --caf-def made from the reco1's raw parent: its name starts with
                     reco2_<raw stem>.flat.caf (one `list-file-locations` of the CAF def);
5. reco1 and CAF must be ONLINE in dCache;
until the selected pairs hold --target-events events.  Writes pairs.tsv (find-pairs.py format) and
<pairs.tsv>.skipped (reco1, reason).  Run where samweb works (SL7 + `setup sam_web_client`).
"""
import argparse
import json
import os
import random
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument('--reco1-def', required=True)
ap.add_argument('--caf-def', required=True)
ap.add_argument('--relation', choices=['name', 'sibling'], required=True)
ap.add_argument('--reality', choices=['sim', 'data'], required=True)
ap.add_argument('--target-events', type=int, required=True)
ap.add_argument('--include', default=None, help='pairs.tsv (column 3 = reco1 path) or a list of reco1 names to take first')
ap.add_argument('--seed', type=int, default=20261016)
ap.add_argument('-o', '--output', required=True)
a = ap.parse_args()


def samweb(*args):
    return subprocess.run(['samweb', '-e', 'sbnd'] + list(args), capture_output=True, text=True, check=True).stdout


def locations(defname):
    out = {}
    for line in samweb('list-file-locations', '--defname=%s' % defname).splitlines():
        p = line.split('\t')
        if len(p) < 2:
            continue
        d = p[0].split(':', 1)[-1].split('(')[0]
        out.setdefault(p[1], d)
    return out


def online(path):
    d, n = os.path.split(path)
    try:
        return open(os.path.join(d, '.(get)(%s)(locality)' % n)).read().strip() in ('ONLINE', 'ONLINE_AND_NEARLINE')
    except OSError:
        return False


def metadata(names):
    txt = samweb('get-metadata', '--json', *names)
    dec, i, out = json.JSONDecoder(), 0, []
    while i < len(txt):
        while i < len(txt) and txt[i] in ' \n\r\t':
            i += 1
        if i >= len(txt):
            break
        o, i = dec.raw_decode(txt, i)
        out.extend(o if isinstance(o, list) else [o])
    return {m['file_name']: m for m in out}


reco1 = locations(a.reco1_def)
print('%s: %d reco1 files' % (a.reco1_def, len(reco1)), flush=True)
caf_by_raw = {}
if a.relation == 'sibling':
    for name, d in locations(a.caf_def).items():
        if name.startswith('reco2_') and '.flat.caf' in name:
            stem = name[len('reco2_'):name.index('.flat.caf')]
            caf_by_raw.setdefault(stem, []).append(os.path.join(d, name))
    print('%s: %d CAFs indexed by raw stem' % (a.caf_def, len(caf_by_raw)), flush=True)

first = []
if a.include:
    for line in open(a.include):
        if not line.strip() or line.startswith('#'):
            continue
        p = line.rstrip('\n').split('\t')
        n = os.path.basename(p[2] if len(p) > 2 else p[0])
        if n in reco1 and n not in first:
            first.append(n)
rest = sorted(set(reco1) - set(first))
random.Random(a.seed).shuffle(rest)
order = first + rest
print('order: %d included first, then %d shuffled (seed %d)' % (len(first), len(rest), a.seed), flush=True)

def check(n, m):
    """-> (pair or None, reason): the CAF and the dCache checks for one reco1 (run in threads)."""
    if not m:
        return None, 'no metadata'
    nev = m.get('sbn_dm.event_count') or m.get('event_count')
    r1 = os.path.join(reco1[n], n)
    if a.relation == 'name':
        caf = os.path.join(reco1[n].replace('/reco1/', '/caf/'), 'reco2-%s.flat.caf.root' % n[:-len('.root')])
        if not os.path.exists(caf):
            return None, 'no CAF ' + caf
    else:
        par = [p['file_name'] if isinstance(p, dict) else p for p in m.get('parents', [])]
        stems = [p[:-len('.root')] for p in par if p.endswith('.root')]
        cands = [c for s in stems for c in caf_by_raw.get(s, [])]
        if len(par) != 1 or len(cands) != 1:
            return None, '%d parents, %d sibling CAFs' % (len(par), len(cands))
        caf = cands[0]
    if not online(r1) or not online(caf):
        return None, 'not ONLINE'
    return (n[:-len('.root')], r1, caf, int(nev) if nev else '-'), ''


# the per-file NFS checks (exists, dCache locality) dominate: 32 threads; metadata in batches of 400
pool = ThreadPoolExecutor(32)
pairs, skipped, total, k = [], [], 0, 0
while total < a.target_events and k < len(order):
    batch = order[k:k + 400]
    k += len(batch)
    md = metadata(batch)
    results = list(pool.map(lambda n: check(n, md.get(n)), batch))
    for n, (pair, why) in zip(batch, results):
        if total >= a.target_events:
            break
        if pair is None:
            skipped.append((n, why))
            continue
        pairs.append(pair)
        total += pair[3] if isinstance(pair[3], int) else 0
    print('  %d / %d reco1 looked at: %d pairs, %d events, %d skipped' % (k, len(order), len(pairs), total, len(skipped)), flush=True)

with open(a.output, 'w') as f:
    f.write('#id\treality\treco1\tcaf\treco1_events\n')
    for pid, r1, caf, nev in pairs:
        f.write('%s\t%s\t%s\t%s\t%s\n' % (pid, a.reality, r1, caf, nev))
with open(a.output + '.skipped', 'w') as f:
    for n, why in skipped:
        f.write('%s\t%s\n' % (n, why))
print('%s: %d pairs, %d events (target %d); %d skipped' % (a.output, len(pairs), total, a.target_events, len(skipped)))

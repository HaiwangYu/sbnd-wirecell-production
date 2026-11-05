#!/usr/bin/env python3
"""Seed a work area with the step-1 output of an earlier production, so that run_pair.py (with
WC_STEP1_SEEDED=1) runs only step 2, the merge and the validation (issue #4).

    seed-from-step1.py --pairs P.tsv --work W --nodes N --src DIR [--src DIR ...] [-j 16]

--src     earlier work areas: DIR/node*/<id>/ (capacity layout) or DIR/<id>/ (flat).  Read only.
--nodes   N > 0: the unit goes to W/node<k>/<id>, k chosen as pbs/run-pairs-capacity.pbs slices
          PAIRS (k = (line number among the non-# lines, 1-based) mod N); the job must then run
          with the same PAIRS and N nodes.  N = 0: W/<id> (one bin/run-pairs.sh pool).
Per unit, for every earlier ql/<tag> with a DONE marker: qlpctree.tar.gz is HARDLINKED (no copy,
no new inode; nothing in the new tree writes to it), the small files are copied and DONE last.
reco1_files.json and reco1_events are copied (no event count in a container), and the earlier
events.json skipped / lost_slices go to <id>/step1-seed.json.  Idempotent: a unit whose seeded
ql/ already has a DONE is left alone.  Prints a summary and writes W/seed-report.tsv
(id, result, source)."""
import argparse
import glob
import json
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor

ap = argparse.ArgumentParser()
ap.add_argument('--pairs', required=True)
ap.add_argument('--work', required=True)
ap.add_argument('--nodes', type=int, required=True)
ap.add_argument('--src', action='append', required=True)
ap.add_argument('-j', type=int, default=16)
a = ap.parse_args()

ids = [l.split('\t', 1)[0] for l in open(a.pairs) if l.strip() and not l.startswith('#')]
want = set(ids)

# index the earlier units (directory listings only)
src = {}
dup = []
for root in a.src:
    dirs = sorted(p for p in glob.glob(os.path.join(root, 'node*')) if os.path.isdir(p)) or [root]
    for nd in dirs:
        for name in os.listdir(nd):
            if name in want:
                p = os.path.join(nd, name)
                if name in src:
                    dup.append((name, src[name], p))
                    # prefer the one that has a status (a finished unit)
                    if not os.path.exists(os.path.join(src[name], 'status')) and os.path.exists(os.path.join(p, 'status')):
                        src[name] = p
                else:
                    src[name] = p


def dest_of(i, uid):
    if a.nodes > 0:
        return os.path.join(a.work, 'node%d' % ((i + 1) % a.nodes), uid)
    return os.path.join(a.work, uid)


def seed(job):
    i, uid = job
    d = dest_of(i, uid)
    if glob.glob(os.path.join(d, 'ql', '*', 'DONE')):
        return uid, 'already', src.get(uid, '')
    s = src.get(uid)
    if not s:
        return uid, 'no-source', ''
    tags = [os.path.dirname(p) for p in glob.glob(os.path.join(s, 'ql', '*', 'DONE'))]
    if not tags:
        return uid, 'no-step1-DONE', s
    for f in ('reco1_files.json', 'reco1_events'):
        if not os.path.exists(os.path.join(s, f)):
            return uid, 'no-' + f, s
    os.makedirs(os.path.join(d, 'ql'), exist_ok=True)
    for f in ('reco1_files.json', 'reco1_events'):
        shutil.copy2(os.path.join(s, f), os.path.join(d, f))
    ev = os.path.join(s, 'events.json')
    seedj = {'source': s, 'skipped': [], 'lost_slices': []}
    if os.path.exists(ev):
        e = json.load(open(ev))
        seedj['skipped'] = e.get('skipped', [])
        seedj['lost_slices'] = e.get('lost_slices', [])
    with open(os.path.join(d, 'step1-seed.json'), 'w') as f:
        json.dump(seedj, f, indent=1)
    for t in tags:
        q = os.path.join(d, 'ql', os.path.basename(t))
        os.makedirs(q, exist_ok=True)
        for f in sorted(os.listdir(t)):
            sp, dp = os.path.join(t, f), os.path.join(q, f)
            if f == 'DONE' or os.path.isdir(sp):
                continue
            if os.path.lexists(dp):
                os.remove(dp)
            if f == 'qlpctree.tar.gz':
                os.link(sp, dp)
            else:
                shutil.copy2(sp, dp)
        open(os.path.join(q, 'DONE'), 'w').write('')
    return uid, 'seeded' if len(tags) == 1 else 'seeded-%dslices' % len(tags), s


os.makedirs(a.work, exist_ok=True)
with ThreadPoolExecutor(a.j) as ex:
    res = list(ex.map(seed, enumerate(ids)))
with open(os.path.join(a.work, 'seed-report.tsv'), 'w') as f:
    for r in res:
        f.write('\t'.join(r) + '\n')
cnt = {}
for _, r, _ in res:
    cnt[r] = cnt.get(r, 0) + 1
print('seed %s: %d units -> %s; %s' % (a.pairs, len(ids), a.work, ' '.join('%s %d' % kv for kv in sorted(cnt.items()))))
for name, p1, p2 in dup:
    print('duplicate source %s: %s %s (using %s)' % (name, p1, p2, src[name]))
bad = sum(v for k, v in cnt.items() if not (k.startswith('seeded') or k == 'already'))
sys.exit(1 if bad else 0)

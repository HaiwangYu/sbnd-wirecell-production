#!/usr/bin/env python3
"""Compare a grid job's outputs for one pair with a local run of the same pair, value by value.

    compare-outputs.py <grid pair dir> <local pair dir> [--ignore TREE.BRANCH ...]

<grid pair dir>: what bin/job.sh copies to dCache (<id>.tracking-pr.tar, <id>.qlpctree.tar.gz,
the merged CAF).  <local pair dir>: a run_pair.py work dir (pr/<tag>/pr_evt<E>/tracking-pr.root,
ql/<tag>/qlpctree.tar.gz, merged/*.root), e.g. r8 semiprod/<sample>/<id>.

Compared (never by bytes of a ROOT file):
  tracking-pr.root  every tree of every event, every branch, every entry (uproot + awkward,
                    exact, NaN == NaN);
  merged CAF        every tree (recTree, recTreeWireCell, ...) the same way, and the info TNamed;
  qlpctree.tar.gz   every tensor by datapath: array bytes and metadata.
A branch uproot cannot read is listed under "unreadable" (both sides), not compared.
Prints a JSON verdict (last line); exit 0 if identical apart from --ignore'd branches.
Needs uproot and awkward (e.g. the wire-cell-python venv, which setup-local-opt.sh activates).
"""
import argparse
import collections
import glob
import json
import os
import sys
import tarfile
import tempfile

import awkward as ak
import numpy as np
import uproot

ap = argparse.ArgumentParser()
ap.add_argument('grid')
ap.add_argument('local')
ap.add_argument('--ignore', nargs='*', default=[], help='TREE.BRANCH names whose values may differ')
a = ap.parse_args()
res = dict(trees=0, branches=0, events=0, diffs=collections.Counter(), ignored=collections.Counter(),
           unreadable=collections.Counter(), qlpctree={})


def equal(x, y):
    """Exact, NaN == NaN, for numbers, strings, jagged and record arrays."""
    try:
        return bool(ak.almost_equal(x, y, rtol=0, atol=0, dtype_exact=True, equal_nan=True, check_parameters=False))
    except Exception:
        pass
    if len(x) != len(y):
        return False
    fx, fy = ak.fields(x), ak.fields(y)
    if fx or fy:
        return fx == fy and all(equal(x[f], y[f]) for f in fx)
    try:
        if not ak.all(ak.num(x, axis=-1) == ak.num(y, axis=-1), axis=None):
            return False
    except Exception:
        pass
    try:
        a1 = ak.to_numpy(ak.flatten(x, axis=None))
        b1 = ak.to_numpy(ak.flatten(y, axis=None))
        if a1.dtype.kind == 'f' or b1.dtype.kind == 'f':
            return a1.shape == b1.shape and np.array_equal(a1, b1, equal_nan=True)
        return a1.shape == b1.shape and np.array_equal(a1, b1)
    except Exception:
        return ak.to_list(x) == ak.to_list(y)


def ignored(key):
    return any(key == g or key.startswith(g + '.') or key.startswith(g + '..') for g in a.ignore)


def cmp_files(fa, fb, label):
    A, B = uproot.open(fa), uproot.open(fb)
    ka = {k.split(';')[0]: c for k, c in A.classnames().items()}
    kb = {k.split(';')[0]: c for k, c in B.classnames().items()}
    for k in sorted(set(ka) ^ set(kb)):
        res['diffs']['%s: object %s only in %s' % (label, k, 'grid' if k in ka else 'local')] += 1
    for name in sorted(set(ka) & set(kb)):
        if ka[name] == 'TNamed':
            if A[name].member('fTitle') != B[name].member('fTitle'):
                res['diffs']['%s: %s (TNamed)' % (label, name)] += 1
            continue
        if ka[name] != 'TTree':
            continue
        ta, tb = A[name], B[name]
        res['trees'] += 1
        if ta.num_entries != tb.num_entries:
            res['diffs']['%s: %s entries %d vs %d' % (label, name, ta.num_entries, tb.num_entries)] += 1
            continue
        if set(ta.keys()) != set(tb.keys()):
            res['diffs']['%s: %s branch list' % (label, name)] += 1
        for b in ta.keys():
            if b not in tb.keys():
                continue
            key = '%s.%s' % (name, b)
            try:
                x, y = ta[b].array(library='ak'), tb[b].array(library='ak')
            except Exception:
                res['unreadable'][key] += 1
                continue
            res['branches'] += 1
            if not equal(x, y):
                res['ignored' if ignored(key) else 'diffs'][key] += 1


def tensors(path):
    raw = {}
    with tarfile.open(path) as t:
        for m in t.getmembers():
            if m.isfile():
                raw[m.name] = t.extractfile(m).read()
    out = {}
    for n, b in raw.items():
        if n.endswith('_metadata.json'):
            md = json.loads(b)
            dp = md.get('datapath', n)
            out[dp if dp not in out else dp + '#' + n] = (json.dumps(md, sort_keys=True),
                                                          raw.get(n[:-len('_metadata.json')] + '_array.npy', b''))
    return out


tmp = tempfile.mkdtemp()
tars = glob.glob(os.path.join(a.grid, '*.tracking-pr.tar'))
if tars:
    with tarfile.open(tars[0]) as t:
        t.extractall(tmp)
grid_ev = {os.path.basename(os.path.dirname(f)): f for f in glob.glob(os.path.join(tmp, 'pr', '*', 'pr_evt*', 'tracking-pr.root'))}
loc_ev = {os.path.basename(os.path.dirname(f)): f for f in glob.glob(os.path.join(a.local, 'pr', '*', 'pr_evt*', 'tracking-pr.root'))
          + glob.glob(os.path.join(a.local, 'pr', 'pr_evt*', 'tracking-pr.root'))}
for e in sorted(set(grid_ev) ^ set(loc_ev)):
    res['diffs']['event %s only in %s' % (e, 'grid' if e in grid_ev else 'local')] += 1
for e in sorted(set(grid_ev) & set(loc_ev)):
    res['events'] += 1
    cmp_files(grid_ev[e], loc_ev[e], 'tracking-pr')
mg = glob.glob(os.path.join(a.grid, '*.root'))
ml = glob.glob(os.path.join(a.local, 'merged', '*.root'))
if mg and ml:
    cmp_files(mg[0], ml[0], 'merged CAF')
else:
    res['diffs']['merged CAF missing (grid %d, local %d)' % (len(mg), len(ml))] += 1
qg = glob.glob(os.path.join(a.grid, '*.qlpctree*.tar.gz'))
ql = glob.glob(os.path.join(a.local, 'ql', '*', 'qlpctree.tar.gz')) + glob.glob(os.path.join(a.local, 'ql', 'qlpctree.tar.gz'))
if qg and ql:
    tg, tl = tensors(qg[0]), tensors(ql[0])
    res['qlpctree'] = dict(tensors=(len(tg), len(tl)), only_grid=len(set(tg) - set(tl)), only_local=len(set(tl) - set(tg)),
                           array_diffs=sum(1 for k in tg if k in tl and tg[k][1] != tl[k][1]),
                           metadata_diffs=sum(1 for k in tg if k in tl and tg[k][0] != tl[k][0]))
for k in ('diffs', 'ignored', 'unreadable'):
    res[k] = dict(res[k])
q = res['qlpctree']
ok = not res['diffs'] and (not q or (q['array_diffs'] == 0 and q['only_grid'] == 0 and q['only_local'] == 0))
res['verdict'] = 'IDENTICAL' if ok else 'DIFFERENT'
print(json.dumps(res))
sys.exit(0 if ok else 1)

#!/usr/bin/env python3
"""Validate a merged CAF against its inputs (ai-helper issue 39).

    validate-merge.py --merged <merged.root> --caf <original.flat.caf.root> \
                      [--json out.json] <tracking-pr.root> ...   (or @list.txt)

Checks, all exact:
  A. the original CAF is untouched: every key of the original is in the merged
     file with the same name, cycle, class, object length and compressed size,
     and recTree / GenieEvtRecTree have the same entries;
  B. recTreeWireCell has one entry per recTree entry, with the same
     (run, subrun, event) in the same order;
  C. for every CAF event that has a tracking-pr.root: wc.valid == 1, and EVERY
     row tree of tracking-pr.root (not the flat tree itself) is reproduced from
     recTreeWireCell -- the row count, and every branch value of every row
     (scalars; vector and string branches via ..idx/..length; vector<vector>
     via the .v level), same type, NaN == NaN; a tree the file does not have has
     0 rows in recTreeWireCell;
  D. for every CAF event without one: wc.valid == 0 and every row count is 0.
Exit 0 only if everything passes.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
import numpy as np  # noqa: E402
import wcflat  # noqa: E402
import ROOT  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('--merged', required=True)
ap.add_argument('--caf', required=True)
ap.add_argument('--json', default=None)
ap.add_argument('files', nargs='+')
a = ap.parse_args()
files = []
for x in a.files:
    files += [l.strip() for l in open(x[1:]) if l.strip()] if x.startswith('@') else [x]
P = wcflat.PREFIX
problems = []
stats = {'events_checked': 0, 'rows_checked': 0, 'values_checked': 0, 'trees_checked': 0}


def bad(msg):
    problems.append(msg)


def keys(f):
    return {(k.GetName(), k.GetCycle()): (k.GetClassName(), k.GetObjlen(), k.GetNbytes()) for k in f.GetListOfKeys()}


mf, of = ROOT.TFile.Open(a.merged), ROOT.TFile.Open(a.caf)
# A. original untouched
ko, km = keys(of), keys(mf)
for k, v in ko.items():
    if km.get(k) != v:
        bad('A: key %s;%d differs: %s vs %s' % (k[0], k[1], v, km.get(k)))
extra = sorted(set(k[0] for k in km) - set(k[0] for k in ko))
if extra != sorted([wcflat.TREE_NAME, wcflat.TREE_NAME + '_info']):
    bad('A: unexpected new keys %s' % extra)
for tn in ('recTree', 'GenieEvtRecTree'):
    to, tm = of.Get(tn), mf.Get(tn)
    if bool(to) != bool(tm) or (to and to.GetEntries() != tm.GetEntries()):
        bad('A: %s entries differ' % tn)

# B. alignment
rec, w = mf.Get('recTree'), mf.Get(wcflat.TREE_NAME)
if not w:
    sys.exit('no %s in %s' % (wcflat.TREE_NAME, a.merged))
if w.GetEntries() != rec.GetEntries():
    bad('B: %s has %d entries, recTree %d' % (wcflat.TREE_NAME, w.GetEntries(), rec.GetEntries()))
rec.SetBranchStatus('*', 0)
for k in ('rec.hdr.run', 'rec.hdr.subrun', 'rec.hdr.evt'):
    rec.SetBranchStatus(k, 1)

by_rse = {}
for fn in files:
    r = wcflat.rse_of_flat(fn)
    if r is None:
        bad('C: %s has no readable %s' % (fn, wcflat.TREE_NAME))
    else:
        by_rse[r] = fn

wtrees = sorted({b.GetName().split('.')[1] for b in w.GetListOfBranches()
                 if b.GetName().count('.') == 3 and b.GetName().endswith('..length')})


def eq(x, y):
    x, y = np.asarray(x), np.asarray(y)
    if x.shape != y.shape:
        return False
    if x.dtype.kind == 'f' or y.dtype.kind == 'f':
        return np.array_equal(x.astype(np.float64), y.astype(np.float64), equal_nan=True)
    return np.array_equal(x, y)


def row_values(tree, br, nrows):
    """Per-row values of a row-tree branch: list (len nrows) of numpy arrays (scalars as length-1)."""
    name = br.GetName()
    cls = br.GetClassName()
    out = []
    for r in range(nrows):
        tree.GetEntry(r)
        v = getattr(tree, name)
        if cls == 'string':
            out.append(np.frombuffer(str(v).encode('latin-1'), dtype=np.int8).copy())
        elif cls.startswith('vector<vector'):
            out.append([np.array(list(inner)) for inner in v])
        elif cls.startswith('vector'):
            out.append(np.array(list(v)))
        else:
            out.append(np.array([tree.GetLeaf(name).GetValue()]))
    return out


for i in range(rec.GetEntries()):
    rec.GetEntry(i)
    rse = tuple(int(rec.GetLeaf(k).GetValue()) for k in ('rec.hdr.run', 'rec.hdr.subrun', 'rec.hdr.evt'))
    W = wcflat.read_flat_entry(w, i)
    if tuple(int(W[P + '.' + k][0]) for k in ('run', 'subrun', 'evt')) != rse:
        bad('B: entry %d RSE %s vs recTree %s' % (i, tuple(W[P + '.' + k][0] for k in ('run', 'subrun', 'evt')), rse))
    fn = by_rse.get(rse)
    if fn is None:  # D
        if W[P + '.valid'][0] != 0:
            bad('D: entry %d %s: valid != 0 without Wire-Cell output' % (i, rse))
        for tr in wtrees:
            if W['%s.%s..length' % (P, tr)][0] != 0:
                bad('D: entry %d %s: %s has rows without Wire-Cell output' % (i, rse, tr))
        continue
    # C
    stats['events_checked'] += 1
    if W[P + '.valid'][0] != 1:
        bad('C: entry %d %s: valid != 1' % (i, rse))
    g = ROOT.TFile.Open(fn)
    file_trees = []
    for k in g.GetListOfKeys():
        if k.GetClassName() == 'TTree' and k.GetName() != wcflat.TREE_NAME and k.GetName() not in file_trees:
            file_trees.append(k.GetName())
    for tr in wtrees:
        if tr not in file_trees and W['%s.%s..length' % (P, tr)][0] != 0:
            bad('C: %s: tree %s absent in the file but has rows in the merge' % (rse, tr))
    for tr in file_trees:
        t = g.Get(tr)
        n = t.GetEntries()
        base = '%s.%s' % (P, tr)
        stats['trees_checked'] += 1
        if (base + '..length') not in W or W[base + '..length'][0] != n:
            bad('C: %s %s: rows %d vs merged %s' % (rse, tr, n, W.get(base + '..length')))
            continue
        stats['rows_checked'] += n
        for br in t.GetListOfBranches():
            b = br.GetName()
            name = base + '.' + b
            cls = br.GetClassName()
            probe = name + '..length' if cls else name   # vector/string/vector<vector>: the ..length array
            if probe not in W:
                bad('C: %s %s: no merged branch' % (rse, name))
                continue
            rows = row_values(t, br, n)
            if cls.startswith('vector<vector'):
                ln, ix = W[name + '..length'], W[name + '..idx']
                vl, vi, flat = W[name + '.v..length'], W[name + '.v..idx'], W[name + '.v']
                for r in range(n):
                    if ln[r] != len(rows[r]):
                        bad('C: %s %s row %d: outer length' % (rse, name, r)); break
                    for k in range(ln[r]):
                        j = ix[r] + k
                        got = flat[vi[j]:vi[j] + vl[j]]
                        if not eq(got, rows[r][k]):
                            bad('C: %s %s row %d elem %d differs' % (rse, name, r, k)); break
                        stats['values_checked'] += len(got)
            elif cls:  # vector or string
                ln, ix, flat = W[name + '..length'], W[name + '..idx'], W[name]
                for r in range(n):
                    got = flat[ix[r]:ix[r] + ln[r]]
                    if not eq(got, rows[r]):
                        bad('C: %s %s row %d differs' % (rse, name, r)); break
                    stats['values_checked'] += len(got)
            else:
                exp = np.concatenate(rows) if rows else np.zeros(0)
                if not eq(W[name], exp):
                    bad('C: %s %s differs' % (rse, name))
                stats['values_checked'] += n
                lt = t.GetLeaf(b).GetTypeName()
                if w.GetLeaf(name).GetTypeName() != lt:
                    bad('C: %s %s type %s vs %s' % (rse, name, w.GetLeaf(name).GetTypeName(), lt))
    g.Close()

res = {'merged': a.merged, 'caf_entries': rec.GetEntries(), **stats,
       'wirecell_files': len(files), 'problems': len(problems), 'first_problems': problems[:20],
       'verdict': 'PASS' if not problems else 'FAIL'}
if a.json:
    with open(a.json, 'w') as fo:
        json.dump(res, fo, indent=1)
print(json.dumps(res))
sys.exit(0 if not problems else 1)

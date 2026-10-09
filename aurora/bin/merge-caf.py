#!/usr/bin/env python3
"""Step 3: merge the Wire-Cell per-event flat trees into a flat CAF.

    merge-caf.py --caf <in.flat.caf.root> --out <merged.root> --schema <schema.json> \
                 [--summary summary.json] <tracking-pr.root> ...   (or @list.txt)

The flat CAF is COPIED byte for byte, then one tree is added: recTreeWireCell,
with exactly as many entries as recTree, in recTree's order, matched by
(run, subrun, event) to the recTreeWireCell entry of each given
tracking-pr.root (written by the toolkit's RootFlatTreeVisitor, step 2).

Every entry carries the fixed schema (make-schema.py):
  - an event with Wire-Cell output: its values; a tree it did not write has 0 rows;
  - a CAF event without Wire-Cell output: wc.run/subrun/evt from the CAF,
    wc.valid = 0, every row count 0.
Errors (nonzero exit, nothing kept): a branch outside the schema, a type that
differs from the schema, a schema branch missing from a tree the event does
have, two Wire-Cell files for one event, a Wire-Cell event that names an RSE the
CAF does not have is only a warning (counted in the summary).
"""
import argparse
import datetime
import hashlib
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
import numpy as np  # noqa: E402
import wcflat  # noqa: E402
import ROOT  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('--caf', required=True)
ap.add_argument('--out', required=True)
ap.add_argument('--schema', required=True)
ap.add_argument('--summary', default=None)
ap.add_argument('files', nargs='+', help='tracking-pr.root files, or @file with one path per line')
a = ap.parse_args()

files = []
for x in a.files:
    if x.startswith('@'):
        files += [l.strip() for l in open(x[1:]) if l.strip()]
    else:
        files.append(x)

schema = wcflat.load_schema(a.schema)
sch = {b['name']: b for b in schema}
P = wcflat.PREFIX


def fail(msg):
    if os.path.exists(a.out + '.tmp'):
        os.remove(a.out + '.tmp')
    sys.exit('merge-caf.py: ' + msg)


# Wire-Cell events by RSE
wc = {}
for fn in files:
    rse = wcflat.rse_of_flat(fn)
    if rse is None:
        fail('%s: no readable %s' % (fn, wcflat.TREE_NAME))
    if rse in wc:
        fail('two files for run/subrun/event %s: %s, %s' % (rse, wc[rse], fn))
    wc[rse] = fn

tmp = a.out + '.tmp'
shutil.copyfile(a.caf, tmp)
f = ROOT.TFile.Open(tmp, 'UPDATE')
rec = f.Get('recTree')
if not rec:
    fail('%s has no recTree' % a.caf)
if f.Get(wcflat.TREE_NAME):
    fail('%s already has a %s' % (a.caf, wcflat.TREE_NAME))
rec.SetBranchStatus('*', 0)
for k in ('rec.hdr.run', 'rec.hdr.subrun', 'rec.hdr.evt'):
    rec.SetBranchStatus(k, 1)
caf_rse = []
for i in range(rec.GetEntries()):
    rec.GetEntry(i)
    caf_rse.append(tuple(int(rec.GetLeaf(k).GetValue()) for k in ('rec.hdr.run', 'rec.hdr.subrun', 'rec.hdr.evt')))
rec.SetBranchStatus('*', 1)

# output tree with numpy buffers
f.cd()
out = ROOT.TTree(wcflat.TREE_NAME, 'Wire-Cell per-event tree, merged (ai-helper issue 39)')
out.SetDirectory(f)
bufs = {}
for b in schema:
    dt, code = wcflat.TYPES[b['type']]
    buf = np.zeros(1 if b['count'] is None else 16, dtype=dt)
    bufs[b['name']] = buf
    leaflist = ('%s/%s' % (b['name'], code)) if b['count'] is None else ('%s[%s]/%s' % (b['name'], b['count'], code))
    out.Branch(b['name'], buf, leaflist, 4096)
scalars = [b['name'] for b in schema if b['count'] is None]
trees_of = {}
for b in schema:
    parts = b['name'].split('.')
    if len(parts) >= 3:
        trees_of.setdefault(parts[1], []).append(b['name'])

n_valid = 0
for i, rse in enumerate(caf_rse):
    for s in scalars:
        bufs[s][0] = 0
    fn = wc.get(rse)
    if fn is None:
        bufs[P + '.run'][0], bufs[P + '.subrun'][0], bufs[P + '.evt'][0] = rse
        bufs[P + '.valid'][0] = 0
        out.Fill()
        continue
    g = ROOT.TFile.Open(fn)
    t = g.Get(wcflat.TREE_NAME)
    in_schema = wcflat.tree_schema(t)
    names = {b['name'] for b in in_schema}
    for b in in_schema:
        s = sch.get(b['name'])
        if s is None:
            fail('%s: branch %s is not in the schema %s (rebuild it with make-schema.py)' % (fn, b['name'], a.schema))
        if s != b:
            fail('%s: branch %s is %s, the schema says %s' % (fn, b['name'], b, s))
    present_trees = {n.split('.')[1] for n in names if n.count('.') == 3 and n.endswith('..length')}
    for tr in present_trees:
        lacking = [n for n in trees_of.get(tr, []) if n not in names]
        if lacking:
            fail('%s: tree %s lacks schema branches %s' % (fn, tr, lacking[:5]))
    vals = wcflat.read_flat_entry(t, 0)
    g.Close()
    for name, arr in vals.items():
        if sch[name]['count'] is None:
            bufs[name][0] = arr[0]
        else:
            buf = bufs[name]
            if len(arr) > len(buf):
                buf = np.zeros(max(len(arr), 2 * len(buf)), dtype=buf.dtype)
                bufs[name] = buf
                out.SetBranchAddress(name, buf)
            buf[:len(arr)] = arr
    if (int(bufs[P + '.run'][0]), int(bufs[P + '.subrun'][0]), int(bufs[P + '.evt'][0])) != rse:
        fail('%s: RSE mismatch with CAF entry %d %s' % (fn, i, rse))
    n_valid += 1
    out.Fill()

f.cd()   # opening the per-event files moved gDirectory
f.WriteTObject(out)
md5 = hashlib.md5(open(a.schema, 'rb').read()).hexdigest()
info = {'caf': os.path.abspath(a.caf), 'schema': os.path.abspath(a.schema), 'schema_md5': md5,
        'n_caf_events': len(caf_rse), 'n_wirecell_events': n_valid,
        'n_caf_events_without_wirecell': len(caf_rse) - n_valid,
        'n_wirecell_events_not_in_caf': len(set(wc) - set(caf_rse)),
        'created': datetime.datetime.now().isoformat(timespec='seconds')}
f.WriteTObject(ROOT.TNamed(wcflat.TREE_NAME + '_info', json.dumps(info)))
f.Close()
os.replace(tmp, a.out)
if a.summary:
    with open(a.summary, 'w') as fo:
        json.dump(info, fo, indent=1)
print(json.dumps(info))

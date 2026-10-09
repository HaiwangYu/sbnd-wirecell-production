#!/usr/bin/env python3
"""Build the fixed recTreeWireCell schema from reference tracking-pr.root files.

The per-event flat tree only has the branches of the trees that event wrote
(T_tagger / T_kine / T_segment only with a neutrino candidate, T_truth_* only
on MC, ...).  A CAF tree needs ONE schema for every event and file, so the
merger works from a schema: the union, in first-seen order, of the flat trees
of reference files.  Choose references that together carry every tree (an MC
event with a neutrino candidate does).  A name seen with two different types or
counts is an error.

    make-schema.py -o schema.json [--require T_tagger,T_kine,...] <tracking-pr.root> ...

The schema records the trees it covers; merge-caf.py refuses an event that has
a branch outside the schema (rerun this with that event among the references).
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
import wcflat  # noqa: E402
import ROOT  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('-o', '--output', required=True)
ap.add_argument('--require', default='Trun,T_kine,T_tagger,T_cluster,T_rec_charge,T_bad_ch,T_proj_data,'
                'T_bundle,T_flash,T_segment,T_truth_nu,T_truth_pf,T_dlvtx_call,T_dlvtx_cloud',
                help='trees the union must contain (comma separated)')
ap.add_argument('files', nargs='+')
a = ap.parse_args()

order, by_name = [], {}
for fn in a.files:
    f = ROOT.TFile.Open(fn)
    t = f.Get(wcflat.TREE_NAME) if f else None
    if not t:
        sys.exit('%s: no %s' % (fn, wcflat.TREE_NAME))
    for b in wcflat.tree_schema(t):
        old = by_name.get(b['name'])
        if old is None:
            by_name[b['name']] = b
            order.append(b['name'])
        elif old != b:
            sys.exit('inconsistent branch %s: %s vs %s (%s)' % (b['name'], old, b, fn))
    f.Close()

trees = sorted({n.split('.')[1] for n in order if n.endswith('..length') and n.count('.') == 3})
missing = [t for t in a.require.split(',') if t and t not in trees]
if missing:
    sys.exit('the references cover no %s: add a file that has them' % missing)
branches = [by_name[n] for n in order]
for b in branches:
    if b['count'] and b['count'] not in by_name:
        sys.exit('branch %s counts on %s, which is not in the schema' % (b['name'], b['count']))
with open(a.output, 'w') as f:
    json.dump({'tree': wcflat.TREE_NAME, 'prefix': wcflat.PREFIX, 'trees': trees,
               'references': [os.path.abspath(x) for x in a.files], 'branches': branches}, f, indent=1)
print('%s: %d branches, %d trees: %s' % (a.output, len(branches), len(trees), ' '.join(trees)))

#!/usr/bin/env python3
"""Collect the COMPLETE per-event Wire-Cell files of one pair from all its step-2 directories.
Run inside SL7.

    collect-good.py -o good.txt <step-2 dir> ...      (earlier dirs win for the same event)

A tracking-pr.root counts as complete when it has a readable recTreeWireCell with exactly one
entry: RootFlatTreeVisitor writes it last, after every writer of the file closed it, so a stub
left by a crash (the event processed just before it, closed lazily) or a file of the event that
crashed has none.  Prints a JSON summary: complete / incomplete counts and the RSE list.
"""
import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
import wcflat  # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('-o', '--output', required=True)
ap.add_argument('dirs', nargs='+')
a = ap.parse_args()
chosen, incomplete = {}, []
for d in a.dirs:
    for fn in sorted(glob.glob(os.path.join(d, 'pr_evt*', 'tracking-pr.root'))):
        rse = wcflat.rse_of_flat(fn)
        if rse is None:
            incomplete.append(fn)
        elif rse not in chosen:
            chosen[rse] = fn
with open(a.output, 'w') as f:
    for rse in sorted(chosen):
        f.write(chosen[rse] + '\n')
print(json.dumps({'complete': len(chosen), 'incomplete': len(incomplete),
                  'rse': sorted(chosen), 'incomplete_files': incomplete[:20]}))

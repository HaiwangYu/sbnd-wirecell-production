#!/usr/bin/env python3
"""Summarise the per-pair cost.tsv of a run-pairs.sh work dir: per step, totals and per event.
    cost-summary.py <workdir>      (markdown to stdout)"""
import csv, glob, json, os, sys
W = sys.argv[1]
rows, nev, npairs, ok = [], 0, 0, 0
for d in sorted(glob.glob(os.path.join(W, '*', 'cost.tsv'))):
    pd = os.path.dirname(d); npairs += 1
    st = open(os.path.join(pd, 'status')).read().strip() if os.path.exists(os.path.join(pd, 'status')) else '?'
    ok += st == 'OK'
    m = os.path.join(pd, 'merged', 'merge.json')
    n = json.load(open(m))['n_wirecell_events'] if os.path.exists(m) else 0
    nev += n
    for r in csv.DictReader(open(d), delimiter='\t'):
        r['pair'] = os.path.basename(pd); r['n'] = n; rows.append(r)
print('# cost summary: %s\n\n%d pairs (%d OK), %d events with Wire-Cell output\n' % (W, npairs, ok, nev))
print('| step | runs | wall total [s] | wall per event [s] | CPU per event [s] | max RSS: median / max [MB] | output total [MB] | output per event [MB] |')
print('|---|---|---|---|---|---|---|---|')
for s in ('step1', 'step2', 'step2-try1', 'step3', 'validate'):
    R = [r for r in rows if r['step'] == s]
    if not R: continue
    f = lambda k: [float(r[k]) for r in R if r[k] not in ('', None)]
    rss = sorted(f('maxrss_MB'))
    print('| %s | %d | %.0f | %.2f | %.2f | %.0f / %.0f | %.1f | %.3f |' % (
        s, len(R), sum(f('wall_s')), sum(f('wall_s')) / max(nev, 1), sum(f('cpu_s')) / max(nev, 1),
        rss[len(rss) // 2], rss[-1], sum(f('out_MB')), sum(f('out_MB')) / max(nev, 1)))
print('\nwall per event = summed process wall / events (one process per pair and step); CPU = user + sys.')

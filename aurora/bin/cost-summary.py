#!/usr/bin/env python3
"""Summarise the per-pair cost.tsv (run_pair.py) of a run-pairs.sh work dir.
    cost-summary.py <workdir>      (markdown to stdout)
Successful runs (rc 0) give the cost per event; failed tries (crashes, timeouts) are listed
separately as wasted compute."""
import collections, csv, glob, json, os, sys
W = sys.argv[1]
rows, nev, st = [], 0, collections.Counter()
for d in sorted(glob.glob(os.path.join(W, '*', 'status'))):
    pd = os.path.dirname(d)
    st[open(d).read().split()[0] if open(d).read().strip() else '?'] += 1
    m = os.path.join(pd, 'merged', 'merge.json')
    nev += json.load(open(m))['n_wirecell_events'] if os.path.exists(m) else 0
    c = os.path.join(pd, 'cost.tsv')
    if os.path.exists(c):
        for r in csv.DictReader(open(c), delimiter='\t'):
            r['pair'] = os.path.basename(pd); rows.append(r)
print('# cost summary: %s\n\npairs: %s; %d events with Wire-Cell output\n' % (W, dict(st), nev))
print('| step | runs | wall total [s] | wall per event [s] | CPU per event [s] | max RSS: median / max [MB] | output total [MB] | output per event [MB] |')
print('|---|---|---|---|---|---|---|---|')
num = lambda R, k: [float(r[k]) for r in R if r.get(k) not in ('', None)]
for s in ('step1', 'step2', 'step3', 'validate'):
    R = [r for r in rows if r['step'] == s and r['rc'] == '0']
    if not R: continue
    rss = sorted(num(R, 'maxrss_MB')) or [0]
    print('| %s | %d | %.0f | %.2f | %.2f | %.0f / %.0f | %.1f | %.3f |' % (
        s, len(R), sum(num(R, 'wall_s')), sum(num(R, 'wall_s')) / max(nev, 1), sum(num(R, 'cpu_s')) / max(nev, 1),
        rss[len(rss) // 2], rss[-1], sum(num(R, 'out_MB')), sum(num(R, 'out_MB')) / max(nev, 1)))
F = [r for r in rows if r['rc'] not in ('0', '')]
if F:
    print('\nFailed tries (wasted compute; kept under <pair>/attempts/):\n')
    print('| pair | step | tag | try | rc | wall [s] | CPU [s] | max RSS [MB] |')
    print('|---|---|---|---|---|---|---|---|')
    for r in F:
        print('| %s | %s | %s | %s | %s | %s | %s | %s |' % (r['pair'], r['step'], r['tag'], r['attempt'], r['rc'], r['wall_s'], r['cpu_s'], r['maxrss_MB']))
print('\nwall per event = summed process wall of the successful runs / events with Wire-Cell output; CPU = user + sys.')

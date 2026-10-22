#!/usr/bin/env python3
"""One reco1 / flat-CAF pair through the three steps, with exception handling (HOST side).

    run_pair.py <id> <sim|data> <reco1.root[,reco1.root...]> <flat.caf.root> <workdir> <schema.json>

Multi-reco1 unit (gen2 BNB 1M on Aurora: one flat CAF is made from the reco2 of 20 reco1 files,
one subrun each, 0-6 events after the rockbox filter): the reco1 column holds the files
comma-separated, in the CAF sidecar's parent order (find-pairs.py --caf-sidecar-dir).  Step 1
is ONE lar over all of them (one -s each, art concatenates; --nskip / -n index the
concatenation, so the step-1 slicing below is unchanged); the events are counted per file
(reco1_files.json) and the pair is EMPTY only when every file is.  Steps 2-3 do not care: the
merge keys on run/subrun/event.  Data (FrameShift) gets one step-0 copy per file.

Each step runs inside the SL7 container (site config: WC_WRAP, WC_SL7_SETUP, WC_CPUSET), timed
with /usr/bin/time -v and wrapped in `timeout -k 60 <limit>`.

Exception handling (ai-helper issue 39 log (c)):
  precheck   reco1 and CAF must exist and be non-empty; a /pnfs path must be ONLINE (dCache
             locality), else the pair stops here: "FAIL precheck <why>", no compute spent.
  step 0     DATA only (WC_FRAMESHIFT=1, the default for data): step0-frameshift.sh copies the
             reco1 into <id>/fs/ with the FrameShift product, and step 1 reads that copy.  Run
             once, before the first step-1 job; failure -> "FAIL step0".  Timeout WC_TIMEOUT_STEP0.
  step 1     timeout = WC_TIMEOUT_STEP1_BASE + WC_TIMEOUT_STEP1_PER_EVENT * events.  If lar fails
             or times out, the event it was on (the last "<OpHitSource:tpc0> run R subrun S event E"
             line of lar.log) is skipped and the rest of that slice is rerun as two slices
             (--nskip / -n), recursively, up to WC_STEP1_MAX_BAD skipped events per file.
  step 2     per step-1 tar; timeout = BASE + PER_EVENT * events; WC_STEP2_ATTEMPTS tries (default
             2).  A failed try is kept, never overwritten.
  merge      the complete per-event files (collect-good.py: recTreeWireCell present) from the
             final AND failed step-2 tries are merged; CAF events without one get wc.valid = 0.
  status     OK       every CAF event has Wire-Cell output, nothing failed;
             PARTIAL  merged and validated, but some events have no Wire-Cell output
                      (skipped in step 1, or step 2 never completed them) -- see events.json;
             EMPTY    the reco1 file has no events (its Events tree is empty): nothing to run;
             FAIL <stage> <why>.
  attempts   every failed try is moved to <id>/attempts/<step>-<tag>-try<k>/ and kept.
Resume: a rerun reuses every step-1 slice / step-2 tar that has a DONE marker.
Keep (WC_KEEP), applied once the pair is merged and validated (OK or PARTIAL); a FAIL pair keeps
  everything for debugging.  The FrameShift copy goes right after step 1 in every mode but "all".
    all         keep everything (default)
    minimal     ql/<tag>/qlpctree.tar.gz, merged/, logs; everything else (*.root, *.zip, *.h5,
                pr_evt*/) goes, and so do the pr/<tag>/DONE markers, so a rerun
                (WC_RETRY_PARTIAL=1) redoes step 2 from the kept tars
    validation  as minimal, plus every pr_evt*/tracking-pr.root and the Bee zips
                (ql/<tag>/mabc.zip, pr/<tag>/mabc-pr.zip)
    semiprod    as minimal, plus every pr_evt*/tracking-pr.root (no Bee)
  Failed tries under attempts/ keep only their logs (all but "all").

Layout <workdir>/<id>/: fs/ (step 0, data), ql/<tag>/ (step 1, tag "all" or "s<a>-<b>"), pr/<tag>/ (step 2),
attempts/, merged/, good.txt, events.json, validate.json, cost.tsv, status.
"""
import glob
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import time

ID, REAL, RECO1, CAF, WORK, SCHEMA = sys.argv[1:7]
RECO1S = RECO1.split(',')
BIN = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(WORK, ID)
os.makedirs(os.path.join(D, 'cost'), exist_ok=True)
E = os.environ
WRAP, SETUP = E['WC_WRAP'], E['WC_SL7_SETUP']
CPUSET = E.get('WC_CPUSET', '')
T1B, T1E = int(E.get('WC_TIMEOUT_STEP1_BASE', 900)), int(E.get('WC_TIMEOUT_STEP1_PER_EVENT', 300))
T2B, T2E = int(E.get('WC_TIMEOUT_STEP2_BASE', 600)), int(E.get('WC_TIMEOUT_STEP2_PER_EVENT', 300))
T3 = int(E.get('WC_TIMEOUT_STEP3', 1800))
TV = int(E.get('WC_TIMEOUT_VALIDATE', 3600))
MAX_BAD = int(E.get('WC_STEP1_MAX_BAD', 3))
ATTEMPTS2 = int(E.get('WC_STEP2_ATTEMPTS', 2))
T0 = int(E.get('WC_TIMEOUT_STEP0', 1800))
# RSS watchdog: a step whose process tree (the container, lar / wire-cell / python and their
# children) exceeds WC_STEP_MAX_RSS_GB resident is killed (rc 137, "rss" in the log).  A step-1
# lar is ~1.6 GB and a step-2 wire-cell ~1.4 GB; on Aurora (BNB 1M, 2026-10-22) step-1 lars that
# froze at the GDML geometry import grew to ~500 GB each, pushed the node into swap for the 4-h
# step timeout and stalled the whole pool.  0 disables.
MAX_RSS_GB = float(E.get('WC_STEP_MAX_RSS_GB', 48))
RSS_POLL_S = int(E.get('WC_RSS_POLL_S', 20))
FRAMESHIFT = E.get('WC_FRAMESHIFT', '1' if REAL == 'data' else '0') == '1'
KEEP = E.get('WC_KEEP', 'all')
# Provenance (sbnd-wirecell-production #1): the files this pair stands for, when RECO1/CAF are
# local copies (a grid job's scratch copies).  WC_STAMP_INPUT_FILE=1 makes step 1 record
# WC_RECO1_ORIG (default RECO1) as the event's input_file (larwirecell WCLS_INPUT_FILE) -- also the
# fix for data, whose step 1 reads the FrameShift copy.  Default off: unchanged.
RECO1_ORIG = E.get('WC_RECO1_ORIG', RECO1)
CAF_ORIG = E.get('WC_CAF_ORIG', CAF)
STAMP = E.get('WC_STAMP_INPUT_FILE', '0') == '1'
# Multi-reco1 units: the event numbers of the 20 subruns collide (1..10 each), so step 2 names
# its per-event directories by run/subrun/event (toolkit per_event_name tokens) instead of the
# event number; single-file units keep the r8 layout pr_evt<event>.
if len(RECO1S) > 1 and 'WC_EVT_SUBDIR' not in E:
    os.environ['WC_EVT_SUBDIR'] = 'pr_evt{run}_{subrun}_{event}'
if STAMP and len(RECO1S) > 1 and 'WC_RECO1_ORIG' not in E:
    sys.exit('run_pair.py: WC_STAMP_INPUT_FILE=1 needs WC_RECO1_ORIG with a multi-reco1 unit (one name for all files?)')
if KEEP not in ('all', 'minimal', 'validation', 'semiprod'):
    sys.exit('run_pair.py: WC_KEEP must be all, minimal, validation or semiprod')
COST = os.path.join(D, 'cost.tsv')


def log(msg):
    with open(os.path.join(D, 'run_pair.log'), 'a') as f:
        f.write('%s %s\n' % (time.strftime('%F %T'), msg))


def finish(status, **extra):
    with open(os.path.join(D, 'status'), 'w') as f:
        f.write(status + '\n')
    if extra:
        with open(os.path.join(D, 'events.json'), 'w') as f:
            json.dump(extra, f, indent=1)
    log('status: ' + status)
    sys.exit(0 if status.split()[0] in ('OK', 'PARTIAL', 'EMPTY') else 1)


def du_mb(path):
    tot = 0
    if os.path.isfile(path):
        return os.path.getsize(path) / 1e6
    for dp, _, fs in os.walk(path):
        for f in fs:
            fp = os.path.join(dp, f)
            if os.path.isfile(fp):
                tot += os.path.getsize(fp)
    return tot / 1e6


def cost_row(step, tag, attempt, rc, timefile, out_path):
    wall = cpu = rss = ''
    try:
        txt = open(timefile).read()
        m = re.search(r'Elapsed \(wall clock\) time \(h:mm:ss or m:ss\): (\S+)', txt)
        p = [float(x) for x in m.group(1).split(':')]
        wall = '%.2f' % (p[0] * 3600 + p[1] * 60 + p[2] if len(p) == 3 else p[0] * 60 + p[1])
        u = float(re.search(r'User time \(seconds\): (\S+)', txt).group(1))
        s = float(re.search(r'System time \(seconds\): (\S+)', txt).group(1))
        cpu = '%.2f' % (u + s)
        rss = '%.0f' % (float(re.search(r'Maximum resident set size \(kbytes\): (\d+)', txt).group(1)) / 1024)
    except Exception:
        pass
    new = not os.path.exists(COST)
    with open(COST, 'a') as f:
        if new:
            f.write('step\ttag\tattempt\trc\twall_s\tcpu_s\tmaxrss_MB\tout_MB\n')
        f.write('%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.2f\n' % (step, tag, attempt, rc, wall, cpu, rss,
                                                       du_mb(out_path) if out_path and os.path.exists(out_path) else 0))


def container(name, cmd, timeout_s, cwd=None):
    """Run cmd inside SL7 with the run setup, timed, under timeout -k 60.  Returns (rc, timefile)."""
    timefile = os.path.join(D, 'cost', name + '.time')
    inner = ['/usr/bin/time', '-v', '-o', timefile]
    if CPUSET:
        inner += ['taskset', '-c', CPUSET]
    inner += ['/usr/bin/timeout', '-k', '60', str(timeout_s)] + cmd
    env = dict(os.environ, SL7_SETUP=SETUP)
    if STAMP:
        env['WCLS_INPUT_FILE'] = RECO1_ORIG
    with open(os.path.join(D, 'cost', name + '.out'), 'w') as out:
        p = subprocess.Popen([WRAP] + inner, stdout=out, stderr=subprocess.STDOUT, env=env, cwd=cwd or D)
        peak = 0
        while True:
            try:
                rc = p.wait(timeout=RSS_POLL_S if MAX_RSS_GB > 0 else None)
                break
            except subprocess.TimeoutExpired:
                pass
            rss = tree_rss_kb(p.pid)
            peak = max(peak, rss)
            if rss > MAX_RSS_GB * 1048576:
                log('%s: rss %.1f GB > %.0f GB limit -- killing the process tree; biggest: %s'
                    % (name, rss / 1048576, MAX_RSS_GB, tree_top(p.pid)))
                kill_tree(p.pid)
                rc = p.wait()
                open(os.path.join(D, 'cost', name + '.rss_killed'), 'w').write('%.1f GB\n' % (rss / 1048576))
                rc = 137
                break
    return rc, timefile


def proc_table():
    """pid -> (ppid, rss_kb) for every process, from /proc (no ps: it can take > 30 s on a busy login node)."""
    t = {}
    page_kb = os.sysconf('SC_PAGE_SIZE') // 1024
    for name in os.listdir('/proc'):
        if not name.isdigit():
            continue
        try:
            with open('/proc/%s/stat' % name) as f:
                st = f.read()
            with open('/proc/%s/statm' % name) as f:
                rss_pages = int(f.read().split()[1])
        except OSError:
            continue
        # field 4 (ppid) comes after the ")" that closes the comm field
        ppid = int(st[st.rindex(')') + 2:].split()[1])
        t[int(name)] = (ppid, rss_pages * page_kb)
    return t


def tree_pids(root, table=None):
    table = table if table is not None else proc_table()
    kids = {}
    for pid, (ppid, _) in table.items():
        kids.setdefault(ppid, []).append(pid)
    out, todo = [], [root]
    while todo:
        pid = todo.pop()
        out.append(pid)
        todo.extend(kids.get(pid, []))
    return out, table


def tree_rss_kb(root):
    pids, table = tree_pids(root)
    return sum(table[pid][1] for pid in pids if pid in table)


def tree_top(root, n=3):
    """The n biggest processes of the tree as 'pid comm rss_GB', for the kill log line."""
    pids, table = tree_pids(root)
    rows = []
    for pid in pids:
        if pid not in table:
            continue
        try:
            with open('/proc/%d/comm' % pid) as f:
                comm = f.read().strip()
        except OSError:
            comm = '?'
        rows.append((table[pid][1], pid, comm))
    rows.sort(reverse=True)
    return ', '.join('%d %s %.1f GB' % (pid, comm, kb / 1048576) for kb, pid, comm in rows[:n])


def kill_tree(root):
    import signal
    pids, _ = tree_pids(root)
    for pid in reversed(pids):      # children first
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def next_attempt_dir(prefix):
    os.makedirs(os.path.join(D, 'attempts'), exist_ok=True)
    k = 1
    while os.path.exists(os.path.join(D, 'attempts', '%s-try%d' % (prefix, k))):
        k += 1
    return os.path.join(D, 'attempts', '%s-try%d' % (prefix, k)), k


# ---------------------------------------------------------------- precheck (fix 1)
def locality_ok(path):
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return False, 'missing or empty: ' + path
    if path.startswith('/pnfs/'):
        d, n = os.path.split(path)
        try:
            loc = open(os.path.join(d, '.(get)(%s)(locality)' % n)).read().strip()
        except OSError:
            loc = 'UNKNOWN'
        if loc not in ('ONLINE', 'ONLINE_AND_NEARLINE'):
            return False, 'not on disk (dCache locality %s): %s' % (loc, path)
    return True, ''


log('start %s %s reco1=%s caf=%s' % (ID, REAL, RECO1, CAF))
for what, p in [('reco1', r) for r in RECO1S] + [('caf', CAF)]:
    ok, why = locality_ok(p)
    if not ok:
        finish('FAIL precheck %s %s' % (what, why))

# ---------------------------------------------------------------- step 0: FrameShift (data)
FSDIR = os.path.join(D, 'fs')


def fscopy(r1):
    return os.path.join(FSDIR, os.path.basename(r1)[:-len('.root')] + '_frameshift.root')


def step1_input():
    """What step 1 reads (comma-separated): the reco1 file(s), or (data) their FrameShift copies,
    made on first use."""
    if not FRAMESHIFT:
        return RECO1
    for i, r1 in enumerate(RECO1S):
        fc = fscopy(r1)
        if not os.path.exists(fc):
            tag = 'all' if len(RECO1S) == 1 else 'f%d' % i
            rc, tf = container('step0-' + tag, [os.path.join(BIN, 'step0-frameshift.sh'), r1, fc], T0)
            cost_row('step0', tag, 1, rc, tf, fc)
            if rc != 0:
                finish('FAIL step0 frameshift rc %d on %s (see fs/frameshift-lar.log.gz, cost/step0-%s.out)' % (rc, r1, tag))
            log('step0 FrameShift copy %s' % fc)
    return ','.join(fscopy(r1) for r1 in RECO1S)


# ---------------------------------------------------------------- step 1 (fixes 2, 4, 5)
nfile = os.path.join(D, 'reco1_events')
if not os.path.exists(nfile) or not os.path.exists(os.path.join(D, 'reco1_files.json')):
    rc, _ = container('count-events', ['python3', os.path.join(BIN, 'count-events.py')] + RECO1S, 600)
    try:
        lines = open(os.path.join(D, 'cost', 'count-events.out')).read().strip().splitlines()
        n = int(lines[-1].split()[-1])
        per_file = [{'reco1': l.split(' ', 1)[1], 'events': int(l.split(' ', 1)[0])} for l in lines[-1 - len(RECO1S):-1]]
        assert len(per_file) == len(RECO1S)
    except Exception:
        finish('FAIL precheck cannot count the events of the reco1 file(s) (rc %d)' % rc)
    with open(os.path.join(D, 'reco1_files.json'), 'w') as f:
        json.dump(per_file, f, indent=1)
    open(nfile, 'w').write('%d\n' % n)
NEV = int(open(nfile).read())
RECO1_FILES = json.load(open(os.path.join(D, 'reco1_files.json')))
if len(RECO1S) > 1:
    log('multi-reco1 unit: %d files, %d events (%s)' % (len(RECO1S), NEV, ' '.join(str(x['events']) for x in RECO1_FILES)))
if NEV == 0:
    finish('EMPTY no events in the reco1 file(s)', reco1_events=0, reco1_files=RECO1_FILES)

OPHIT = re.compile(r'<OpHitSource:tpc0> run (\d+) subrun (\d+) event (\d+)')


def read_lar_log(dirpath):
    for name in ('lar.log', 'lar.log.gz'):
        p = os.path.join(dirpath, name)
        if os.path.exists(p):
            op = gzip.open if name.endswith('.gz') else open
            with op(p, 'rt', errors='replace') as f:
                return f.read()
    return ''


def ql_tag(a, b):
    return 'all' if (a, b) == (0, NEV) else 's%d-%d' % (a, b)


slices, tars, skipped, lost = [(0, NEV)], [], [], []
while slices:
    a, b = slices.pop(0)
    if a >= b:
        continue
    tag = ql_tag(a, b)
    qdir = os.path.join(D, 'ql', tag)
    if os.path.exists(os.path.join(qdir, 'DONE')):
        tars.append((tag, b - a, os.path.join(qdir, 'qlpctree.tar.gz')))
        continue
    os.makedirs(qdir, exist_ok=True)
    rc, tf = container('step1-' + tag, [os.path.join(BIN, 'step1.sh'), step1_input(), qdir, REAL, str(a), str(b - a)],
                       T1B + T1E * (b - a))
    cost_row('step1', tag, 1, rc, tf, qdir)
    if rc == 0:
        open(os.path.join(qdir, 'DONE'), 'w').write('')
        tars.append((tag, b - a, os.path.join(qdir, 'qlpctree.tar.gz')))
        continue
    # failed, timed out (124) or killed by the RSS watchdog (137): find the event it was on,
    # keep the try, slice around it
    seen = OPHIT.findall(read_lar_log(qdir))
    order = []
    for r in seen:
        if not order or order[-1] != r:
            order.append(r)
    keep, _ = next_attempt_dir('step1-' + tag)
    shutil.move(qdir, keep)
    log('step1 %s rc %d (%s); kept in %s' % (tag, rc, 'timeout' if rc in (124, 137) else 'failed', keep))
    if not order or len(skipped) >= MAX_BAD:
        why = 'cannot locate the failing event' if not order else 'more than %d bad events' % MAX_BAD
        lost.append({'slice': [a, b], 'why': why, 'rc': rc})
        log('step1 %s: giving up on events %d..%d: %s' % (tag, a, b - 1, why))
        continue
    bad = a + len(order) - 1
    skipped.append({'index': bad, 'rse': [int(x) for x in order[-1]], 'rc': rc,
                    'why': 'timeout' if rc in (124, 137) else 'lar rc %d' % rc})
    log('step1 %s: skipping event index %d rse %s; rerunning %d..%d and %d..%d' %
        (tag, bad, order[-1], a, bad - 1, bad + 1, b - 1))
    slices[:0] = [(a, bad), (bad + 1, b)]

if not tars:
    finish('FAIL step1 no step-1 output', skipped=skipped, lost_slices=lost)
if KEEP != 'all' and os.path.isdir(FSDIR):
    for f in glob.glob(os.path.join(FSDIR, '*.root*')):
        os.remove(f)

# ---------------------------------------------------------------- step 2 (fixes 2, 3, 5)
pr_dirs, failed_dirs, step2_failed = [], [], []
for tag, n, tar in tars:
    pdir = os.path.join(D, 'pr', tag)
    if os.path.exists(os.path.join(pdir, 'DONE')):
        pr_dirs.append(pdir)
        continue
    ok = False
    for k in range(ATTEMPTS2):
        os.makedirs(pdir, exist_ok=True)
        rc, tf = container('step2-%s-a%d' % (tag, k + 1), [os.path.join(BIN, 'step2.sh'), tar, pdir, REAL],
                           T2B + T2E * n)
        cost_row('step2', tag, k + 1, rc, tf, pdir)
        if rc == 0:
            open(os.path.join(pdir, 'DONE'), 'w').write('')
            ok = True
            break
        keep, _ = next_attempt_dir('step2-' + tag)
        shutil.move(pdir, keep)
        failed_dirs.append(keep)
        log('step2 %s try %d rc %d (%s); kept in %s' % (tag, k + 1, rc, 'timeout' if rc in (124, 137) else 'failed', keep))
    if ok:
        pr_dirs.append(pdir)
    else:
        step2_failed.append(tag)
# earlier failed tries of this pair (previous runs) also count for the partial merge
failed_dirs += [p for p in sorted(glob.glob(os.path.join(D, 'attempts', 'step2-*-try*'))) if p not in failed_dirs]

good = os.path.join(D, 'good.txt')
rc, _ = container('collect', ['python3', os.path.join(BIN, 'collect-good.py'), '-o', good] + pr_dirs + failed_dirs, 1800)
try:
    coll = json.loads(open(os.path.join(D, 'cost', 'collect.out')).read().strip().splitlines()[-1])
except Exception:
    finish('FAIL step2 cannot collect the step-2 files (rc %d)' % rc)
if coll['complete'] == 0:
    finish('FAIL step2 no complete Wire-Cell event', skipped=skipped, lost_slices=lost, step2_failed=step2_failed)

# ---------------------------------------------------------------- step 3 + validation
cafn = os.path.basename(CAF)
for ext in ('.flat.caf.root', '.caf.root', '.root'):
    if cafn.endswith(ext):
        out_name = cafn[:-len(ext)] + '.wc' + ext
        break
mdir = os.path.join(D, 'merged')
os.makedirs(mdir, exist_ok=True)
merged = os.path.join(mdir, out_name)
rc, tf = container('step3', ['python3', os.path.join(BIN, 'merge-caf.py'), '--caf', CAF, '--out', merged,
                             '--schema', SCHEMA, '--summary', os.path.join(mdir, 'merge.json')]
                   + (['--caf-name', CAF_ORIG] if CAF_ORIG != CAF else []) + ['@' + good], T3)
cost_row('step3', 'all', 1, rc, tf, merged)
if rc != 0:
    finish('FAIL step3 merge rc %d' % rc, skipped=skipped, lost_slices=lost, step2_failed=step2_failed)
if E.get('WC_VALIDATE', '1') == '1':
    rc, tf = container('validate', ['python3', os.path.join(BIN, 'validate-merge.py'), '--merged', merged,
                                    '--caf', CAF, '--json', os.path.join(D, 'validate.json'), '@' + good], TV)
    cost_row('validate', 'all', 1, rc, tf, None)
    if rc != 0:
        finish('FAIL validate rc %d' % rc, skipped=skipped, lost_slices=lost, step2_failed=step2_failed)


def cleanup(keep_mode):
    """WC_KEEP != all: delete the large files the mode does not keep (see the docstring)."""
    n, mb = 0, 0.0
    keep_pr = keep_mode in ('validation', 'semiprod')     # pr_evt*/tracking-pr.root (+ DONE)
    keep_bee = keep_mode == 'validation'                  # mabc.zip, mabc-pr.zip

    def rm(p):
        nonlocal n, mb
        mb += du_mb(p)
        n += 1
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
    big = ('.root', '.zip', '.h5', '.tar.gz', '.root.tmp')
    for f in glob.glob(os.path.join(FSDIR, '*.root*')):
        rm(f)
    for qd in glob.glob(os.path.join(D, 'ql', '*')) + glob.glob(os.path.join(D, 'attempts', 'step1-*')):
        final = os.path.dirname(qd) == os.path.join(D, 'ql')
        for f in os.listdir(qd):
            if f.endswith(big) and not (final and (f == 'qlpctree.tar.gz' or (keep_bee and f == 'mabc.zip'))):
                rm(os.path.join(qd, f))
    for pd in glob.glob(os.path.join(D, 'pr', '*')) + glob.glob(os.path.join(D, 'attempts', 'step2-*')):
        final = os.path.dirname(pd) == os.path.join(D, 'pr')
        for f in os.listdir(pd):
            if final and keep_pr and (f.startswith('pr_evt') or f == 'DONE'):
                continue
            if final and keep_bee and f == 'mabc-pr.zip':
                continue
            if f.startswith('pr_evt') or f.endswith(big) or f == 'DONE':
                rm(os.path.join(pd, f))
    left = [(du_mb(os.path.join(dp, f)), os.path.join(dp, f)) for dp, _, fs in os.walk(D) for f in fs
            if not dp.startswith(mdir) and f != 'qlpctree.tar.gz']
    left = [x for x in left if x[0] > 5 and not (keep_pr and '/pr_evt' in x[1]) and not (keep_bee and x[1].endswith('.zip'))]
    log('keep=%s: removed %d files/dirs, %.1f MB%s' % (keep_mode, n, mb, ('; still > 5 MB: %s' % left) if left else ''))


if KEEP != 'all':
    cleanup(KEEP)
mj = json.load(open(os.path.join(mdir, 'merge.json')))
missing = mj['n_caf_events_without_wirecell']
info = dict(skipped=skipped, lost_slices=lost, step2_failed=step2_failed, caf_events=mj['n_caf_events'],
            wirecell_events=mj['n_wirecell_events'], caf_events_without_wirecell=missing,
            incomplete_files=coll['incomplete'], reco1_events=NEV, reco1_files=RECO1_FILES)
finish('OK' if (missing == 0 and not skipped and not lost and not step2_failed) else 'PARTIAL', **info)

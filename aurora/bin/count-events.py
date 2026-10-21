#!/usr/bin/env python3
"""Print the number of art events in artROOT files (their Events tree).  Run inside SL7.
    count-events.py <file.root> [<file.root> ...]
One line "<n> <file>" per file, then the total ALONE on the last line (run_pair.py reads that)."""
import sys
import ROOT
ROOT.gErrorIgnoreLevel = ROOT.kError
tot = 0
for fn in sys.argv[1:]:
    f = ROOT.TFile.Open(fn)
    t = f.Get('Events') if f else None
    if not t:
        sys.exit('count-events.py: no Events tree in %s' % fn)
    n = int(t.GetEntries())
    tot += n
    print('%d %s' % (n, fn))
print(tot)

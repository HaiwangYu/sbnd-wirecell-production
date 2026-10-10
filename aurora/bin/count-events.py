#!/usr/bin/env python3
"""Print the number of art events in an artROOT file (its Events tree).  Run inside SL7.
    count-events.py <file.root>"""
import sys
import ROOT
ROOT.gErrorIgnoreLevel = ROOT.kError
f = ROOT.TFile.Open(sys.argv[1])
t = f.Get('Events') if f else None
if not t:
    sys.exit('count-events.py: no Events tree in %s' % sys.argv[1])
print(int(t.GetEntries()))

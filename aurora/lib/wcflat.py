"""Shared helpers for the Wire-Cell flat tree (recTreeWireCell) and the flat CAF.

The flat tree is written per event by the toolkit's RootFlatTreeVisitor into
pr_evt<E>/tracking-pr.root (wire-cell-toolkit branch sbnd-wc-flatcaf; ai-helper
issue 39).  Layout, prefix "wc":

    wc.run, wc.subrun, wc.evt, wc.valid          Int_t scalars
    wc.<T>..length                               Int_t, rows of row-tree T
    wc.<T>.<b>[wc.<T>..length]                   a scalar branch b of T
    wc.<T>.<b>..length/..idx[wc.<T>..length]     a vector / string branch b ...
    wc.<T>.<b>..totarraysize                     ... its flat size
    wc.<T>.<b>[wc.<T>.<b>..totarraysize]         ... and the flat elements
    wc.<T>.<b>.v..length/..idx/..totarraysize, wc.<T>.<b>.v   vector<vector> inner level

Every branch has ONE leaf; an array leaf's size is a scalar Int_t leaf (its
"count").  So a schema is the ordered list of (name, ROOT type, count).

PyROOT only (no uproot), so it runs in any of the SL7 LArSoft environments.
"""
import json

import numpy as np

import ROOT

ROOT.gErrorIgnoreLevel = ROOT.kError

# ROOT leaf type name -> (numpy dtype, leaf-list code)
TYPES = {
    'Int_t': (np.int32, 'I'), 'UInt_t': (np.uint32, 'i'),
    'Float_t': (np.float32, 'F'), 'Double_t': (np.float64, 'D'),
    'Long64_t': (np.int64, 'L'), 'ULong64_t': (np.uint64, 'l'),
    'Short_t': (np.int16, 'S'), 'UShort_t': (np.uint16, 's'),
    'Char_t': (np.int8, 'B'), 'UChar_t': (np.uint8, 'b'), 'Bool_t': (np.bool_, 'O'),
}

TREE_NAME = 'recTreeWireCell'
PREFIX = 'wc'
HEADER = ['run', 'subrun', 'evt', 'valid']


def tree_schema(tree):
    """The (name, type, count) list of a flat tree, in branch order."""
    out = []
    for br in tree.GetListOfBranches():
        leaves = br.GetListOfLeaves()
        if leaves.GetEntries() != 1:
            raise ValueError('branch %s has %d leaves' % (br.GetName(), leaves.GetEntries()))
        leaf = leaves.At(0)
        lc = leaf.GetLeafCount()
        typ = leaf.GetTypeName()
        if typ not in TYPES:
            raise ValueError('branch %s: unsupported type %s' % (br.GetName(), typ))
        out.append({'name': br.GetName(), 'type': typ, 'count': lc.GetName() if lc else None})
    return out


def load_schema(path):
    with open(path) as f:
        js = json.load(f)
    return js['branches'] if isinstance(js, dict) else js


def leaf_array(leaf, n):
    """A copy of the first n values of a leaf's buffer, with the leaf's own dtype.
    Read as raw bytes from the buffer address (cppyy would turn a Char_t* into a
    Python str)."""
    dt = TYPES[leaf.GetTypeName()][0]
    if n <= 0:
        return np.zeros(0, dtype=dt)
    import ctypes
    import cppyy
    addr = cppyy.ll.cast['uintptr_t'](leaf.GetValuePointer())
    size = np.dtype(dt).itemsize
    if leaf.GetLenType() != size:
        raise ValueError('leaf %s: element size %d, expected %d' % (leaf.GetName(), leaf.GetLenType(), size))
    return np.frombuffer(ctypes.string_at(addr, n * size), dtype=dt).copy()


def read_flat_entry(tree, entry=0):
    """{branch name: numpy array} of one entry of a flat tree (scalars as length-1 arrays)."""
    tree.GetEntry(entry)
    out = {}
    for br in tree.GetListOfBranches():
        leaf = br.GetListOfLeaves().At(0)
        out[br.GetName()] = leaf_array(leaf, leaf.GetLen())
    return out


def rse_of_flat(path):
    """(run, subrun, evt) of the one entry of recTreeWireCell in a tracking-pr.root, or None."""
    try:
        f = ROOT.TFile.Open(path)
    except OSError:        # ROOT >= 6.28 raises instead of returning a zombie (a truncated file
        return None        # left by a killed step 2 made collect-good.py fail the unit)
    if not f or f.IsZombie():
        return None
    t = f.Get(TREE_NAME)
    if not t or t.GetEntries() < 1:
        f.Close()
        return None
    t.GetEntry(0)
    r = tuple(int(t.GetLeaf('%s.%s' % (PREFIX, k)).GetValue()) for k in ('run', 'subrun', 'evt'))
    f.Close()
    return r

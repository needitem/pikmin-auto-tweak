#!/usr/bin/env python3
"""Architecture check: a module may import only from its own layer or one below.

Layers, top to bottom: App, Passes, Rpc, Model, Game, IL2CPP, Support (see README).
Run by tests/run.sh; exits 1 and lists the offending imports.
"""
import glob, os, re, sys

ORDER = ['App', 'Passes', 'Rpc', 'Model', 'Game', 'IL2CPP', 'Support']
rank = {n: i for i, n in enumerate(ORDER)}
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Sources')

owner = {os.path.basename(f): f.split(os.sep)[-2] for f in glob.glob(os.path.join(root, '*', '*'))}
bad = []
for f in glob.glob(os.path.join(root, '*', '*.mm')) + glob.glob(os.path.join(root, '*', '*.h')):
    mine = f.split(os.sep)[-2]
    for m in re.finditer(r'#import "([^"]+)"', open(f).read()):
        layer = owner.get(m.group(1))
        if layer and rank[layer] < rank[mine]:
            bad.append('  %s/%s imports %s (%s is above %s)' % (mine, os.path.basename(f), m.group(1), layer, mine))
if bad:
    print('layering violations:'); print('\n'.join(bad)); sys.exit(1)
print('layering ok')

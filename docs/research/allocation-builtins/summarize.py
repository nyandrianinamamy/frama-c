#!/usr/bin/env python3
"""Aggregate allocation-builtin counts per target. Usage: summarize.py CAMPAIGN OSCS OLD_HEAP_RESULTS OUTDIR (OLD_HEAP_RESULTS: per-target results of the heap-refusal measurement, or - to skip the cross-check)"""
import csv, os, re, sys
camp, oscs, old_path, out = sys.argv[1:5]
CANON = {
 'malloc':'malloc','Frama_C_malloc':'malloc',
 'calloc':'calloc','Frama_C_calloc':'calloc',
 'realloc':'realloc','Frama_C_realloc':'realloc',
 'reallocarray':'reallocarray','Frama_C_reallocarray':'reallocarray',
 'alloca':'alloca','Frama_C_alloca':'alloca',
 '__fc_vla_alloc':'vla','Frama_C_vla_alloc':'vla',
 'free':'free','Frama_C_free':'free',
 '__fc_vla_free':'vla_free','Frama_C_vla_free':'vla_free',
 'Frama_C_check_leak':'check_leak'}
ALLOC = ['malloc','calloc','realloc','reallocarray','alloca','vla']
FREE = ['free','vla_free']
OTHER = FREE + ['check_leak']
manifest = [l.strip() for l in open(os.path.join(camp,'manifest')) if l.strip()]
outcomes = {r['case']: r for r in csv.DictReader(open(os.path.join(camp,'outcomes.tsv')), delimiter='\t')}
old = {} if old_path == '-' else {r['case']: r for r in csv.DictReader(open(old_path), delimiter='\t')}
tags = {}
for d in os.listdir(oscs):
    p = os.path.join(oscs, d, 'OSCS-README.txt')
    if os.path.isfile(p):
        m = re.search(r'((?:NO|HAS|UNUSED)_DYN_ALLOC(?:\(tests\))?)', open(p, errors='replace').read())
        tags[d] = m.group(1) if m else 'untagged'
rows, problems, unknown_builtins = [], [], set()
for t in manifest:
    o = outcomes.get(t)
    h = os.path.join(camp, t, 'heap.tsv')
    if not o or o['make_exit'] != '0' or o['analysis_complete'] != 'true' or not os.path.exists(h):
        problems.append((t, 'incomplete', o)); continue
    kv = dict(l.rstrip('\n').split('\t') for l in open(h))
    counts = {k: 0 for k in ALLOC + OTHER}
    for r in csv.DictReader(open(h + '.calls.tsv'), delimiter='\t'):
        if r['kind'] != 'apply': continue
        c = CANON.get(r['function'])
        if c: counts[c] += int(r['count'])
        else: unknown_builtins.add(r['function'])
    row = dict(case=t, dir=t.split('/')[0], tag=tags.get(t.split('/')[0], 'no-readme'),
               bodies=int(kv['body_analysed']), cpu=float(kv['analysis_cpu_s']),
               heap_created=int(kv['heap_created']), stack_created=int(kv['stack_alloc_created']),
               heap_refused=int(kv['heap_refused']), **counts)
    row['alloc_calls'] = sum(counts[k] for k in ALLOC)
    row['any_calls'] = row['alloc_calls'] + sum(counts[k] for k in OTHER)
    row['alloc_only_A'] = row['alloc_calls'] == 0
    row['in_A'] = row['alloc_calls'] + sum(counts[k] for k in FREE) == 0
    row['in_A_strict'] = row['any_calls'] == 0
    # consistency checks
    if row['heap_created'] and not (counts['malloc'] + counts['calloc'] + counts['realloc'] + counts['reallocarray']):
        problems.append((t, 'heap base without heap builtin', row))
    if row['stack_created'] and not (counts['alloca'] + counts['vla']):
        problems.append((t, 'stack base without alloca/vla builtin', row))
    ot = old.get(t)
    if ot is None and old: problems.append((t, 'missing in #14 results', None))
    elif ot:
        if int(ot['body_calls']) != row['bodies']: problems.append((t, f"bodies {row['bodies']} vs #14 {ot['body_calls']}", None))
        if int(ot['new_heap_bases']) != row['heap_created']: problems.append((t, f"heap bases {row['heap_created']} vs #14 {ot['new_heap_bases']}", None))
        if row['in_A'] and int(ot['heap_refused']) > 0: problems.append((t, 'in A but refused in #14', None))
    rows.append(row)
os.makedirs(out, exist_ok=True)
cols = ['case','dir','tag','in_A','alloc_only_A','in_A_strict','bodies','cpu','heap_created','stack_created','heap_refused'] + ALLOC + OTHER
with open(os.path.join(out,'per-target.tsv'),'w') as f:
    w = csv.DictWriter(f, cols, delimiter='\t', extrasaction='ignore'); w.writeheader(); w.writerows(rows)
N = len(manifest); B = sum(r['bodies'] for r in rows); C = sum(r['cpu'] for r in rows)
def share(sel, name):
    s = [r for r in rows if sel(r)]
    b = sum(r['bodies'] for r in s); c = sum(r['cpu'] for r in s)
    print(f"{name}: targets {len(s)}/{N} ({100*len(s)/N:.2f}%), bodies {b}/{B} ({100*b/B:.2f}%), cpu {c:.2f}/{C:.2f} s ({100*c/C:.2f}%)")
print(f"completed {len(rows)}/{N}; problems {len(problems)}; unknown builtin names applied: {sorted(unknown_builtins)}")
share(lambda r: r['in_A'], 'set A (no allocation or free builtin)')
share(lambda r: r['alloc_only_A'], 'no allocation builtin, free ignored')
share(lambda r: r['alloc_only_A'] and not r['in_A'], 'excluded only by free')
share(lambda r: r['in_A'] and not r['in_A_strict'], 'in A but check_leak runs')
share(lambda r: not r['in_A'], 'outside A')
print('old #14 no-refusal targets:', sum(1 for t,o in old.items() if int(o['heap_refused'])==0))
print('builtin totals:', {k: sum(r[k] for r in rows) for k in ALLOC+OTHER})
print('targets with each builtin:', {k: sum(1 for r in rows if r[k]) for k in ALLOC+OTHER})
for p in problems[:40]: print('PROBLEM', p[0], p[1])
# per directory vs tag
print('\ndir\ttag\ttargets\tin_A\toutside_A')
dirs = {}
for r in rows: dirs.setdefault(r['dir'], []).append(r)
for d in sorted(dirs):
    rs = dirs[d]; a = sum(r['in_A'] for r in rs)
    print(f"{d}\t{rs[0]['tag']}\t{len(rs)}\t{a}\t{len(rs)-a}")
print('\nTop outside A by bodies:')
for r in sorted((r for r in rows if not r['in_A']), key=lambda r: -r['bodies'])[:15]:
    print(r['case'], r['bodies'], f"{r['cpu']:.2f}", {k: r[k] for k in ALLOC+OTHER if r[k]})

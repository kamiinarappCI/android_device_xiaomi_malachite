#!/usr/bin/env python3
"""Check that every vendor/odm/device init service has a domain init can enter,
and that vendor.prop, odm.prop and vendor rc setprops are settable by
vendor_init (init silently drops the rest). Run in WSL from the source root
after `m selinux_policy libsepolwrap`:

  python3 /mnt/e/LineageOS-23.2-Malachite/tools/policy_check_vendor.py out/host/linux-x86/lib64/libsepolwrap.so
"""
import glob, os, re, sys
sys.path.insert(0, os.path.expanduser('~/android/lineage/system/sepolicy/tests'))
import policy as P

root = os.path.expanduser('~/android/lineage')
O = root + '/out/target/product/malachite'
pol = P.Policy(O + '/odm/etc/selinux/precompiled_sepolicy', None, sys.argv[1])
allow = {}
for r in pol.QueryExpandedTERule():
    allow.setdefault((r.sctx, r.tctx, r.tclass), set()).update(r.perms)
def has(s, t, c, p):
    return p in allow.get((s, t, c), set())

# ---- file contexts (last match wins; files are fc_sort'ed)
fc = []
for f in [O + '/system/etc/selinux/plat_file_contexts', O + '/vendor/etc/selinux/vendor_file_contexts',
          O + '/odm/etc/selinux/odm_file_contexts', O + '/product/etc/selinux/product_file_contexts', O + '/system_ext/etc/selinux/system_ext_file_contexts']:
    if not os.path.exists(f):
        continue
    for line in open(f):
        line = line.split('#')[0].split()
        if len(line) < 2:
            continue
        rx, ctx = line[0], line[-1]
        if len(line) == 3 and line[1] not in ('--', '-d'):
            continue
        try:
            fc.append((re.compile('^' + rx + '$'), ctx.split(':')[2]))
        except re.error:
            pass
def flabel(path):
    t = None
    for rx, ty in fc:
        if rx.match(path):
            t = ty
    return t

bad = 0
def fail(msg):
    global bad
    bad += 1
    print('FAIL ' + msg)

# ---- rc files that end up on vendor/odm
rcs = glob.glob(root + '/vendor/xiaomi/malachite/proprietary/vendor/etc/init/**/*.rc', recursive=True)
rcs += glob.glob(root + '/vendor/xiaomi/malachite/proprietary/odm/etc/init/**/*.rc', recursive=True)
rcs += glob.glob(root + '/device/xiaomi/malachite/**/*.rc', recursive=True)
rcs = [r for r in rcs if '/recovery' not in r and 'recovery.' not in os.path.basename(r)]
domains_by_exec = {}
for (s, t, c), perms in allow.items():
    if c == 'file' and 'entrypoint' in perms:
        domains_by_exec.setdefault(t, set()).add(s)

print('== services (%d rc files)' % len(rcs))
nsvc = 0
for rc in rcs:
    lines = open(rc, errors='replace').read().splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r'\s*service\s+(\S+)\s+(\S+)', lines[i])
        if not m:
            i += 1; continue
        name, exe = m.groups()
        j = i + 1; seclabel = None
        while j < len(lines) and not re.match(r'\s*(service|on|import)\s', lines[j]):
            s = re.match(r'\s*seclabel\s+(\S+)', lines[j])
            if s: seclabel = s.group(1)
            j += 1
        i = j
        nsvc += 1
        if seclabel:
            continue
        exe = re.sub(r'^/system/vendor/', '/vendor/', exe)
        t = flabel(exe)
        doms = {d for d in domains_by_exec.get(t, ()) if has('init', d, 'process', 'transition')}
        if not doms:
            fail('%s: service %s %s [%s] has no domain init can enter' % (os.path.relpath(rc, root), name, exe, t))
print('%d services checked' % nsvc)

# ---- property contexts
pc = []
for f in [O + '/system/etc/selinux/plat_property_contexts', O + '/vendor/etc/selinux/vendor_property_contexts',
          O + '/odm/etc/selinux/odm_property_contexts', O + '/product/etc/selinux/product_property_contexts', O + '/system_ext/etc/selinux/system_ext_property_contexts']:
    if not os.path.exists(f):
        continue
    for line in open(f):
        w = line.split('#')[0].split()
        if len(w) >= 2:
            pc.append((w[0], w[1].split(':')[2], len(w) > 2 and w[2] == 'exact'))
def plabel(name):
    best = None
    for key, t, exact in pc:
        if exact and key == name:
            return t
    for key, t, exact in pc:
        if not exact and name.startswith(key) and (best is None or len(key) > len(best[0])):
            best = (key, t)
    return best[1] if best else 'default_prop'

print('== vendor/odm build props settable by vendor_init')
props = []
for f in ['vendor.prop', 'odm.prop']:
    for line in open(root + '/device/xiaomi/malachite/' + f):
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            props.append((f, line.split('=', 1)[0].strip()))
for f, name in props:
    t = plabel(name)
    if not has('vendor_init', t, 'property_service', 'set'):
        fail('%s: %s [%s] not settable by vendor_init' % (f, name, t))
print('%d props checked' % len(props))

print('== setprop in vendor rc files')
n = 0
for rc in rcs:
    for k, line in enumerate(open(rc, errors='replace'), 1):
        m = re.match(r'\s*setprop\s+(\S+)', line)
        if not m or '$' in m.group(1):
            continue
        n += 1
        t = plabel(m.group(1))
        if not has('vendor_init', t, 'property_service', 'set'):
            fail('%s:%d setprop %s [%s]' % (os.path.relpath(rc, root), k, m.group(1), t))
print('%d setprops checked' % n)
print('\n%d problem(s)' % bad)

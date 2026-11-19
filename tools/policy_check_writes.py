#!/usr/bin/env python3
"""Check the device's init writes, powerhint nodes, TEE access and ADPF grants
against a compiled policy. Run in WSL from the source root after
`m selinux_policy libsepolwrap`:

  O=out/target/product/malachite
  python3 /mnt/e/LineageOS-23.2-Malachite/tools/policy_check_writes.py     $O/odm/etc/selinux/precompiled_sepolicy out/host/linux-x86/lib64/libsepolwrap.so     device/xiaomi/malachite vendor/xiaomi/malachite/proprietary/vendor/etc/init/tee-supplicant.rc

Labels come from genfscon only; /config (configfs) paths are not resolved.
Takes a few minutes: it expands every allow rule."""
import json, os, re, sys
sys.path.insert(0, os.path.expanduser('~/android/lineage/system/sepolicy/tests'))
import policy as P

GENFS = []
def _add(self, Dict, buf):
    fs, rest = buf.split(' ', 1)
    path, ctx = rest.rsplit(' ', 1)
    GENFS.append((fs, path, ctx.split(':')[2]))
P.Policy._Policy__GenfsDictAdd = _add

pol = P.Policy(sys.argv[1], None, sys.argv[2])
dev = sys.argv[3]
rules = list(pol.QueryExpandedTERule())
allow = {}
for r in rules:
    if r.flavor != 'allow':
        continue
    allow.setdefault((r.sctx, r.tctx, r.tclass), set()).update(r.perms)

def can(s, t, c, perms):
    got = allow.get((s, t, c), set())
    return set(perms) - got

def genfs(fs, path):
    best = None
    for f, p, t in GENFS:
        if f == fs and (path == p or path.startswith(p.rstrip('/') + '/') or p == '/'):
            if best is None or len(p) > len(best[0]):
                best = (p, t)
    return best[1] if best else None

def label(path):
    if path.startswith('/sys/'):
        return genfs('sysfs', path[4:])
    if path.startswith('/proc/'):
        return genfs('proc', path[5:])
    if path.startswith('/dev/sys/fs/by-name/userdata/'):
        return genfs('sysfs', '/fs/f2fs/x/' + path.rsplit('/', 1)[1])
    for cg in ('/dev/cpuctl', '/dev/cpuset', '/dev/blkio'):
        if path.startswith(cg):
            return genfs('cgroup', '/') or 'cgroup'
    return None

bad = 0
def report(ok, msg):
    global bad
    if not ok:
        bad += 1
    print(('OK   ' if ok else 'FAIL ') + msg)

print('== vendor rc writes (vendor_init)')
rcs = [os.path.join(dev, 'init', f) for f in sorted(os.listdir(os.path.join(dev, 'init'))) if f.endswith('.rc')] + sys.argv[4:]
for rc in rcs:
    for n, line in enumerate(open(rc), 1):
        m = re.match(r'\s*write\s+(\S+)', line)
        if not m or '$' in m.group(1):
            continue
        p = m.group(1)
        t = label(p)
        if t is None:
            print('?    %s:%d %s (no label resolved)' % (os.path.basename(rc), n, p)); continue
        missing = can('vendor_init', t, 'file', {'open', 'write'})
        report(not missing, '%s:%d %s [%s] %s' % (os.path.basename(rc), n, p, t, ('missing ' + ' '.join(sorted(missing))) if missing else ''))

print('== powerhint nodes (hal_power_default)')
j = json.load(open(os.path.join(dev, 'configs/powerhint.json')))
for node in j['Nodes']:
    p = node['Path']
    if not p.startswith('/'):
        continue
    t = label(p)
    if t is None:
        print('?    %s (no label)' % p); continue
    missing = can('hal_power_default', t, 'file', {'open', 'write'})
    report(not missing, '%s [%s] %s' % (p, t, ('missing ' + ' '.join(sorted(missing))) if missing else ''))

print('== TEE clients -> mitee_client_device')
for d in ['tee', 'hal_keymint_default', 'hal_gatekeeper_default', 'hal_identity_default',
          'hal_fingerprint_default', 'hal_secure_element_default', 'hal_drm_widevine']:
    missing = can(d, 'mitee_client_device', 'chr_file', {'open', 'read', 'write', 'ioctl'})
    report(not missing, '%s %s' % (d, ('missing ' + ' '.join(sorted(missing))) if missing else ''))
for t, c, perms in [('mitee_sfs_file', 'dir', {'search', 'add_name', 'write', 'create'}),
                    ('mitee_sfs_file', 'file', {'open', 'read', 'write', 'create'}),
                    ('mitee_data_file', 'dir', {'search', 'add_name', 'write'}),
                    ('ufs_bsg_device', 'chr_file', {'open', 'read', 'write', 'ioctl'})]:
    missing = can('tee', t, c, perms)
    report(not missing, 'tee %s:%s %s' % (t, c, ('missing ' + ' '.join(sorted(missing))) if missing else ''))

print('== relabel of /mnt/vendor/persist/data by vendor_init')
for old in ['mnt_vendor_file', 'persist_data_file', 'vendor_persist_type']:
    if not any(k[1] == old for k in allow):
        continue
    for c in ('dir', 'file'):
        m1 = can('vendor_init', old, c, {'relabelfrom'})
        m2 = can('vendor_init', 'mitee_sfs_file', c, {'relabelto'})
        report(not (m1 or m2), 'vendor_init %s -> mitee_sfs_file (%s) %s' % (old, c, ' '.join(sorted(m1 | m2))))
    for c in ('dir', 'file'):
        m = can('tee', old, c, {'open', 'read', 'write', 'search'} if c == 'dir' else {'open', 'read', 'write'})
        report(not m, 'tee still reaches old label %s:%s %s' % (old, c, ' '.join(sorted(m))))

print('== ADPF: power HAL may set app thread clamps')
for d in ['untrusted_app', 'platform_app', 'priv_app', 'system_app']:
    m = can('hal_power_default', d, 'process', {'setsched'})
    report(not m, 'hal_power_default %s:process setsched' % d)
m = can('hal_power_default', 'hal_power_default', 'capability', {'sys_nice'})
report(not m, 'hal_power_default self:capability sys_nice')

print('\n%d problem(s)' % bad)

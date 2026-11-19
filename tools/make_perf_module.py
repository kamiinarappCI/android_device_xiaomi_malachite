#!/usr/bin/env python3
"""Build the malachite performance KernelSU module.

The module's /vendor/etc/powerhint.json is derived from the released build's
file (device tree commit RELEASE) with two changes carried over from
lineage-23.2:

  * uclamp.min boosts above 12.5% are written as 12.5, the value they ran at
    under the release's sched_util_clamp_min=128. The module lifts that
    ceiling, so without this they would suddenly take effect.
  * the AdpfConfig section is copied from lineage-23.2.

customize.sh installs the file only if the phone's powerhint.json hashes to
the release's, so it never replaces a different build's table.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
WORKSPACE = os.path.dirname(HERE)
DEVICE = os.path.join(WORKSPACE, 'src', 'device_xiaomi_malachite')
MODULE = os.path.join(WORKSPACE, 'ksu-module', 'malachite-performance')
RELEASE = 'a3c7b5b'
BRANCH = 'origin/lineage-23.2'
HINT = 'configs/powerhint.json'
OUT = os.path.join(MODULE, 'system', 'vendor', 'etc', 'powerhint.json')
GROUP_BOOST_LIMIT = 12.5
UCLAMP_NODES = ('UclampFGMin', 'UclampTAMin')
TEXT_EXT = {'.sh', '.prop', '.rule', '.json', '.md'}
RESERVED = {'NUL', 'CON', 'PRN', 'AUX'}


def git_show(rev, path):
    return subprocess.run(['git', '-C', DEVICE, 'show', f'{rev}:{path}'],
                          capture_output=True, check=True).stdout


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def cap(value):
    return '12.5' if float(value) > GROUP_BOOST_LIMIT else value


def derive(release, branch):
    table = json.loads(release)
    if 'AdpfConfig' in table:
        sys.exit('release table already has an AdpfConfig')
    for node in table['Nodes']:
        if node['Name'] in UCLAMP_NODES:
            values = []
            for v in node['Values']:
                if cap(v) not in values:
                    values.append(cap(v))
            node['Values'] = values
            if node.get('DefaultIndex', 0) >= len(values):
                sys.exit(f"{node['Name']}: DefaultIndex out of range after capping")
    for action in table['Actions']:
        if action.get('Node') in UCLAMP_NODES:
            action['Value'] = cap(action['Value'])
    table['AdpfConfig'] = json.loads(branch)['AdpfConfig']
    return table


def check(table):
    """Reuse the device tree's own contract for the table."""
    sys.path.insert(0, DEVICE)
    from tests import test_powerhint as t  # noqa: E402

    declared = {n['Name']: n for n in table['Nodes']}
    for action in table['Actions']:
        if 'Node' in action:
            assert action['Value'] in declared[action['Node']]['Values'], action
    for name in UCLAMP_NODES:
        for v in declared[name]['Values']:
            assert float(v) <= t.GROUP_BOOST_LIMIT, (name, v)
    profiles = table['AdpfConfig']
    assert profiles
    for p in profiles:
        for key, kind in t.ADPF_REQUIRED.items():
            assert key in p, key
            v = p[key]
            if kind is bool:
                assert isinstance(v, bool), key
            else:
                assert isinstance(v, (int, float)) and not isinstance(v, bool), key
                if kind is int:
                    assert isinstance(v, int), key
                if key in t.ADPF_UNSIGNED:
                    assert v >= 0, key
        assert 'HeuristicBoost_On' not in p
        assert ('UclampMax_EfficientBase' in p) == ('UclampMax_EfficientOffset' in p)


def lf(path):
    data = open(path, 'rb').read()
    return data.replace(b'\r\n', b'\n') if os.path.splitext(path)[1] in TEXT_EXT else data


def version():
    for line in lf(os.path.join(MODULE, 'module.prop')).decode().splitlines():
        if line.startswith('version='):
            return line.split('=', 1)[1]
    sys.exit('module.prop has no version')


def pack(dest):
    with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(MODULE):
            dirs.sort()
            for name in sorted(files):
                if name in RESERVED:
                    continue
                full = os.path.join(root, name)
                rel = os.path.relpath(full, MODULE).replace(os.sep, '/')
                info = zipfile.ZipInfo(rel, date_time=(2026, 1, 1, 0, 0, 0))
                info.external_attr = (0o755 if name.endswith('.sh') else 0o644) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                z.writestr(info, lf(full))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--release', default=RELEASE)
    ap.add_argument('--branch', default=BRANCH)
    args = ap.parse_args()

    release = git_show(args.release, HINT).replace(b'\r\n', b'\n')
    table = derive(release, git_show(args.branch, HINT))
    check(table)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    body = (json.dumps(table, indent=2) + '\n').encode()
    open(OUT, 'wb').write(body)

    customize = lf(os.path.join(MODULE, 'customize.sh')).decode()
    for label, digest in (('RELEASE_SHA', sha256(release)), ('MODULE_SHA', sha256(body))):
        if f'{label}={digest}' not in customize:
            sys.exit(f'customize.sh: set {label}={digest}')

    dest = os.path.join(WORKSPACE, 'ksu-module', f'malachite-performance-v{version()}.zip')
    pack(dest)
    print(f'release powerhint {sha256(release)}')
    print(f'module  powerhint {sha256(body)}')
    print(f'wrote {dest}')


if __name__ == '__main__':
    main()

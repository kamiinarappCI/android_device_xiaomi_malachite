#!/usr/bin/env python3
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
"""Prepare a separate repo checkout from the local crDroid support branches."""
import argparse
import hashlib
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import xml.etree.ElementTree as ET


def run(*args, cwd=None, capture=False, env=None):
    result = subprocess.run(args, cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None, env=env)
    return result.stdout.strip() if capture else None


def reference_tips(checkout):
    project_list = checkout / '.repo/project.list'
    if not project_list.exists():
        return {}
    tips = {}
    for path in project_list.read_text().splitlines():
        gitdir = checkout / '.repo/projects' / (path + '.git')
        if not (gitdir / 'HEAD').exists():
            continue
        head = (gitdir / 'HEAD').read_text().strip()
        if head.startswith('ref: '):
            result = subprocess.run(['git', '--git-dir=' + str(gitdir), 'rev-parse', 'HEAD'],
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            head = result.stdout.strip() if result.returncode == 0 else ''
        if not re.fullmatch('[0-9a-f]{40}', head):
            heads = run('git', '--git-dir=' + str(gitdir), 'for-each-ref',
                        '--format=%(objectname)', 'refs/remotes', capture=True).splitlines()
        else:
            heads = [head]
        if heads:
            objects = (gitdir / 'objects').resolve()
            tips[str(objects.parent)] = list(dict.fromkeys(heads))
    return tips


def lfs_pointers(source, revision):
    attributes = subprocess.run(
        ['git', '-C', str(source), 'grep', '-l', '-F', 'filter=lfs', revision,
         '--', '.gitattributes', ':(glob)**/.gitattributes'],
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if attributes.returncode == 1:
        return
    if attributes.returncode:
        raise RuntimeError(attributes.stderr.decode())
    entries = subprocess.check_output(
        ['git', '-C', str(source), 'ls-tree', '-rlz', revision]).split(b'\0')
    candidates = []
    for entry in entries:
        if not entry:
            continue
        metadata, name = entry.split(b'\t', 1)
        mode, kind, oid, size = metadata.split()
        if kind == b'blob' and int(size) <= 1024:
            candidates.append((oid.decode(), name.decode()))
    batch = subprocess.Popen(['git', '-C', str(source), 'cat-file', '--batch'],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    try:
        for oid, name in candidates:
            batch.stdin.write((oid + '\n').encode())
            batch.stdin.flush()
            header = batch.stdout.readline().split()
            data = batch.stdout.read(int(header[2]))
            batch.stdout.read(1)
            if data.startswith(b'version https://git-lfs.github.com/spec/v1\n'):
                match = re.search(rb'^oid sha256:([0-9a-f]{64})$', data, re.M)
                if not match:
                    raise RuntimeError(f'Malformed LFS pointer: {name}')
                yield match[1].decode(), name
    finally:
        batch.stdin.close()
        batch.wait()


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--ports', type=pathlib.Path,
                    default=pathlib.Path.home() / 'android/crdroid-17.0')
parser.add_argument('--top', type=pathlib.Path,
                    default=pathlib.Path.home() / 'android/crdroid-17.0-build')
parser.add_argument('--reference', type=pathlib.Path,
                    default=pathlib.Path('/mnt/wsl/malachite-build/lineage-24'))
parser.add_argument('--sync', action='store_true', help='Download and check out sources; never compile')
parser.add_argument('--projects', nargs='+', help='Limit the source sync to named repo project paths')
args = parser.parse_args()
ports, top, reference = [path.resolve() for path in (args.ports, args.top, args.reference)]
if top in (ports, reference) or top in ports.parents or top in reference.parents:
    raise SystemExit('The destination must be a separate checkout')
if ports in top.parents or reference in top.parents:
    raise SystemExit('The destination cannot be inside an input checkout')
branch = 'crdroid-17.0'
state = pathlib.Path.home() / 'android/crdroid-17.0-state'
mirrors = state / 'local-remotes'
mirrors.mkdir(parents=True, exist_ok=True)
manifest = ET.parse(ports / 'device/xiaomi/malachite/manifests/crdroid.xml')
root = manifest.getroot()
remote = root.find('remote')
remote.set('name', 'malachite-local')
remote.set('fetch', mirrors.as_uri() + '/')
for project in root.findall('project'):
    path, name = project.get('path'), project.get('name')
    source = ports / path
    if run('git', '-C', str(source), 'status', '--porcelain', capture=True):
        raise SystemExit(f'Dirty source checkout: {source}')
    head = run('git', '-C', str(source), 'rev-parse', branch, capture=True)
    mirror = mirrors / (name + '.git')
    if not mirror.exists():
        run('git', 'clone', '--bare', '--shared', '--single-branch', '--branch', branch,
            str(source), str(mirror))
    else:
        run('git', '--git-dir=' + str(mirror), 'fetch', str(source),
            f'{branch}:refs/heads/{branch}')
    mirror_head = run('git', '--git-dir=' + str(mirror), 'rev-parse', branch, capture=True)
    if mirror_head != head:
        raise SystemExit(f'Mirror revision mismatch: {path}')
    alias = mirrors / name
    if not alias.exists():
        alias.symlink_to(mirror.name, target_is_directory=True)
    elif alias.resolve() != mirror.resolve():
        raise SystemExit(f'Unexpected local remote path: {alias}')
    # Reuse the exact LFS objects in the reference checkout, without changing
    # its repository, cache, refs or worktree.
    index = state / 'lfs-index' / (name + '-' + head + '.json')
    if index.exists():
        pointers = json.loads(index.read_text())
    else:
        pointers = list(lfs_pointers(source, head))
        index.parent.mkdir(parents=True, exist_ok=True)
        index.write_text(json.dumps(pointers))
    for oid, name_in_tree in pointers:
        cached = mirror / 'lfs/objects' / oid[:2] / oid[2:4] / oid
        if cached.exists():
            continue
        original = reference / path / name_in_tree
        with original.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        if digest != oid:
            raise SystemExit(f'Reference LFS object mismatch: {path}/{name_in_tree}')
        cached.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, cached)
    project.set('remote', 'malachite-local')
    project.set('revision', branch)
top.mkdir(parents=True, exist_ok=True)
if not (top / '.repo').exists():
    run('repo', 'init', '-u', 'https://github.com/crdroidandroid/android.git', '-b', '17.0',
        '--git-lfs', '--no-clone-bundle', '--reference=' + str(reference), cwd=top)
local = top / '.repo/local_manifests'
local.mkdir(exist_ok=True)
ET.indent(root, space='  ')
manifest.write(local / 'malachite.xml', encoding='utf-8', xml_declaration=True)
print('Source destination:', top, flush=True)
print('Local support branches:', mirrors, flush=True)
if args.sync:
    resolved = ET.fromstring(run('repo', 'manifest', cwd=top, capture=True))
    for project in resolved.findall('project'):
        path = project.get('path', project.get('name'))
        source = next((checkout / path for checkout in (ports, reference)
                       if (checkout / path / '.git').exists()), None)
        store = top / '.repo/project-objects' / (project.get('name') + '.git')
        if source is None or store.exists():
            continue
        run('git', 'init', '--bare', '-q', str(store))
        common = run('git', '-C', str(source), 'rev-parse', '--git-common-dir', capture=True)
        objects = (source / common / 'objects').resolve()
        (store / 'objects/info/alternates').write_text(str(objects) + '\n')
    tips = reference_tips(reference)
    tips.update(reference_tips(ports))
    (state / 'alternate-tips.json').write_text(json.dumps(tips))
    helper = state / 'alternate_tips.py'
    helper.write_text('import json, pathlib, sys\n'
                      'tips = json.loads(pathlib.Path(__file__).with_name("alternate-tips.json").read_text())\n'
                      'heads = tips.get(str(pathlib.Path(sys.argv[1]).resolve()), [])\n'
                      'if heads: print("\\n".join(heads))\n')
    environment = os.environ.copy()
    count = int(environment.get('GIT_CONFIG_COUNT', '0'))
    environment['GIT_CONFIG_COUNT'] = str(count + 1)
    environment[f'GIT_CONFIG_KEY_{count}'] = 'core.alternateRefsCommand'
    environment[f'GIT_CONFIG_VALUE_{count}'] = 'python3 ' + shlex.quote(str(helper))
    run('repo', 'sync', '-c', '-j4', '--retry-fetches=3', '--no-tags', '--no-clone-bundle',
        *(args.projects or []),
        cwd=top, env=environment)
    for project in root.findall('project'):
        path = project.get('path')
        if args.projects and path not in args.projects:
            continue
        checkout = top / path
        current = run('git', '-C', str(checkout), 'branch', '--show-current', capture=True)
        if current and current != branch:
            raise SystemExit(f'Preserving another checked-out branch: {checkout}: {current}')
        run('git', '-C', str(checkout), 'config', 'user.name', 'Noam')
        run('git', '-C', str(checkout), 'config', 'user.email', 'noamtu123@users.noreply.github.com')
        if not current:
            run('git', '-C', str(checkout), 'switch', '-c', branch,
                '--track', 'malachite-local/' + branch)
print('Source preparation finished. No compilation was run.', flush=True)

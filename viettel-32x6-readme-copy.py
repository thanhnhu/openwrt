#!/usr/bin/env python3
"""Copy README-viettel-32x6.md (canonical, in the repo) to the device folder
as README-32x6.md, rewriting relative links so they still resolve there.

usage: python viettel-32x6-readme-copy.py [device_dir]
default device_dir: ../../../Softwares/Why/OpenWRT/vAP-32X6V1 (netis-NX31)
"""
import os
import re
import sys

repo = os.path.dirname(os.path.abspath(__file__))
dev = os.path.normpath(os.path.join(
    repo, sys.argv[1] if len(sys.argv) > 1 else
    '../../../Softwares/Why/OpenWRT/vAP-32X6V1 (netis-NX31)'))
src = os.path.join(repo, 'README-viettel-32x6.md')
dst = os.path.join(dev, 'README-32x6.md')

text = open(src, encoding='utf-8').read()


def fix(target):
    if re.match(r'^[a-z]+:|^#|^/', target):          # URL, anchor, absolute
        return target
    path, sep, frag = target.partition('#')
    trail = '/' if path.endswith('/') else ''
    absolute = os.path.normpath(os.path.join(repo, path))
    rel = os.path.relpath(absolute, dev).replace(os.sep, '/')
    return rel + trail + sep + frag


def sub(m):
    # links into the repo become plain workspace names ("OpenWRT/<path>"):
    # no machine-specific relative paths in the device-folder copy
    label, angle, plain = m.group(1), m.group(2), m.group(3)
    target = angle if angle is not None else plain
    if re.match(r'^[a-z]+:|^#|^/', target):          # URL, anchor, absolute
        return m.group(0)
    path = target.partition('#')[0].rstrip('/')
    return '`OpenWRT/%s`' % path


out = re.sub(r'\[([^\]]*)\]\((?:<([^>]+)>|([^)\s]+))\)', sub, text)
note = ('<!-- Generated from OpenWRT/README-viettel-32x6.md (workspace folder OpenWRT) '
        'by viettel-32x6-readme-copy.py - edit the repo copy, not this file. -->\n')
open(dst, 'w', encoding='utf-8', newline='\n').write(note + out)
print('written', dst.encode('ascii', 'replace').decode())

#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# Usage: Scripts/ci-change-scope.py BASE HEAD
# Prints documentation only when every changed path is a documentation file.

import subprocess
import sys


def is_documentation(path):
    if b"\n" in path or b"\r" in path:
        return False
    return path in {b'README.md', b'AGENTS.md', b'TASKS.md'} or (
        path.startswith(b'Documentation/') and path.endswith((b'.md', b'.bib'))
    )


def main():
    if len(sys.argv) != 3:
        raise SystemExit('Usage: Scripts/ci-change-scope.py BASE HEAD')
    paths = subprocess.check_output([
        'git', 'diff', '--name-only', '--no-renames', '-z', sys.argv[1], sys.argv[2]
    ]).split(b'\0')
    paths = [path for path in paths if path]
    print('documentation' if paths and all(map(is_documentation, paths)) else 'code')


if __name__ == '__main__':
    main()

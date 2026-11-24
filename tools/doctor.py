#!/usr/bin/env python3
"""Report which toolchain pieces are present. Exit 0 when Go and Python exist."""

import shutil
import sys

checks = {
    "python3": shutil.which("python3"),
    "go": shutil.which("go"),
    "flutter": shutil.which("flutter"),
    "dart": shutil.which("dart"),
    "node": shutil.which("node"),
    "google-chrome": shutil.which("google-chrome"),
}
pg = shutil.which("postgres") or shutil.which("pg_ctl")
print("doctor")
for name, path in checks.items():
    print(f"  {name}: {path or 'missing'}")
print(f"  postgres: {pg or 'missing'}")
missing = [name for name in ("python3", "go") if not checks[name]]
if missing:
    print("T00 requires", ", ".join(missing))
    sys.exit(1)
print("T00 toolchain ok")

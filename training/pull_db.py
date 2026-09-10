"""
Pulls smartspend.db off the device without going through any shell pipe or
redirect. PowerShell's `|` and `>` can pass native-process output through a
text-processing layer even between two binaries, which silently corrupts
binary data (SQLite page bytes) while leaving the plain-ASCII header intact --
which is exactly the "header looks fine, integrity_check fails" symptom.

This calls adb directly via subprocess and writes subprocess.stdout (raw
bytes) to disk, with no shell in between.

Usage:
    python pull_db.py --package com.example.smartspend --out smartspend_debug.db
"""

import argparse
import subprocess
import sqlite3
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--package", required=True)
parser.add_argument("--out", default="smartspend_debug.db")
args = parser.parse_args()

print("Force-stopping app...")
subprocess.run(["adb", "shell", "am", "force-stop", args.package], check=True)

print("Pulling database via adb subprocess (no shell pipe)...")
result = subprocess.run(
    ["adb", "exec-out", "run-as", args.package, "cat", "databases/smartspend.db"],
    capture_output=True,
)

if result.returncode != 0:
    print("adb command failed:", result.stderr.decode(errors="replace"), file=sys.stderr)
    sys.exit(1)

data = result.stdout

if not data.startswith(b"SQLite format 3"):
    print(
        f"Pulled data doesn't start with the SQLite header. First 30 bytes: {data[:30]!r}",
        file=sys.stderr,
    )
    sys.exit(1)

with open(args.out, "wb") as f:
    f.write(data)

print(f"Wrote {len(data)} bytes to {args.out}")

conn = sqlite3.connect(args.out)
check = conn.execute("PRAGMA integrity_check;").fetchone()
conn.close()

if check[0] == "ok":
    print("integrity_check: ok -- database is sound.")
else:
    print(f"integrity_check FAILED: {check[0]}", file=sys.stderr)
    sys.exit(1)

#!/usr/bin/env python3
"""Execute a fixed, read-only VM diagnostic over SSH."""

import argparse
import re
import shlex
import subprocess
import sys


def host(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]*", value, flags=re.ASCII):
        raise argparse.ArgumentTypeError("host must be a DNS hostname or IPv4 address")
    return value


def user(value):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.-]*", value, flags=re.ASCII):
        raise argparse.ArgumentTypeError("user must be a plain SSH username")
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True, type=host)
    parser.add_argument("--user", required=True, type=user)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)
    command = [
        "ssh",
        "-T",
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=yes",
        "-o", "ConnectTimeout=10",
        "--",
        f"{args.user}@{args.host}",
        "uname -s && hostname",
    ]
    if args.dry_run:
        print("DRY RUN (no connection): " + shlex.join(command))
        return 0
    try:
        result = subprocess.run(command, timeout=20, check=False)
    except subprocess.TimeoutExpired:
        print("VM diagnostic timed out after 20 seconds.", file=sys.stderr)
        return 124
    except FileNotFoundError:
        print("SSH executable not found; install OpenSSH first.", file=sys.stderr)
        return 127
    return result.returncode if result.returncode >= 0 else 128 - result.returncode


if __name__ == "__main__":
    sys.exit(main())

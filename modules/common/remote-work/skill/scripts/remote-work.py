#!/usr/bin/env python3
"""Explicit, argv-based local orchestration for disposable SSH build workspaces."""

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import subprocess
import sys
import time


EXCLUDED = {
    ".git", ".env", ".highstate", ".ssh", ".aws", ".kube", ".terraform",
    "node_modules", ".venv", "venv", "__pycache__", "target", "dist", "build",
    ".output", ".nuxt", ".next", ".artifacts", "secrets", "credentials",
}
MARKER = ".remote-work-artifacts"


def host(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.@-]*", value):
        raise ValueError("Use a configured SSH alias, not SSH options or a URL")
    return value


def remote_path(value):
    path = PurePosixPath(value)
    if not value.startswith("/") or ".." in path.parts or len(path.parts) < 4:
        raise ValueError("Use a dedicated absolute workspace below /home/USER/...")
    if path.parts[1] != "home" or any(c in value for c in "\n\r\0"):
        raise ValueError("Remote workspace must be below /home/USER")
    return str(path)


def control_path(alias):
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ValueError("XDG_RUNTIME_DIR is required for private SSH sockets")
    directory = Path(runtime) / "remote-work"
    directory.mkdir(mode=0o700, exist_ok=True)
    if directory.is_symlink() or directory.stat().st_uid != os.getuid():
        raise ValueError("Unsafe control socket directory")
    directory.chmod(0o700)
    return str(directory / hashlib.sha256(alias.encode()).hexdigest()[:20])


def ssh_args(alias):
    return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
            "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=3",
            "-o", "ControlMaster=auto", "-o", "ControlPersist=600",
            "-S", control_path(alias)]


def remote_command(alias, argv, **kwargs):
    return subprocess.run(ssh_args(alias) + [alias, shlex.join(argv)], **kwargs)


def allowed_file(value):
    parts = PurePosixPath(value).parts
    return not any(
        part in EXCLUDED or part.startswith(".env.")
        or part.endswith((".pem", ".key", ".p12", ".pfx", ".db", ".sqlite", ".sqlite3"))
        for part in parts
    )


def tracked_files(source):
    root = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "--show-toplevel"], text=True
    ).strip()
    if Path(root).resolve() != source:
        raise ValueError("sync source must be the Git repository root")
    entries = subprocess.check_output(["git", "-C", str(source), "ls-files", "--stage", "-z"])
    files = []
    for entry in entries.split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, _, stage = metadata.split()
        path = os.fsdecode(name)
        if stage != b"0":
            raise ValueError("Resolve Git conflicts before synchronizing")
        if not allowed_file(path):
            continue
        local = source / path
        if mode == b"160000":
            raise ValueError("Submodules need a separately reviewed sync")
        if local.is_symlink() or any(parent.is_symlink() for parent in local.parents if parent != source):
            raise ValueError(f"Refusing symlink source: {path}")
        if local.is_file():
            files.append(name)
    return b"\0".join(files) + b"\0"


def artifact_directory(value, initialize, delete):
    original = Path(value).expanduser().absolute()
    if any(part.is_symlink() for part in [original, *original.parents]):
        raise ValueError("Artifact destination cannot contain symlinks")
    destination = original.resolve()
    if destination in {Path.home(), Path("/"), Path.cwd().resolve()}:
        raise ValueError("Choose a dedicated artifact directory")
    if destination.exists() and not destination.is_dir():
        raise ValueError("Artifact destination is not a directory")
    if initialize:
        destination.mkdir(parents=True, exist_ok=True)
        if any(destination.iterdir()):
            raise ValueError("--init requires an empty artifact directory")
        (destination / MARKER).write_text("remote-work scratch artifacts\n")
    if delete and not (destination / MARKER).is_file():
        raise ValueError("--delete requires a scratch directory initialized with --init")
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def forward(value):
    if not re.fullmatch(r"[0-9]+:[0-9]+", value):
        raise ValueError("Forward must be LOCAL_PORT:REMOTE_PORT")
    local, remote = map(int, value.split(":"))
    if not all(1 <= port <= 65535 for port in (local, remote)):
        raise ValueError("Port outside 1..65535")
    return f"127.0.0.1:{local}:127.0.0.1:{remote}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    for name in ["ssh", "doctor", "close", "tunnel"]:
        command = commands.add_parser(name)
        command.add_argument("host", type=host)
        if name == "tunnel":
            command.add_argument("--forward", action="append", required=True, type=forward)
    sync = commands.add_parser("sync", help="Upload tracked source, without deletion")
    sync.add_argument("host", type=host)
    sync.add_argument("source", type=Path)
    sync.add_argument("workspace", type=remote_path)
    sync.add_argument("--dry-run", action="store_true")
    run = commands.add_parser("run", help="Execute argv in an existing remote workspace")
    run.add_argument("host", type=host)
    run.add_argument("workspace", type=remote_path)
    run.add_argument("command", nargs=argparse.REMAINDER)
    pull = commands.add_parser("pull", help="Pull checksum-selected artifact deltas")
    pull.add_argument("host", type=host)
    pull.add_argument("remote", type=remote_path)
    pull.add_argument("destination")
    pull.add_argument("--init", action="store_true")
    pull.add_argument("--delete", action="store_true")
    pull.add_argument("--dry-run", action="store_true")
    vm = commands.add_parser("vm", help="Use an already authorized local yc CLI")
    vm.add_argument("operation", choices=["status", "start", "stop"])
    vm.add_argument("--id", required=True)
    vm.add_argument("--folder-id")
    args = parser.parse_args()
    start = time.monotonic()

    if args.action == "vm":
        argv = ["yc", "compute", "instance", "get" if args.operation == "status" else args.operation,
                "--id", args.id, "--format", "json"]
        if args.folder_id:
            argv += ["--folder-id", args.folder_id]
        result = subprocess.run(argv)
    elif args.action in {"ssh", "tunnel"}:
        argv = ssh_args(args.host)
        # Forward operations on our master are explicit, not silently ignored by multiplexing.
        if args.action == "tunnel":
            check = subprocess.run(argv + ["-O", "check", args.host], capture_output=True)
            if check.returncode == 0:
                argv += ["-O", "forward"]
            else:
                argv += ["-fNT"]
            argv += ["-o", "ExitOnForwardFailure=yes"]
            for item in args.forward:
                argv += ["-L", item]
        else:
            argv += ["-fNT"]
        result = subprocess.run(argv + [args.host])
    elif args.action == "close":
        result = subprocess.run(ssh_args(args.host) + ["-O", "exit", args.host])
    elif args.action == "doctor":
        # Fixed argv, no shell program or remote provisioning.
        result = remote_command(args.host, ["uname", "-a"])
        if result.returncode == 0:
            result = remote_command(args.host, ["df", "-h", "."])
        if result.returncode == 0:
            result = remote_command(args.host, ["rsync", "--version"])
    elif args.action == "sync":
        source = args.source.expanduser().resolve()
        files = tracked_files(source)
        if not files.strip(b"\0"):
            raise ValueError("No eligible tracked files")
        if not args.dry_run:
            remote_command(args.host, ["mkdir", "-p", "--", args.workspace], check=True)
        argv = ["rsync", "-azs", "--from0", "--files-from=-", "--stats",
                "-e", shlex.join(ssh_args(args.host))]
        if args.dry_run:
            argv += ["--dry-run", "--itemize-changes"]
        result = subprocess.run(argv + [str(source) + "/",
                                       f"{args.host}:{args.workspace}/"], input=files)
    elif args.action == "run":
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not command:
            raise ValueError("A command is required after --")
        result = remote_command(args.host, ["env", "--chdir=" + args.workspace, "--", *command])
    else:
        if args.dry_run and args.init:
            raise ValueError("--dry-run cannot initialize a directory")
        destination = artifact_directory(args.destination, args.init, args.delete)
        argv = ["rsync", "-azcs", "--stats", "--exclude=/" + MARKER,
                "-e", shlex.join(ssh_args(args.host))]
        if args.delete:
            argv += ["--delete"]
        if args.dry_run:
            argv += ["--dry-run", "--itemize-changes"]
        result = subprocess.run(argv + [f"{args.host}:{args.remote}/", str(destination) + "/"])
    print(json.dumps({"action": args.action, "wallSeconds": round(time.monotonic() - start, 3),
                      "exitCode": result.returncode}), file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"remote-work: {error}", file=sys.stderr)
        sys.exit(1)

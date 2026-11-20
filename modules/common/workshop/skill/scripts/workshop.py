#!/usr/bin/env python3
"""Explicit, argv-based local orchestration for disposable SSH build workspaces."""

import argparse
import contextlib
import hashlib
import fcntl
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import signal
import subprocess
import sys
import threading
import time
import tempfile
import uuid


EXCLUDED = {
    ".git",
    ".env",
    ".highstate",
    ".ssh",
    ".aws",
    ".kube",
    ".terraform",
    "node_modules",
    ".venv",
    "venv",
    "__pycache__",
    "target",
    "dist",
    "build",
    ".output",
    ".nuxt",
    ".next",
    ".artifacts",
    "secrets",
    "credentials",
}
MARKER = ".workshop-artifacts"
SSH_HOST = "workshop"
CONNECTION = {}


def configuration():
    path = Path(
        os.environ.get("WORKSHOP_CONFIG", Path.home() / ".config/workshop/config.json")
    )
    if not path.exists():
        return {}
    config = json.loads(path.read_text())
    if not isinstance(config, dict) or not all(
        isinstance(config.get(key), str) and config[key]
        for key in ("functionId", "organizationId", "login")
    ):
        raise ValueError(
            "Expected one Workshop controller with functionId, organizationId and login"
        )
    return config


def invoke_controller(config, payload, retryable=False):
    function_id = config["functionId"]
    try:
        result = subprocess.run(
            [
                "yc",
                "serverless",
                "function",
                "invoke",
                "--id",
                function_id,
                "--data-stdin",
            ],
            input=json.dumps({"body": json.dumps(payload)}),
            capture_output=True,
            text=True,
            timeout=200,
        )
    except subprocess.TimeoutExpired:
        if retryable:
            return {"status": "pending", "phase": "connection-retry", "retryAfter": 10}
        raise ValueError("Workshop controller invocation timed out") from None
    if result.returncode:
        if retryable and re.search(
            r"code = (Unavailable|DeadlineExceeded|ResourceExhausted)\b", result.stderr
        ):
            return {"status": "pending", "phase": "connection-retry", "retryAfter": 10}
        raise ValueError(
            "yc function invocation failed; check your personal YC profile and connectivity"
        )
    try:
        response = json.loads(result.stdout)
        status = response["statusCode"]
        if status in {409, 429}:
            return {"status": "busy", "retryAfter": 5}
        if retryable and status in {500, 502, 503, 504}:
            return {"status": "pending", "phase": "controller-retry", "retryAfter": 10}
        body = json.loads(response["body"])
        if isinstance(body, dict) and (
            status == 200 or (status == 400 and body.get("status") == "invalid")
        ):
            return body
    except (KeyError, ValueError, TypeError):
        raise ValueError("Invalid Workshop controller response") from None
    raise ValueError("Workshop controller rejected the request")


def establish(config, spec=None, timeout=1800):
    lease = uuid.uuid4().hex
    request = {
        "action": "prepare",
        "leaseId": lease,
        "spec": spec or {"cpu": 8, "memoryGiB": 32, "diskGiB": 93},
    }
    deadline = time.monotonic() + timeout
    previous = None
    while True:
        result = invoke_controller(config, request, retryable=True)
        if result.get("status") == "ready":
            break
        if result.get("status") not in {
            "pending",
            "busy",
            "bootstrapping",
            "unreachable",
        }:
            raise ValueError(
                "Controller did not produce a usable worker: "
                + str(result.get("error", result.get("status")))
            )
        if time.monotonic() >= deadline:
            raise ValueError("Timed out waiting for Workshop; no task was replayed")
        progress = (result["status"], result.get("phase"))
        if progress != previous:
            print(
                "workshop: " + " ".join(part for part in progress if part),
                file=sys.stderr,
            )
            previous = progress
        time.sleep(min(max(int(result.get("retryAfter", 5)), 1), 30))
    ipaddress.IPv4Address(result["ipv4"])
    generation = result["generation"]
    if not re.fullmatch(r"[a-f0-9]{32}", generation):
        raise ValueError("Invalid generation from controller")
    cache = Path(control_path() + ".json")
    lock = Path(control_path() + ".lock")
    with lock.open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        existing = json.loads(cache.read_text()) if cache.exists() else None
        if (
            existing
            and existing["result"]["generation"] == generation
            and existing["result"]["ipv4"] == result["ipv4"]
        ):
            CONNECTION.update(existing)
            if (
                subprocess.run(
                    ssh_args() + ["-O", "check", SSH_HOST], capture_output=True
                ).returncode
                == 0
            ):
                try:
                    health = guest_control({"action": "health"})
                except (ValueError, OSError, subprocess.SubprocessError):
                    health = {}
                if health.get("ready") and health.get("generation") == generation:
                    existing["lease"] = lease
                    existing["result"] = result
                    temporary = cache.with_suffix(".new")
                    temporary.write_text(json.dumps(existing))
                    temporary.chmod(0o600)
                    temporary.replace(cache)
                    start_keeper()
                    return result
        install_transport(config, result, lease, cache)
    start_keeper()
    return result


def install_transport(config, result, lease, cache):
    from direct_ssh import options

    address = str(ipaddress.IPv4Address(result["ipv4"]))
    generation = result["generation"]
    public = result["hostKey"].split()
    if (
        not re.fullmatch(r"[a-f0-9]{32}", generation)
        or len(public) < 2
        or public[0] != "ssh-ed25519"
        or not re.fullmatch(r"[A-Za-z0-9+/=]+", public[1])
    ):
        raise ValueError("Invalid host identity from controller")
    directory = Path(control_path() + ".identity")
    directory.mkdir(mode=0o700, exist_ok=True)
    key = str(directory / "identity")
    login = config["login"]
    if not re.fullmatch(r"[a-zA-Z0-9_][a-zA-Z0-9_-]{0,31}", login):
        raise ValueError("Invalid OS Login name")
    export_certificate(config, directory)
    known = str(directory / "known_hosts")
    key_alias = SSH_HOST + "-" + generation
    Path(known).write_text(key_alias + " " + " ".join(public[:2]) + "\n")
    subprocess.run(ssh_args() + ["-O", "exit", SSH_HOST], capture_output=True)
    CONNECTION.update(
        {
            "lease": lease,
            "result": result,
            "options": [
                "-o",
                "HostName=" + address,
                "-o",
                "User=" + login,
                "-o",
                "IdentityFile=" + key,
                "-o",
                "CertificateFile=" + key + "-cert.pub",
                "-o",
                "IdentityAgent=none",
                "-o",
                "IdentitiesOnly=yes",
                "-o",
                "StrictHostKeyChecking=yes",
                "-o",
                "HostKeyAlias=" + key_alias,
                "-o",
                "UserKnownHostsFile=" + known,
                "-o",
                "GlobalKnownHostsFile=/dev/null",
            ],
        }
    )
    with tempfile.TemporaryFile() as errors:
        opened = subprocess.run(
            ssh_args(connect=True) + options(config, address, cache.parent) + ["-fNT", SSH_HOST],
            stdout=subprocess.DEVNULL, stderr=errors,
        )
        if opened.returncode:
            errors.seek(0)
            raise ValueError(
                "SSH transport connection failed: " + errors.read()[-500:].decode(errors="replace").strip()
            )
    try:
        probe = guest_control({"action": "health"})
        if not probe.get("ready") or probe.get("generation") != generation:
            raise ValueError("Local SSH readiness check failed")
    except BaseException:
        subprocess.run(ssh_args() + ["-O", "exit", SSH_HOST], capture_output=True)
        raise
    temporary = cache.with_suffix(".new")
    temporary.write_text(json.dumps(CONNECTION))
    temporary.chmod(0o600)
    temporary.replace(cache)


def export_certificate(config, directory):
    with tempfile.TemporaryDirectory(dir=directory) as staging:
        result = subprocess.run(
            [
                "yc",
                "compute",
                "ssh",
                "certificate",
                "export",
                "--directory",
                staging,
                "--organization-id",
                config["organizationId"],
                "--login",
                config["login"],
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode:
            raise ValueError(
                "yc OS Login certificate export failed; check your personal YC profile"
            )
        certificates = list(Path(staging).glob("*-cert.pub"))
        if len(certificates) != 1:
            raise ValueError("yc did not export exactly one OS Login certificate")
        certificate = certificates[0]
        identity = certificate.with_name(certificate.name.removesuffix("-cert.pub"))
        if not identity.is_file():
            raise ValueError("yc did not export the matching SSH identity")
        for source, name in (
            (identity, "identity"),
            (certificate, "identity-cert.pub"),
        ):
            source.chmod(0o600)
            source.replace(directory / name)


def start_keeper():
    Path(control_path() + ".stop").unlink(missing_ok=True)
    subprocess.Popen(
        [sys.executable, str(Path(__file__).with_name("transport.py"))],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def load_transport():
    cache = Path(control_path() + ".json")
    if not cache.exists():
        return False
    CONNECTION.update(json.loads(cache.read_text()))
    CONNECTION["lease"] = uuid.uuid4().hex
    return (
        subprocess.run(
            ssh_args() + ["-O", "check", SSH_HOST], capture_output=True
        ).returncode
        == 0
    )


def guest_control(request):
    result = remote_command(
        ["sudo", "-n", "/usr/local/lib/workshop/guest.py", "control"],
        input=json.dumps(request),
        text=True,
        capture_output=True,
        timeout=30,
    )
    if result.returncode:
        raise ValueError(
            "Guest control failed; reconnect through prepare, do not replay a task"
        )
    return json.loads(result.stdout)


@contextlib.contextmanager
def held_lease():
    connection = CONNECTION
    if not connection:
        yield
        return
    stopped = threading.Event()
    failures = []

    def heartbeat():
        while not stopped.wait(60):
            try:
                guest_control(
                    {"action": "lease", "id": connection["lease"], "seconds": 300},
                )
            except Exception:
                failures.append(True)
                return

    thread = threading.Thread(target=heartbeat, daemon=True)
    thread.start()
    try:
        yield
        if failures:
            raise ValueError(
                "Worker lease lost; task result requires inspection, not automatic replay"
            )
    finally:
        stopped.set()
        thread.join(timeout=35)
        try:
            guest_control({"action": "release", "id": connection["lease"]})
        except Exception:
            pass


def remote_path(value):
    path = PurePosixPath(value)
    if not value.startswith("/") or ".." in path.parts or len(path.parts) < 4:
        raise ValueError("Use a dedicated absolute workspace below /home/USER/...")
    if path.parts[1] != "home" or any(c in value for c in "\n\r\0"):
        raise ValueError("Remote workspace must be below /home/USER")
    return str(path)


def control_path():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime:
        raise ValueError("XDG_RUNTIME_DIR is required for private SSH sockets")
    directory = Path(runtime) / "workshop"
    directory.mkdir(mode=0o700, exist_ok=True)
    if directory.is_symlink() or directory.stat().st_uid != os.getuid():
        raise ValueError("Unsafe control socket directory")
    directory.chmod(0o700)
    return str(directory / hashlib.sha256(SSH_HOST.encode()).hexdigest()[:20])


def ssh_args(connect=False):
    return [
        "ssh",
        "-F",
        "/dev/null",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=15",
        "-o",
        "ServerAliveInterval=30",
        "-o",
        "ServerAliveCountMax=3",
        "-o",
        "ControlMaster=auto",
        "-o",
        "ControlPersist=yes",
        "-S",
        control_path(),
        *(["-o", "ProxyCommand=false"] if not connect else []),
        *CONNECTION.get("options", []),
    ]


def remote_command(argv, **kwargs):
    return subprocess.run(ssh_args() + [SSH_HOST, shlex.join(argv)], **kwargs)


def allowed_file(value):
    parts = PurePosixPath(value).parts
    return not any(
        part in EXCLUDED
        or part.startswith(".env.")
        or part.endswith((".pem", ".key", ".p12", ".pfx", ".db", ".sqlite", ".sqlite3"))
        for part in parts
    )


def tracked_files(source, ignore_files=()):
    root = subprocess.check_output(
        ["git", "-C", str(source), "rev-parse", "--show-toplevel"], text=True
    ).strip()
    if Path(root).resolve() != source:
        raise ValueError("sync source must be the Git repository root")
    entries = subprocess.check_output(
        ["git", "-C", str(source), "ls-files", "--stage", "-z"]
    )
    ignored_command = [
        "git",
        "-C",
        str(source),
        "ls-files",
        "--cached",
        "--ignored",
        "-z",
    ]
    ignored = set(
        subprocess.check_output(ignored_command + ["--exclude-standard"]).split(b"\0")
    )
    if ignore_files:
        extra = []
        for path in ignore_files:
            file = path.expanduser().resolve(strict=True)
            if not file.is_file():
                raise ValueError(f"Not an ignore file: {path}")
            extra.append(f"--exclude-from={file}")
        # Extra patterns may exclude more files, never override standard ignores.
        ignored.update(subprocess.check_output(ignored_command + extra).split(b"\0"))
    files = []
    for entry in entries.split(b"\0"):
        if not entry:
            continue
        metadata, name = entry.split(b"\t", 1)
        mode, _, stage = metadata.split()
        path = os.fsdecode(name)
        if stage != b"0":
            raise ValueError("Resolve Git conflicts before synchronizing")
        if name in ignored or not allowed_file(path):
            continue
        local = source / path
        if mode == b"160000":
            raise ValueError("Submodules need a separately reviewed sync")
        if local.is_symlink() or any(
            parent.is_symlink() for parent in local.parents if parent != source
        ):
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
        (destination / MARKER).write_text("workshop scratch artifacts\n")
    if delete and not (destination / MARKER).is_file():
        raise ValueError(
            "--delete requires a scratch directory initialized with --init"
        )
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def forward(value):
    if not re.fullmatch(r"[0-9]+:[0-9]+", value):
        raise ValueError("Forward must be LOCAL_PORT:REMOTE_PORT")
    local, remote = map(int, value.split(":"))
    if not all(1 <= port <= 65535 for port in (local, remote)):
        raise ValueError("Port outside 1..65535")
    return f"127.0.0.1:{local}:127.0.0.1:{remote}"


def estimated_spec(agent, requested=None, remember=False):
    root = (
        Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        / "workshop"
    )
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.is_symlink() or root.stat().st_uid != os.getuid():
        raise ValueError("Unsafe estimate directory")
    key = hashlib.sha256((SSH_HOST + "\0" + agent).encode()).hexdigest()
    path = root / (key + ".json")
    with (root / (key + ".lock")).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = (
            json.loads(path.read_text())
            if path.exists()
            else {"cpu": 8, "memoryGiB": 32, "diskGiB": 93}
        )
        result = {
            key: (requested or {}).get(key)
            if (requested or {}).get(key) is not None
            else value
            for key, value in previous.items()
        }
        if not all(
            isinstance(value, int) and not isinstance(value, bool) and value > 0
            for value in result.values()
        ):
            raise ValueError("Resource estimates must be positive integers")
        if remember:
            path.write_text(json.dumps(result))
            path.chmod(0o600)
        return result


def task_control(request):
    return remote_command(
        ["sudo", "-n", "/usr/local/lib/workshop/tasks.py", "control"],
        input=json.dumps(request),
        text=True,
        capture_output=True,
    )


def main():
    parser = argparse.ArgumentParser(prog="workshop", description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    android = commands.add_parser("android", help="Open a named Android worker")
    android.add_argument("mode", nargs="?", choices=["preview"], help="Open a desktop preview window")
    android.add_argument("name")
    android.add_argument("--port", type=int, default=15555)
    android.add_argument(
        "--screen",
        metavar="WIDTHxHEIGHT",
        help="Screen size at creation (default: 1080x2400)",
    )
    for name in ["ssh", "doctor", "close", "tunnel"]:
        command = commands.add_parser(name)
        if name == "tunnel":
            command.add_argument(
                "--forward", action="append", required=True, type=forward
            )
    sync = commands.add_parser("sync", help="Upload tracked source, without deletion")
    sync.add_argument("source", type=Path)
    sync.add_argument("workspace", type=remote_path)
    sync.add_argument("--dry-run", action="store_true")
    sync.add_argument(
        "--ignore-file",
        action="append",
        type=Path,
        default=[],
        help="Exclude additional files using a Git-style ignore file (repeatable)",
    )
    pull = commands.add_parser("pull", help="Pull checksum-selected artifact deltas")
    pull.add_argument("remote", type=remote_path)
    pull.add_argument("destination")
    pull.add_argument("--init", action="store_true")
    pull.add_argument("--delete", action="store_true")
    pull.add_argument("--dry-run", action="store_true")
    for name in ["prepare", "status", "notify", "ack"]:
        command = commands.add_parser(name)
        if name == "prepare":
            command.add_argument("--cpu", type=int)
            command.add_argument("--memory-gib", type=int)
            command.add_argument("--disk-gib", type=int)
            command.add_argument("--agent", required=True)
        if name == "notify":
            command.add_argument("--cursor", type=int, default=0)
        if name in {"notify", "ack"}:
            command.add_argument("--agent", required=True)
    tasks = commands.add_parser("task")
    task_commands = tasks.add_subparsers(dest="task_action", required=True)
    for name in ["create", "get", "wait", "cancel"]:
        command = task_commands.add_parser(name)
        if name == "create":
            command.add_argument("workspace", type=remote_path)
            command.add_argument("command", nargs=argparse.REMAINDER)
        else:
            command.add_argument("id")
    args = parser.parse_args()
    start = time.monotonic()

    config = configuration() if args.action != "close" else None
    if not config and args.action != "close":
        raise ValueError("Workshop controller is not configured")
    if args.action == "android":
        from android_session import session

        def stop(*_):
            raise KeyboardInterrupt

        signal.signal(signal.SIGTERM, stop)
        return session(
            config,
            args.name,
            args.port,
            invoke_controller,
            export_certificate,
            Path(control_path()).parent,
            screen=args.screen,
            viewer=args.mode == "preview",
        )
    if args.action == "status":
        print(json.dumps(invoke_controller(config, {"action": "status"})))
        return 0
    if args.action != "close":
        if args.action == "prepare":
            spec = estimated_spec(
                args.agent,
                {
                    "cpu": args.cpu,
                    "memoryGiB": args.memory_gib,
                    "diskGiB": args.disk_gib,
                },
            )
            ready = establish(config, spec)
            estimated_spec(args.agent, spec, remember=True)
            print(json.dumps(ready))
            guest_control({"action": "release", "id": CONNECTION["lease"]})
            return 0
        if not load_transport():
            raise ValueError(
                "Transport recovering or worker absent; run prepare with this agent's resource estimate"
            )
        if args.action in {"notify", "task", "ack"}:
            if args.action == "ack":
                print(
                    json.dumps(
                        guest_control(
                            {"action": "ack", "agent": args.agent},
                        )
                    )
                )
                return 0
            payload = (
                {"action": "notify", "cursor": args.cursor, "agent": args.agent}
                if args.action == "notify"
                else {"action": args.task_action}
            )
            if args.action == "task":
                if args.task_action == "create":
                    command = (
                        args.command[1:] if args.command[:1] == ["--"] else args.command
                    )
                    payload.update(command=command, workspace=args.workspace)
                else:
                    payload["id"] = args.id
            result = task_control(payload)
            if result.returncode and args.action == "notify":
                print(
                    json.dumps(
                        {
                            "type": "transport-lost",
                            "generation": CONNECTION["result"]["generation"],
                        }
                    )
                )
                return 0
            if result.returncode:
                raise ValueError(
                    "Task request failed; inspect its ID, never blindly replay create"
                )
            print(result.stdout.strip())
            if args.action == "task" and args.task_action == "wait":
                record = json.loads(result.stdout)
                code = record.get("exitCode")
                return (
                    (code if code >= 0 else 128 - code)
                    if isinstance(code, int)
                    else 130
                )
            return 0
        guest_control(
            {"action": "lease", "id": CONNECTION["lease"], "seconds": 300},
        )
    with held_lease():
        result = execute(args)
    print(
        json.dumps(
            {
                "action": args.action,
                "wallSeconds": round(time.monotonic() - start, 3),
                "exitCode": result.returncode,
            }
        ),
        file=sys.stderr,
    )
    return result.returncode


def execute(args):
    if args.action in {"ssh", "tunnel"}:
        argv = ssh_args()
        # Forward operations on our master are explicit, not silently ignored by multiplexing.
        if args.action == "tunnel":
            argv += ["-O", "forward", "-o", "ExitOnForwardFailure=yes"]
            for item in args.forward:
                argv += ["-L", item]
        else:
            argv += ["-tt"]
        result = subprocess.run(argv + [SSH_HOST])
    elif args.action == "close":
        Path(control_path() + ".stop").touch(mode=0o600)
        pidfile = Path(control_path() + ".keeper.pid")
        if pidfile.exists():
            try:
                pid = int(pidfile.read_text())
                process = Path(f"/proc/{pid}")
                argv = (process / "cmdline").read_bytes().split(b"\0")
                if process.stat().st_uid == os.getuid() and argv[-2].endswith(
                    b"/skill/scripts/transport.py"
                ):
                    os.kill(pid, signal.SIGTERM)
                    with Path(control_path() + ".keeper.lock").open("a") as lock:
                        fcntl.flock(lock, fcntl.LOCK_EX)
            except (ProcessLookupError, FileNotFoundError, IndexError, ValueError):
                pass
        result = subprocess.run(ssh_args() + ["-O", "exit", SSH_HOST])
    elif args.action == "doctor":
        # Fixed argv, no shell program or remote provisioning.
        result = remote_command(["uname", "-a"])
        if result.returncode == 0:
            result = remote_command(["df", "-h", "."])
        if result.returncode == 0:
            result = remote_command(["rsync", "--version"])
    elif args.action == "sync":
        source = args.source.expanduser().resolve()
        files = tracked_files(source, args.ignore_file)
        if not files.strip(b"\0"):
            raise ValueError("No eligible tracked files")
        if not args.dry_run:
            remote_command(
                [
                    "sudo",
                    "-n",
                    "-u",
                    "workshop",
                    "mkdir",
                    "-p",
                    "--",
                    args.workspace,
                ],
                check=True,
            )
        argv = [
            "rsync",
            "-azs",
            "--from0",
            "--files-from=-",
            "--stats",
            "-e",
            shlex.join(ssh_args()),
        ]
        if args.dry_run:
            argv += ["--dry-run", "--itemize-changes"]
        argv += ["--rsync-path=sudo -n -u workshop rsync"]
        result = subprocess.run(
            argv + [str(source) + "/", f"{SSH_HOST}:{args.workspace}/"], input=files
        )
    else:
        if args.dry_run and args.init:
            raise ValueError("--dry-run cannot initialize a directory")
        destination = artifact_directory(args.destination, args.init, args.delete)
        argv = [
            "rsync",
            "-azcs",
            "--stats",
            "--exclude=/" + MARKER,
            "-e",
            shlex.join(ssh_args()),
        ]
        if args.delete:
            argv += ["--delete"]
        if args.dry_run:
            argv += ["--dry-run", "--itemize-changes"]
        result = subprocess.run(
            argv + [f"{SSH_HOST}:{args.remote}/", str(destination) + "/"]
        )
    return result


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.TimeoutExpired:
        print("workshop: local command timed out", file=sys.stderr)
        sys.exit(1)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"workshop: {error}", file=sys.stderr)
        sys.exit(1)

"""Own a temporary direct IPv4 route for the lifetime of an SSH proxy."""

import fcntl
import ipaddress
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys


def options(config, address, runtime):
    if not config.get("bypassVpn", False):
        return []
    return ["-o", "ProxyCommand=" + shlex.join([
        sys.executable, str(Path(__file__)), address, str(runtime),
    ])]


def routes(*args):
    return json.loads(subprocess.check_output(["ip", "-j", "-4", "route", "show", *args]))


def main(address, runtime):
    address = str(ipaddress.IPv4Address(address))
    prefix = address + "/32"
    protocol = "187"

    def route(action, *args):
        subprocess.run(["sudo", "-n", "ip", "-4", "route", action, prefix,
                        "table", "main", "proto", protocol, *args], check=True)

    def stop(*_):
        raise KeyboardInterrupt

    for sig in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, stop)

    with (Path(runtime) / f"direct-{address}.lock").open("a") as mutex, (
        Path(runtime) / f"direct-{address}.lease"
    ).open("a") as lease:
        try:
            fcntl.flock(mutex, fcntl.LOCK_EX)
            try:
                fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                if routes("table", "main", "exact", prefix, "proto", protocol):
                    route("del")
                defaults = [r for r in routes("table", "main", "default") if r.get("gateway")]
                if not defaults:
                    raise ValueError("No IPv4 default gateway for Workshop VPN bypass")
                default = min(defaults, key=lambda r: r.get("metric", 0))
                hop = ["via", default["gateway"], "dev", default["dev"]]
                if not routes("table", "main", "exact", prefix):
                    route("add", *hop)
                actual = json.loads(subprocess.check_output([
                    "ip", "-j", "-4", "route", "get", address,
                ]))[0]
                if (actual.get("gateway"), actual.get("dev")) != (default["gateway"], default["dev"]):
                    raise ValueError("Workshop cannot route directly to " + address)
            fcntl.flock(lease, fcntl.LOCK_SH)
            fcntl.flock(mutex, fcntl.LOCK_UN)
            with subprocess.Popen(["nc", address, "22"]) as proxy:
                try:
                    return proxy.wait()
                finally:
                    if proxy.poll() is None:
                        proxy.kill()
        finally:
            for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
                signal.signal(sig, signal.SIG_IGN)
            fcntl.flock(lease, fcntl.LOCK_UN)
            fcntl.flock(mutex, fcntl.LOCK_EX)
            try:
                fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                pass
            else:
                if routes("table", "main", "exact", prefix, "proto", protocol):
                    route("del")


if __name__ == "__main__":
    try:
        sys.exit(main(*sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"Workshop direct SSH: {error}")

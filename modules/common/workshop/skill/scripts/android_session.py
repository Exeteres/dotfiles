"""Keep one named Android worker alive while its foreground ADB session is online."""

import ipaddress
import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

from direct_ssh import options


def session(config, name, port, invoke, export, runtime, screen=None, viewer=False):
    if not 1024 <= port <= 65535:
        raise ValueError("Android local port must be between 1024 and 65535")
    request = {"action": "android-open", "name": name}
    if screen is not None:
        request["screen"] = screen
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        result = invoke(config, request, retryable=True)
        if result["status"] == "ready":
            break
        if result["status"] not in {"pending", "busy"}:
            raise ValueError(
                result.get("error", "Android worker unavailable: " + result["status"])
            )
        time.sleep(5)
    else:
        raise ValueError("Timed out waiting for the Android worker")
    address = str(ipaddress.IPv4Address(result["ipv4"]))
    private_address = str(ipaddress.IPv4Address(result["privateIpv4"]))
    key = result["hostKey"].split()[:2]
    if (
        len(key) != 2
        or key[0] != "ssh-ed25519"
        or not re.fullmatch(r"[A-Za-z0-9+/=]+", key[1])
    ):
        raise ValueError("Invalid Android worker host key")
    endpoint = f"127.0.0.1:{port}"
    with tempfile.TemporaryDirectory(prefix="android-", dir=runtime) as directory:
        directory = Path(directory)
        export(config, directory)
        known = directory / "known_hosts"
        control = directory / "ssh"
        known.write_text(address + " " + " ".join(key) + "\n")
        command = [
            "ssh",
            "-F",
            "/dev/null",
            "-MNT",
            "-S",
            str(control),
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            "-o",
            "ServerAliveInterval=15",
            "-o",
            "ServerAliveCountMax=3",
            "-o",
            "ExitOnForwardFailure=yes",
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "IdentityAgent=none",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            f"UserKnownHostsFile={known}",
            "-o",
            "GlobalKnownHostsFile=/dev/null",
            "-i",
            str(directory / "identity"),
            "-L",
            f"{endpoint}:127.0.0.1:5555",
            "-l",
            config["login"],
            *options(config, address, runtime),
            address,
        ]

        def adb(*args):
            try:
                return subprocess.run(
                    ["adb", *args], capture_output=True, text=True, timeout=10
                ).stdout.strip()
            except subprocess.TimeoutExpired:
                return ""

        connected = False
        window = None
        with subprocess.Popen(command, stdin=subprocess.DEVNULL) as ssh:
            try:
                while ssh.poll() is None and time.monotonic() < deadline:
                    if not control.exists():
                        time.sleep(1)
                        continue
                    if (
                        adb("-s", endpoint, "shell", "getprop", "sys.boot_completed")
                        == "1"
                    ):
                        connected = True
                        break
                    adb("connect", endpoint)
                    time.sleep(3)
                if not connected:
                    raise ValueError(
                        "Android ADB did not become ready; check SSH and guest bootstrap"
                    )
                heartbeat = {
                    "action": "android-heartbeat",
                    "name": name,
                    "generation": result["generation"],
                }
                announced = False
                while (
                    ssh.poll() is None
                    and adb("-s", endpoint, "shell", "echo", "online") == "online"
                ):
                    state = invoke(config, heartbeat, retryable=True)
                    if state["status"] not in {"active", "pending", "busy"}:
                        raise ValueError("Android worker expired")
                    if state["status"] == "active" and not announced:
                        print(
                            json.dumps(
                                {
                                    "name": name,
                                    "adb": endpoint,
                                    "privateIpv4": private_address,
                                }
                            ),
                            flush=True,
                        )
                        announced = True
                        if viewer:
                            window = subprocess.Popen([
                                "scrcpy", "--serial", endpoint, "--max-size", "1280",
                                "--max-fps", "30", "--video-bit-rate", "3M", "--no-audio",
                                "--window-title", f"Workshop Android — {name}",
                            ])
                    if window is None:
                        time.sleep(30)
                    else:
                        until = time.monotonic() + 30
                        while ssh.poll() is None and time.monotonic() < until:
                            try:
                                return window.wait(timeout=1)
                            except subprocess.TimeoutExpired:
                                pass
                raise ValueError("Android ADB session disconnected")
            except KeyboardInterrupt:
                return 0
            finally:
                if window is not None and window.poll() is None:
                    window.terminate()
                if connected:
                    adb("disconnect", endpoint)
                ssh.terminate()
                try:
                    ssh.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    ssh.kill()

"""Isolated explicit-backend regression checks, run inside the Nix sandbox."""

import os
import json
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time


def run(*args, env=None):
    return subprocess.run(args, env=env, check=True, capture_output=True, text=True)


def wait_for_socket(path, process):
    for _ in range(200):
        if process.poll() is not None:
            raise AssertionError(f"Process exited before creating {path}")
        if path.exists():
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {path}")


def receive(stream, size):
    result = b""
    while len(result) < size:
        chunk = stream.recv(size - len(result))
        assert chunk, "Agent closed connection early"
        result += chunk
    return result


def key_count(path):
    with socket.socket(socket.AF_UNIX) as stream:
        stream.settimeout(5)
        stream.connect(str(path))
        stream.sendall(struct.pack(">I", 1) + b"\x0b")
        size = struct.unpack(">I", receive(stream, 4))[0]
        reply = receive(stream, size)
        assert reply[0] == 12, reply
        return struct.unpack(">I", reply[1:5])[0]


def wait_for_keys(path, count):
    for _ in range(150):
        if key_count(path) == count:
            return
        time.sleep(0.05)
    raise AssertionError(f"Expected {count} identities from {path}, got {key_count(path)}")


def main():
    mux = sys.argv[1]
    processes = []
    with tempfile.TemporaryDirectory(prefix="mux-") as temporary:
        root = Path(temporary)
        env = dict(os.environ, HOME=str(root), XDG_RUNTIME_DIR=str(root))

        def agent(name):
            path = root / name
            process = subprocess.Popen(
                ["ssh-agent", "-D", "-a", str(path)],
                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            processes.append(process)
            wait_for_socket(path, process)
            return path

        def start(name, *args, interval=0, extension_routes=None):
            directory = root / name
            directory.mkdir(mode=0o700)
            path = directory / "agent.sock"
            process = subprocess.Popen(
                [mux, "start", "--foreground", "--no-discovery",
                 "--refresh-interval", str(interval), "--socket", str(path),
                 "--pid-file", str(directory / "mux.pid"), *args],
                env=dict(env, SSH_AGENT_MUX_EXTENSION_ROUTES=json.dumps(extension_routes or {})),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            processes.append(process)
            wait_for_socket(directory / "control.sock", process)
            assert path.stat().st_mode & 0o777 == 0o600
            assert directory.stat().st_mode & 0o777 == 0o700
            return path, directory

        def refresh(directory):
            run(mux, "refresh", "--socket-dir", str(directory), env=env)

        try:
            # Extension payloads must reach only the configured backend, even
            # when it has no identities, and unsafe sockets remain rejected.
            extension_path = root / "extension-backend"
            listener = socket.socket(socket.AF_UNIX)
            listener.bind(str(extension_path))
            extension_path.chmod(0o600)
            listener.listen()
            extension_requests = []

            def extension_backend():
                while True:
                    stream, _ = listener.accept()
                    with stream:
                        size = struct.unpack(">I", receive(stream, 4))[0]
                        request = receive(stream, size)
                        if request[0] == 11:
                            reply = b"\x0c" + struct.pack(">I", 0)
                        else:
                            extension_requests.append(request)
                            reply = b"\x06"
                        stream.sendall(struct.pack(">I", len(reply)) + reply)

            threading.Thread(target=extension_backend, daemon=True).start()
            extension_name = b"custom@example.org"
            extension_request = b"\x1b" + struct.pack(">I", len(extension_name)) + extension_name + b"fixture"

            def extension_reply(path):
                with socket.socket(socket.AF_UNIX) as stream:
                    stream.settimeout(5)
                    stream.connect(str(path))
                    stream.sendall(struct.pack(">I", len(extension_request)) + extension_request)
                    size = struct.unpack(">I", receive(stream, 4))[0]
                    return receive(stream, size)

            routed, _ = start(
                "extensions", "--agent", str(extension_path),
                extension_routes={extension_name.decode(): str(extension_path)},
            )
            assert extension_reply(routed) == b"\x06"
            assert extension_requests == [extension_request]
            unrouted, _ = start("unmapped-extensions", "--agent", str(extension_path))
            assert extension_reply(unrouted) == b"\x1c"
            assert extension_requests == [extension_request]
            extension_path.chmod(0o666)
            assert extension_reply(routed) == b"\x05"
            assert extension_requests == [extension_request]

            backend = agent("backend")
            unrelated = agent("unrelated")
            env["SSH_AUTH_SOCK"] = str(unrelated)
            keys = []
            for name in ("unrelated-key", "first-key", "second-key"):
                key = root / name
                run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key), env=env)
                keys.append(key)
            run("ssh-add", str(keys[0]), env=dict(env, SSH_AUTH_SOCK=str(unrelated)))

            # Empty configurations must neither fail startup nor discover the
            # unrelated agent advertised through SSH_AUTH_SOCK.
            empty, empty_dir = start("empty")
            assert key_count(empty) == 0
            refresh(empty_dir)
            assert key_count(empty) == 0
            empty_background, _ = start("empty-background", interval=1)

            # Explicit backends may be empty at startup. Refresh must use only
            # that list; keys and signatures still route to the chosen agent.
            selected, selected_dir = start(
                "selected", "--agent", str(backend), "--primary-agent", str(backend),
            )
            assert key_count(selected) == 0
            run("ssh-add", str(keys[1]), env=dict(env, SSH_AUTH_SOCK=str(backend)))
            assert key_count(selected) == 0
            refresh(selected_dir)
            assert key_count(selected) == 1
            run("ssh-add", "-T", str(keys[1]) + ".pub", env=dict(env, SSH_AUTH_SOCK=str(selected)))

            # Additions through the mux go to the primary agent. The unrelated
            # agent never receives them or becomes part of the refreshed list.
            run("ssh-add", str(keys[2]), env=dict(env, SSH_AUTH_SOCK=str(selected)))
            assert key_count(backend) == 2
            assert key_count(unrelated) == 1
            refresh(selected_dir)
            assert key_count(selected) == 2
            run("ssh-add", "-T", str(keys[2]) + ".pub", env=dict(env, SSH_AUTH_SOCK=str(selected)))

            # Direct changes in a backend are picked up by periodic identity
            # refresh, without adding the unrelated agent to the backend set.
            periodic, _ = start("periodic", "--agent", str(backend), interval=1)
            assert key_count(periodic) == 2
            run("ssh-add", "-d", str(keys[1]) + ".pub", env=dict(env, SSH_AUTH_SOCK=str(backend)))
            wait_for_keys(periodic, 1)
            run("ssh-add", str(keys[1]), env=dict(env, SSH_AUTH_SOCK=str(backend)))
            wait_for_keys(periodic, 2)

            # A long polling interval proves that additions/removals through
            # the mux trigger refresh independently of periodic polling.
            run("ssh-add", "-d", str(keys[2]) + ".pub", env=dict(env, SSH_AUTH_SOCK=str(backend)))
            triggered, _ = start(
                "triggered", "--agent", str(backend), "--primary-agent", str(backend),
                interval=3600,
            )
            assert key_count(triggered) == 1
            run("ssh-add", str(keys[2]), env=dict(env, SSH_AUTH_SOCK=str(triggered)))
            wait_for_keys(triggered, 2)
            run("ssh-add", "-d", str(keys[2]) + ".pub", env=dict(env, SSH_AUTH_SOCK=str(triggered)))
            wait_for_keys(triggered, 1)

            # A configured backend unavailable at startup can recover without
            # rediscovering sockets or restarting the mux.
            late_path = root / "late-backend"
            late, _ = start("late", "--agent", str(late_path), interval=1)
            assert key_count(late) == 0
            agent("late-backend")
            run("ssh-add", str(keys[1]), env=dict(env, SSH_AUTH_SOCK=str(late_path)))
            wait_for_keys(late, 1)
            run("ssh-add", "-T", str(keys[1]) + ".pub", env=dict(env, SSH_AUTH_SOCK=str(late)))
            assert key_count(empty_background) == 0
            assert key_count(unrelated) == 1
            print("Explicit-only startup, manual/periodic/operation refresh, backend recovery, signing, and socket modes passed")
        finally:
            for process in reversed(processes):
                if process.poll() is None:
                    process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    main()

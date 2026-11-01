#!/usr/bin/env python3
"""Integration test using real SOPS and a disposable age key / Git repository.

Run: nix shell --inputs-from path:. nixpkgs#python3 nixpkgs#sops nixpkgs#age \
       --command python3 scripts/test-private-nix.py
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile


SCRIPT = Path(__file__).with_name("private-nix.py").resolve()


def run(*args, ok=True):
    result = subprocess.run(args, capture_output=True)
    if ok and result.returncode:
        raise AssertionError(result.stderr.decode())
    if not ok:
        assert result.returncode != 0, args
    return result.stdout


def sync(*args, **kwargs):
    return run(sys.executable, str(SCRIPT), *args, **kwargs)


def main():
    with tempfile.TemporaryDirectory(prefix="private-nix-test-") as directory:
        os.chdir(directory)
        run("git", "init", "--quiet")
        run("age-keygen", "-o", "key.txt")
        recipient = run("age-keygen", "-y", "key.txt").decode().strip()
        os.environ["SOPS_AGE_KEY_FILE"] = str(Path("key.txt").resolve())
        Path(".sops.yaml").write_text(
            "creation_rules:\n  - path_regex: '\\.enc$'\n"
            f"    age: {recipient}\n"
        )
        Path(".gitignore").write_text("private.nix\n*.private.nix\nkey.txt\n")
        Path("nested").mkdir()
        sources = {
            Path("private.nix"): b"{ home.packages = []; }\n",
            Path("nested/example.private.nix"): b"{ services.example.enable = true; }\n",
        }
        for path, data in sources.items():
            path.write_bytes(data)
        sync("encrypt", "--stage")
        encrypted = {Path(str(p) + ".enc"): Path(str(p) + ".enc").read_bytes() for p in sources}
        staged = run("git", "diff", "--cached", "--name-only").decode().splitlines()
        assert sorted(staged) == sorted(str(p) for p in encrypted)
        sync("encrypt")
        assert all(p.read_bytes() == data for p, data in encrypted.items()), "no-op encryption churn"

        # Recover plaintext and compare exact contents / permissions.
        for path in sources:
            path.unlink()
        sync("decrypt")
        for path, data in sources.items():
            assert path.read_bytes() == data
            assert path.stat().st_mode & 0o777 == 0o600

        plain = Path("private.nix")
        enc = Path("private.nix.enc")
        plain.write_bytes(b"{ localEdit = true; }\n")
        sync("decrypt")
        assert plain.read_bytes() == b"{ localEdit = true; }\n", "local edit overwritten"

        # Simulate an incoming encrypted edit while a local edit is outstanding.
        incoming = subprocess.check_output(
            ["sops", "encrypt", "--filename-override", str(enc),
             "--input-type", "binary", "--output-type", "json", "/dev/stdin"],
            input=b"{ incomingEdit = true; }\n",
        )
        enc.write_bytes(incoming)
        sync("decrypt", ok=False)
        sync("encrypt", ok=False)
        assert enc.read_bytes() == incoming
        assert plain.read_bytes() == b"{ localEdit = true; }\n"
        plain.unlink()
        sync("decrypt")
        assert plain.read_bytes() == b"{ incomingEdit = true; }\n"
        plain.write_bytes(b"{ resolved = true; }\n")
        sync("encrypt", "--stage")
        plain.unlink()
        sync("decrypt")
        assert plain.read_bytes() == b"{ resolved = true; }\n"

        # A missing key fails without replacing the local file.
        os.environ["SOPS_AGE_KEY_FILE"] = str(Path("missing-key").resolve())
        sync("decrypt", ok=False)
        assert plain.read_bytes() == b"{ resolved = true; }\n"

        # Even forcibly staged plaintext must prevent a commit.
        run("git", "add", "-f", "--", str(plain))
        sync("encrypt", "--stage", ok=False)
    print("Private Nix integration checks passed.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Synchronize SOPS binary documents and ignored private Nix modules."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def git(*args):
    return subprocess.check_output(["git", *args])


def private(path):
    return path.name == "private.nix" or path.name.endswith(".private.nix")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def atomic_write(path, data):
    fd, temporary = tempfile.mkstemp(prefix=".private-nix-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def sops(action, path, data):
    return subprocess.check_output(
        [
            "sops", "--config", ".sops.yaml", action,
            "--filename-override", str(path),
            "--input-type", "binary" if action == "encrypt" else "json", "--output-type",
            "json" if action == "encrypt" else "binary", "/dev/stdin",
        ],
        input=data,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["encrypt", "decrypt", "install"])
    parser.add_argument("--stage", action="store_true", help="stage all encrypted private modules")
    args = parser.parse_args()
    if args.stage and args.action != "encrypt":
        parser.error("--stage requires encrypt")

    root = Path(os.fsdecode(git("rev-parse", "--show-toplevel")).strip())
    os.chdir(root)
    if args.action == "install":
        existing = subprocess.run(
            ["git", "config", "--local", "--get", "core.hooksPath"],
            capture_output=True, text=True,
        ).stdout.strip()
        if existing and existing != ".githooks":
            raise RuntimeError(f"core.hooksPath is already {existing!r}; integrate the hooks manually")
        subprocess.run(["git", "config", "--local", "core.hooksPath", ".githooks"], check=True)
        print("Enabled .githooks for this clone. Run scripts/private-nix decrypt next.")
        return

    indexed = [Path(os.fsdecode(p)) for p in git("ls-files", "-z").split(b"\0") if p]
    if any(private(p) for p in indexed):
        raise RuntimeError("Plaintext private Nix files are tracked/staged; remove them from the index first")

    state_path = Path(os.fsdecode(git("rev-parse", "--git-path", "private-nix-state.json")).strip())
    state = json.loads(state_path.read_bytes()) if state_path.exists() else {}
    candidates = git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
    encrypted = {
        Path(os.fsdecode(p)) for p in candidates.split(b"\0")
        if p and os.fsdecode(p).endswith(".enc") and private(Path(os.fsdecode(p)[:-4]))
    }
    ignored = git("ls-files", "--others", "--ignored", "--exclude-standard", "-z")
    plaintext = {Path(os.fsdecode(p)) for p in ignored.split(b"\0") if p and private(Path(os.fsdecode(p)))}
    paths = encrypted if args.action == "decrypt" else {Path(str(p) + ".enc") for p in plaintext}
    pending = []
    stage = []
    for enc in sorted(paths):
        plain = Path(str(enc)[:-4])
        if enc.is_symlink() or plain.is_symlink():
            raise RuntimeError(f"Refusing symlink: {plain} / {enc}")
        if not enc.exists() and args.action == "decrypt":
            continue  # Staged deletions do not delete local plaintext.
        ciphertext = enc.read_bytes() if enc.exists() else None
        local = plain.read_bytes() if plain.exists() else None
        saved = state.get(str(enc), {})

        if args.action == "decrypt":
            decoded = sops("decrypt", enc, ciphertext)
            if local is not None and local != decoded:
                if saved.get("ciphertext") == digest(ciphertext):
                    print(f"Preserving local edits: {plain}")
                    continue
                if saved.get("plaintext") != digest(local):
                    raise RuntimeError(f"Local edits conflict with {enc}; reconcile them before decrypting")
            if local != decoded:
                pending.append((plain, decoded))
            state[str(enc)] = {"plaintext": digest(decoded), "ciphertext": digest(ciphertext)}
        else:
            synchronized = ciphertext is not None and saved.get("ciphertext") == digest(ciphertext)
            if synchronized:
                unchanged = saved.get("plaintext") == digest(local)
            else:
                decoded = sops("decrypt", enc, ciphertext) if ciphertext is not None else None
                unchanged = decoded == local
                if ciphertext is not None and not unchanged:
                    raise RuntimeError(f"{enc} differs from local plaintext; decrypt/reconcile it first")
            if not unchanged:
                ciphertext = sops("encrypt", enc, local)
                pending.append((enc, ciphertext))
            state[str(enc)] = {"plaintext": digest(local), "ciphertext": digest(ciphertext)}
            stage.append(str(enc))

    # Finish all SOPS operations/conflict checks before replacing any files.
    for path, data in pending:
        atomic_write(path, data)
        print(f"Updated {path}")
    atomic_write(state_path, json.dumps(state, indent=2).encode() + b"\n")
    if args.stage and stage:
        subprocess.run(["git", "add", "--", *stage], check=True)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"private-nix: {error}", file=sys.stderr)
        sys.exit(1)

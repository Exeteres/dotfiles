"""rbw-specific pinentry: SOPS master password, interactive other challenges."""

from pathlib import Path
import subprocess
import sys
from urllib.parse import quote_from_bytes


def respond(line):
    sys.stdout.buffer.write(line + b"\n")
    sys.stdout.buffer.flush()


def main():
    secret_file, interactive, *args = sys.argv[1:]
    respond(b"OK rbw SOPS pinentry")
    commands = []
    prompt = b""
    for line in sys.stdin.buffer:
        commands.append(line)
        command, _, value = line.rstrip(b"\r\n").partition(b" ")
        if command == b"SETPROMPT":
            prompt = value
        if command == b"GETPIN":
            if prompt == b"Master Password":
                # Accept a conventional one-line password file. Preserve spaces.
                password = Path(secret_file).read_bytes().removesuffix(b"\n").removesuffix(b"\r")
                if not password or b"\n" in password or b"\r" in password:
                    raise ValueError("invalid password file")
                respond(b"D " + quote_from_bytes(password, safe="").encode())
                respond(b"OK")
            else:
                # API credentials and 2FA must never receive the master password.
                result = subprocess.run(
                    [interactive, *args], input=b"".join(commands),
                    capture_output=True, check=True,
                )
                # Suppress the fallback's greeting and setup acknowledgements;
                # those have already been sent by this wrapper.
                responses = result.stdout.splitlines()
                for response in responses[len(commands):]:
                    respond(response)
            return
        if command == b"BYE":
            respond(b"OK")
            return
        respond(b"OK")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Do not log secret values, subprocess output, or exceptions.
        respond(b"ERR 83886179 Pinentry unavailable")
        sys.exit(1)

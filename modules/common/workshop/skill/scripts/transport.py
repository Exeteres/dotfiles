#!/usr/bin/env python3
"""Workshop SSH keeper. Never provisions or replays remote tasks."""

import fcntl
import json
import os
from pathlib import Path
import subprocess
import time

import workshop


def main():
    base = workshop.control_path()
    with Path(base + ".keeper.lock").open("a") as keeper:
        try:
            fcntl.flock(keeper, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        Path(base + ".keeper.pid").write_text(str(os.getpid()))
        delay = 10
        while not Path(base + ".stop").exists():
            try:
                if not workshop.load_transport():
                    config = workshop.configuration()
                    result = workshop.invoke_controller(
                        config, {"action": "status"}, retryable=True
                    )
                    if result.get("status") == "ready":
                        delay = 10
                        with Path(base + ".lock").open("a") as lock:
                            fcntl.flock(lock, fcntl.LOCK_EX)
                            if (
                                not Path(base + ".stop").exists()
                                and not workshop.load_transport()
                            ):
                                workshop.install_transport(
                                    config,
                                    result,
                                    "transport",
                                    Path(base + ".json"),
                                )
                    elif result.get("status") == "absent":
                        delay = min(delay * 2, 300)
                else:
                    delay = 10
            except (
                OSError,
                ValueError,
                subprocess.SubprocessError,
                KeyError,
                json.JSONDecodeError,
            ):
                # The foreground prepare reports errors; keeper waits through VM
                # restarts and outages without printing credentials or spinning.
                delay = min(delay * 2, 300)
            time.sleep(delay)


if __name__ == "__main__":
    main()

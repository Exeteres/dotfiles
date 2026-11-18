---
name: Workshop
description: Offload builds, tests, and other resource-intensive tasks to a disposable worker. Sync local source, run and monitor tasks, and bring results back.
---

# Workshop

Keep OpenCode, authoritative source, and required results local. Use Workshop for work that can be rerun from local source. **Never leave the only copy of work or results on the worker.**

## Run a task

Read the project's development and testing guides, then use the project's pinned commands. Run this example from the local Git repository root, replacing the agent ID, workspace, and test command:

```sh
workshop prepare --agent my-agent
```

After `prepare` and **before starting work**, launch `workshop notify --agent my-agent --cursor 0` as a background command through your agent harness. Keep one waiter per agent. When it returns an event, record its sequence and start another waiter with that cursor. Reset the cursor to zero if the worker generation changes.

```sh
workshop sync . /home/workshop/my-project
workshop task create /home/workshop/my-project -- nix develop -c make test
```

- `prepare` starts or resumes the worker. Reuse your agent ID to reuse your last resource estimate. If unknown, start with the defaults (8 vCPU, 32 GiB RAM, 93 GiB disk). Use `--cpu`, `--memory-gib`, or `--disk-gib` when the workload justifies more.
- `sync` uploads eligible Git-tracked files, including local edits. It skips files matched by `.gitignore`, `.git/info/exclude`, or global Git ignore rules, even if tracked. Use `--ignore-file PATH` (repeatable) for extra Git-style exclusions. Review `--dry-run` before uploading. Sync does not remove files already on the worker; use a fresh workspace if ignored or removed files would leave stale copies behind.
- `task create` returns a task ID. Use `workshop task get <id>` to check progress, `workshop task wait <id>` for the final result and exit code, and `workshop task cancel <id>` to stop your task. Keep task IDs private. Shell operators passed to `task create` are literal arguments; put multi-step commands in a reviewed project script.
- Pull required results before leaving the worker idle: `workshop pull /home/workshop/my-project/results ./results --init`. The remote path must be a directory. Use `--init` only for an empty local directory; `--delete` is only for an initialized scratch directory. Validate pulled artifacts locally before using them.

## Save work and recover

- **Disconnect:** A task can keep running after you lose the connection. Check `workshop status`, re-prepare if needed, and look up the existing task ID. If `task create` disconnected before returning an ID, treat the outcome as unknown; do not blindly submit it again.
- **Resize notice:** Stop submitting tasks. Save and pull results before the event's deadline (up to ten minutes), cancel your remaining tasks, then run `workshop ack --agent my-agent`. Unfinished tasks can be terminated. Re-prepare and restart the notification waiter once the worker returns.
- **Idle or recycled worker:** After 15 minutes idle, the worker can stop with its disk intact; `prepare` resumes it. After one hour of total idle time, the worker and its disk can be deleted. Recycling can also happen earlier, so treat both thresholds as cleanup rules, not retention guarantees. If the generation changed, re-sync and rebuild as needed. Use `task create` for unattended work; don't assume an untracked process or an open connection keeps the worker alive.
- **Authentication failure:** Ask the user to initialize or refresh their personal `yc` profile. Do not substitute other credentials or bypass host verification.

## When needed

- Prefer the project's pinned Nix environment. Nix and Docker are available. On Workshop, you may use passwordless `sudo -n` when needed for the requested development, build, or test work, including installing tools, without asking again. This permission does not extend to the local machine or other hosts. Verify installers before running them.
- Use `workshop ssh` for interactive troubleshooting and `workshop doctor` for basic diagnostics. No SSH config is needed. Use `workshop tunnel --forward LOCAL_PORT:REMOTE_PORT` when a local client needs a remote service; bind the service to loopback and verify the actual client workflow.
- See [language workflows](references/languages.md), [validation guidance](references/validation.md), and [offload measurements](references/measurements.md) if choosing what to offload or how to validate it.

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location(
    "workshop",
    Path(__file__).parents[1] / "modules/common/workshop/skill/scripts/workshop.py",
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class RemoteWorkTest(unittest.TestCase):
    def test_resource_estimates_are_agent_scoped_and_not_cloud_limits(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict(helper.os.environ, {"XDG_STATE_HOME": directory}),
        ):
            high = {"cpu": 1000, "memoryGiB": 4000, "diskGiB": 9999}
            self.assertEqual(helper.estimated_spec("a", high), high)
            self.assertEqual(helper.estimated_spec("a")["cpu"], 8)
            helper.estimated_spec("a", {"cpu": 16, "memoryGiB": 64}, remember=True)
            self.assertEqual(helper.estimated_spec("a")["cpu"], 16)
            self.assertEqual(helper.estimated_spec("b")["cpu"], 8)

    def test_managed_channels_cannot_open_a_second_transport(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict(helper.os.environ, {"XDG_RUNTIME_DIR": directory}),
        ):
            self.assertIn("ProxyCommand=false", helper.ssh_args())
            self.assertNotIn("ProxyCommand=false", helper.ssh_args(connect=True))
            self.assertEqual(
                helper.ssh_args(connect=True)[:3], ["ssh", "-F", "/dev/null"]
            )

    def test_cli_invocation_error_does_not_retry_denied_identity_or_expose_output(self):
        with patch.object(
            helper.subprocess,
            "run",
            return_value=SimpleNamespace(
                returncode=1,
                stdout="private-token",
                stderr="code = PermissionDenied desc = private-key",
            ),
        ):
            with self.assertRaisesRegex(
                ValueError, "yc function invocation failed"
            ) as error:
                helper.invoke_controller(
                    {"functionId": "test"}, {"action": "status"}, retryable=True
                )
        self.assertNotIn("private", str(error.exception))

    def test_lifecycle_retries_transient_controller_response(self):
        response = SimpleNamespace(returncode=0, stdout='{"statusCode":503}', stderr="")
        with patch.object(helper.subprocess, "run", return_value=response):
            self.assertEqual(
                helper.invoke_controller({"functionId": "test"}, {}, retryable=True)[
                    "status"
                ],
                "pending",
            )
            with self.assertRaises(ValueError):
                helper.invoke_controller({"functionId": "test"}, {})

    def test_status_uses_yc_and_takes_no_alias(self):
        response = SimpleNamespace(
            returncode=0,
            stdout=helper.json.dumps(
                {"statusCode": 200, "body": '{"status":"absent"}'}
            ),
        )
        with (
            patch.object(helper, "configuration", return_value={"functionId": "test"}),
            patch.object(helper.sys, "argv", ["workshop", "status"]),
            patch.object(helper.subprocess, "run", return_value=response) as run,
            patch("builtins.print") as output,
        ):
            self.assertEqual(helper.main(), 0)
            self.assertEqual(
                run.call_args.args[0],
                [
                    "yc",
                    "serverless",
                    "function",
                    "invoke",
                    "--id",
                    "test",
                    "--data-stdin",
                ],
            )
            self.assertEqual(
                helper.json.loads(
                    helper.json.loads(run.call_args.kwargs["input"])["body"]
                ),
                {"action": "status"},
            )
            output.assert_called_once_with('{"status": "absent"}')

    def test_controller_cannot_supply_arbitrary_ssh_hostnames(self):
        with (
            patch.object(
                helper,
                "invoke_controller",
                return_value={"status": "ready", "ipv4": "attacker.invalid"},
            ),
        ):
            with self.assertRaises(ValueError):
                helper.establish({"functionId": "test"})

    def test_managed_tasks_use_guest_admission_without_replay(self):
        result = SimpleNamespace(returncode=255)
        payload = {
            "action": "create",
            "workspace": "/home/workshop/project",
            "command": ["echo", "literal ; value"],
        }
        with patch.object(helper, "remote_command", return_value=result) as command:
            self.assertIs(helper.task_control(payload), result)
        command.assert_called_once_with(
            ["sudo", "-n", "/usr/local/lib/workshop/tasks.py", "control"],
            input=helper.json.dumps(payload),
            text=True,
            capture_output=True,
        )

    def test_extra_alias_is_rejected(self):
        with patch.object(helper.sys, "argv", ["workshop", "ssh", "workshop"]):
            with self.assertRaises(SystemExit) as error:
                helper.main()
        self.assertEqual(error.exception.code, 2)

    def test_remote_workspace_is_scoped(self):
        for value in [
            "/",
            "/home/dev",
            "/home/dev/../root",
            "~/work",
            "/tmp/work/test",
        ]:
            with self.assertRaises(ValueError):
                helper.remote_path(value)
        self.assertEqual(
            helper.remote_path("/home/dev/work/repo"), "/home/dev/work/repo"
        )

    def test_loopback_forward_only(self):
        self.assertEqual(helper.forward("43000:3000"), "127.0.0.1:43000:127.0.0.1:3000")
        for value in ["0:3000", "65536:3000", "0.0.0.0:22:22"]:
            with self.assertRaises(ValueError):
                helper.forward(value)

    def test_sync_sends_edited_tracked_source_not_secrets_or_untracked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            for name in [
                "source.py",
                ".env",
                ".env.production",
                "private.key",
                "state.db",
                "untracked.py",
            ]:
                (root / name).write_text("original")
            subprocess.run(
                [
                    "git",
                    "-C",
                    directory,
                    "add",
                    "source.py",
                    ".env",
                    ".env.production",
                    "private.key",
                    "state.db",
                ],
                check=True,
            )
            (root / "source.py").write_text("edited")
            self.assertEqual(helper.tracked_files(root), b"source.py\0")
            (root / "source.py").unlink()
            (root / "source.py").symlink_to("/etc/passwd")
            with self.assertRaises(ValueError):
                helper.tracked_files(root)

    def test_sync_applies_git_ignore_rules_even_to_tracked_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            (root / "nested").mkdir()
            files = [
                "keep.txt",
                "root.tmp",
                "keep.tmp",
                "nested/hide.txt",
                "local.txt",
                "global.txt",
                "extra.txt",
            ]
            for name in files:
                (root / name).write_text("tracked")
            subprocess.run(
                ["git", "-C", directory, "add", "-f", "--", *files], check=True
            )
            (root / ".gitignore").write_text("*.tmp\n!keep.tmp\n")
            (root / "nested/.gitignore").write_text("/hide.txt\n")
            (root / ".git/info/exclude").write_text("/local.txt\n")
            global_ignore = root / "global-ignore"
            global_ignore.write_text("/global.txt\n")
            subprocess.run(
                [
                    "git",
                    "-C",
                    directory,
                    "config",
                    "core.excludesFile",
                    str(global_ignore),
                ],
                check=True,
            )

            self.assertEqual(
                helper.tracked_files(root), b"extra.txt\0keep.tmp\0keep.txt\0"
            )
            extra = root / "extra-ignore"
            extra.write_text("/extra.txt\n!root.tmp\n")
            self.assertEqual(
                helper.tracked_files(root, [extra]), b"keep.tmp\0keep.txt\0"
            )

    def test_deletion_requires_explicit_empty_scratch_initialization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "artifacts"
            with self.assertRaises(ValueError):
                helper.artifact_directory(str(root), False, True)
            helper.artifact_directory(str(root), True, False)
            (root / "old.js").write_text("old output")
            self.assertEqual(helper.artifact_directory(str(root), False, True), root)
            with self.assertRaises(ValueError):
                helper.artifact_directory(str(root), True, False)
            alias = Path(directory) / "alias"
            alias.symlink_to(root)
            with self.assertRaises(ValueError):
                helper.artifact_directory(str(alias), False, True)


if __name__ == "__main__":
    unittest.main()

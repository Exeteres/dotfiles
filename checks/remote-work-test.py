import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "remote_work",
    Path(__file__).parents[1] / "modules/common/remote-work/skill/scripts/remote-work.py",
)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class RemoteWorkTest(unittest.TestCase):
    def test_rejects_option_and_shell_hosts(self):
        for value in ["-oProxyCommand=evil", "dev;touch x", "ssh://dev"]:
            with self.assertRaises(ValueError):
                helper.host(value)
        self.assertEqual(helper.host("dev"), "dev")

    def test_remote_workspace_is_scoped(self):
        for value in ["/", "/home/dev", "/home/dev/../root", "~/work", "/tmp/work/test"]:
            with self.assertRaises(ValueError):
                helper.remote_path(value)
        self.assertEqual(helper.remote_path("/home/dev/work/repo"), "/home/dev/work/repo")

    def test_loopback_forward_only(self):
        self.assertEqual(helper.forward("43000:3000"), "127.0.0.1:43000:127.0.0.1:3000")
        for value in ["0:3000", "65536:3000", "0.0.0.0:22:22"]:
            with self.assertRaises(ValueError):
                helper.forward(value)

    def test_sync_sends_edited_tracked_source_not_secrets_or_untracked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", directory], check=True)
            for name in ["source.py", ".env", ".env.production", "private.key", "state.db", "untracked.py"]:
                (root / name).write_text("original")
            subprocess.run(["git", "-C", directory, "add", "source.py", ".env", ".env.production", "private.key", "state.db"], check=True)
            (root / "source.py").write_text("edited")
            self.assertEqual(helper.tracked_files(root), b"source.py\0")
            (root / "source.py").unlink()
            (root / "source.py").symlink_to("/etc/passwd")
            with self.assertRaises(ValueError):
                helper.tracked_files(root)

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

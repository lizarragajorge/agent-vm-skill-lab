import contextlib
import importlib.util
import io
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


RUNNER = (
    Path(__file__).resolve().parents[1]
    / ".github/skills/vm-command/scripts/run.py"
)
spec = importlib.util.spec_from_file_location("vm_command", RUNNER)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class VMCommandTests(unittest.TestCase):
    def test_dry_run_never_connects(self):
        output = io.StringIO()
        with patch.object(runner.subprocess, "run") as execute:
            with contextlib.redirect_stdout(output):
                result = runner.main(
                    ["--host", "vm.example.com", "--user", "vmuser", "--dry-run"]
                )
        self.assertEqual(result, 0)
        execute.assert_not_called()
        self.assertIn("DRY RUN (no connection)", output.getvalue())
        self.assertIn("vmuser@vm.example.com", output.getvalue())

    def test_live_command_and_remote_exit_status(self):
        with patch.object(
            runner.subprocess, "run", return_value=subprocess.CompletedProcess([], 42)
        ) as execute:
            result = runner.main(["--host", "192.0.2.1", "--user", "vmuser"])
        self.assertEqual(result, 42)
        execute.assert_called_once_with(
            [
                "ssh", "-T",
                "-o", "BatchMode=yes",
                "-o", "StrictHostKeyChecking=yes",
                "-o", "ConnectTimeout=10",
                "--", "vmuser@192.0.2.1", "uname -s && hostname",
            ],
            timeout=20,
            check=False,
        )

    def test_invalid_connection_inputs_never_execute(self):
        for field, value in [
            ("--host", "-oProxyCommand=bad"),
            ("--host", "host; hostname"),
            ("--user", "user@other-host"),
        ]:
            with self.subTest(field=field, value=value):
                args = ["--host", "vm.example.com", "--user", "vmuser"]
                args[args.index(field) + 1] = value
                with patch.object(runner.subprocess, "run") as execute:
                    with contextlib.redirect_stderr(io.StringIO()):
                        with self.assertRaises(SystemExit) as error:
                            runner.main(args)
                self.assertEqual(error.exception.code, 2)
                execute.assert_not_called()

    def test_local_failures_are_reported(self):
        for failure, status, message in [
            (subprocess.TimeoutExpired("ssh", 20), 124, "timed out"),
            (FileNotFoundError(), 127, "SSH executable not found"),
        ]:
            with self.subTest(status=status):
                output = io.StringIO()
                with patch.object(runner.subprocess, "run", side_effect=failure):
                    with contextlib.redirect_stderr(output):
                        result = runner.main(
                            ["--host", "vm.example.com", "--user", "vmuser"]
                        )
                self.assertEqual(result, status)
                self.assertIn(message, output.getvalue())


if __name__ == "__main__":
    unittest.main()

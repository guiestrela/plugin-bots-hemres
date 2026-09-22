"""Actual Quickshell Process/stdin against an offline helper, never a gateway."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DelegationProcessTests(unittest.TestCase):
    def run_case(self, response, expected, exit_code=0, stall=False, missing=False):
        with tempfile.TemporaryDirectory(prefix="pbh-delegation-", dir=ROOT / "tests/ui") as folder:
            work = Path(folder)
            for name in ("Ui", "Commons"):
                (work / name).symlink_to(Path("/usr/share/omarchy/shell") / name)
            shutil.copytree(ROOT / "ui", work / "plugin/ui")
            scripts = work / "plugin/scripts"
            scripts.mkdir()
            # Assert the exact immutable stdin payload. No networking/imports
            # from production transport; only the QML Process is real here.
            (scripts / "hermes_delegate.py").write_text(
                'import json, sys\n'
                'payload = json.loads(sys.stdin.readline())\n'
                'assert payload["transport"] == "canonical-chat" and payload.get("async") is True, payload\n' +
                ('import time; time.sleep(10)\n' if stall else '') +
                'print(' + repr(response) + ', flush=True)\n' +
                'sys.exit(' + str(exit_code) + ')\n')
            shutil.copyfile(ROOT / "tests/ui/delegation.qml", work / "shell.qml")
            env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       QT_QPA_PLATFORMTHEME="", QT_QUICK_CONTROLS_STYLE="Basic", PBH_EXPECTED=expected, PBH_MISSING="1" if missing else "", PBH_TIMEOUT="1" if stall or missing else "")
            env.pop("WAYLAND_DISPLAY", None)
            env.pop("DISPLAY", None)
            result = subprocess.run(["quickshell", "-n", "-p", str(work)], env=env,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("DELEGATION_FATAL", result.stdout)
            self.assertIn("DELEGATION_RESULT 0", result.stdout)

    def test_unacknowledged_output_is_uncertain_not_success_or_failure(self):
        for response, exit_code, expected in [("", 0, "delivery-uncertain"), ("not json", 1, "delivery-uncertain"), ('{"ok":true}', 0, "delivery-uncertain"),
                                    ('{"ok":true,"state":"completed"}', 0, "completed"),
                                    ('{"ok":false,"state":"delivery-uncertain"}', 0, "delivery-uncertain")]:
            with self.subTest(response=response):
                self.run_case(response, expected, exit_code)

    def test_watchdog_stalled_helper_is_uncertain(self):
        self.run_case("", "delivery-uncertain", stall=True)

    def test_missing_executable_is_failed_not_running_forever(self):
        self.run_case("", "failed", missing=True)

    def test_explicit_failure(self):
        self.run_case('{"ok":false,"state":"failed","error":"invalid_request"}', "failed")

    def test_snapshot_stdin_ack_and_new_draft(self):
        self.run_case('{"ok":true,"state":"submitted","session_id":"fixture-session"}', "submitted")


if __name__ == "__main__":
    unittest.main()

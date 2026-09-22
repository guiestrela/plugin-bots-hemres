"""Real Qt6/Quickshell offscreen regression, using installed host Ui/Commons.
No live shell, gateway, credentials, installation or service is used.
Run: PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/ui -p test_surface.py -v
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SurfaceRegression(unittest.TestCase):
    def test_native_panel_lifecycle_and_two_synthetic_rows(self):
        self.assertIsNotNone(shutil.which('quickshell'), 'Quickshell is required')
        with tempfile.TemporaryDirectory(prefix='pbh-014a-') as folder:
            work = Path(folder)
            for name in ('Ui', 'Commons'):
                (work / name).symlink_to(Path('/usr/share/omarchy/shell') / name)
            baseline = os.environ.get('PBH_BASELINE_REF')
            if baseline:
                # Read an old revision into the temporary harness only. Never
                # checkout/reset the working tree or copy runtime credentials.
                plugin = work / 'plugin'
                plugin.mkdir()
                for name in ('ui', 'assets'):
                    shutil.copytree(ROOT / name, plugin / name)
                for name in ('BarWidget.qml', 'ui/BotPanel.qml'):
                    source = subprocess.check_output(
                        ['git', 'show', baseline + ':' + name], cwd=ROOT)
                    (plugin / name).write_bytes(source)
            else:
                (work / 'plugin').symlink_to(ROOT)
            shutil.copyfile(ROOT / 'tests/ui/surface.qml', work / 'shell.qml')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic')
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('DISPLAY', None)
            try:
                result = subprocess.run(['quickshell', '-n', '-p', str(work)], env=env,
                                        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
            except subprocess.TimeoutExpired as exc:
                self.fail('Harness timed out: ' + str(exc.stdout))
            print(result.stdout)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn('PBH_FATAL', result.stdout)
            self.assertIn('PBH_RESULT 0', result.stdout)


if __name__ == '__main__':
    unittest.main()

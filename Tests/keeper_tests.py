import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('keeper', Path(__file__).parents[1]/'Resources/QuotaKeeper/quota_keeper.py')
k = importlib.util.module_from_spec(spec)
spec.loader.exec_module(k)

class KeeperTests(unittest.TestCase):
    def test_blocked_and_rounded_and_same_window(self):
        self.assertFalse(k.eligible({}, {}, {'usedPercent':1}, {}, 50000)[0])
        self.assertFalse(k.eligible({}, {}, {'usedPercent':0}, {'last_attempt':49999}, 50000)[0])
        self.assertFalse(k.eligible({}, {}, {'usedPercent':0,'resetsAt':60000}, {'window_reset':60000}, 50000)[0])
        self.assertFalse(k.eligible({'ordinaryUsageAllowed':False}, {}, {'usedPercent':0}, {}, 50000)[0])
        self.assertFalse(k.eligible({}, {'secondary':{'usedPercent':100}}, {'usedPercent':0}, {}, 50000)[0])
    def test_tick_sends_once_even_when_zero_does_not_change(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(k, 'DATA', Path(directory)), patch.object(k, 'read_limits', return_value=({}, {}, {'usedPercent':0,'resetsAt':k.time.time()+18000})), patch.object(k, 'codex', return_value='/fake/codex'), patch.object(k.subprocess, 'run') as run:
            run.return_value.returncode = 0
            k.check(True)
            k.check(True)
            self.assertEqual(run.call_count, 1)
            args = run.call_args.args[0]
            self.assertIn('--ignore-user-config', args)
            self.assertIn('--ephemeral', args)
            self.assertEqual(json.loads((Path(directory)/'state.json').read_text())['outcome'], 'success')
    def test_failure_persists_cooldown(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(k, 'DATA', Path(directory)), patch.object(k, 'read_limits', return_value=({}, {}, {'usedPercent':0})), patch.object(k, 'codex', return_value='/fake/codex'), patch.object(k.subprocess, 'run') as run:
            run.return_value.returncode = 1
            with self.assertRaises(RuntimeError): k.check(True)
            k.check(True)
            self.assertEqual(run.call_count, 1)

if __name__ == '__main__': unittest.main()

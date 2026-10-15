#!/usr/bin/env python3
"""Kamailio translation of the Softswitch server Logs tab, with a fake kamcmd."""
import importlib.util
from pathlib import Path
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('kamlogs', ROOT / 'scripts/kamailio-softswitch-logs.py')
kam = importlib.util.module_from_spec(spec)
spec.loader.exec_module(kam)
BASE = {'managed': True, 'logEnabled': True, 'logLevel': 'notice', 'logRetentionDays': 7,
        'logDebugUntil': None}


class KamailioLogs(unittest.TestCase):
    def setUp(self):
        self.calls, self.pid = [], '7'
        for patch in [
            mock.patch.object(kam, 'kamcmd', side_effect=lambda *args: self.calls.append(args) or ''),
            mock.patch.object(kam, 'main_pid', side_effect=lambda: self.pid),
            mock.patch.object(kam.core, 'low_disk', return_value=False),
        ]:
            patch.start()
            self.addCleanup(patch.stop)

    def test_levels_map_to_core_debug_live(self):
        marker = None
        for level, value in (('debug', '3'), ('info', '2'), ('notice', '1'), ('warning', '0')):
            marker = kam.apply(dict(BASE, logLevel=level), marker)
            self.assertEqual(self.calls[-1], ('corex.debug', value))

    def test_security_warning_line_survives_a_disabled_log(self):
        kam.apply(dict(BASE, logEnabled=False, logLevel='debug'), None)
        self.assertEqual(self.calls, [('corex.debug', '0')])

    def test_reapplied_only_after_change_or_restart(self):
        marker = kam.apply(BASE, None)
        kam.apply(BASE, marker)
        self.assertEqual(len(self.calls), 1)
        self.pid = '8'
        kam.apply(BASE, marker)
        self.assertEqual(len(self.calls), 2)


if __name__ == '__main__':
    unittest.main()

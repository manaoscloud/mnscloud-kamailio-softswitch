#!/usr/bin/env python3
"""Apply the Softswitch server Logs tab on Kamailio and keep /var/log/mnscloud/kamailio bounded.

Run every minute by mnscloud-kamailio-softswitch-logs.timer. The core `debug` level is changed live
through the corex RPC (`kamcmd corex.debug N`, no restart) and re-applied after a restart. The
systemd unit appends stdout/stderr to files, so rotation copies and truncates them. The
"SIP edge denied" lines read by CrowdSec are L_WARN, so the lowest level applied is L_WARN.
"""
import grp
import importlib.util
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('mnscloud_engine_logs', HERE / 'mnscloud_engine_logs.py')
core = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(core)

IDENTITY = Path('/etc/mnscloud/softswitch')
LOG_DIR = Path('/var/log/mnscloud/kamailio')
# Kamailio core levels: L_ERR=-1, L_WARN=0, L_NOTICE=1, L_INFO=2, L_DBG=3. `error` stays at L_WARN:
# the "SIP edge denied" security line read by CrowdSec is L_WARN and must never be disabled.
DEBUG = {'error': 0, 'warning': 0, 'notice': 1, 'info': 2, 'debug': 3}


def kamcmd(*args):
    result = subprocess.run(['kamcmd', *args], capture_output=True, text=True, timeout=15)
    if result.returncode or 'error' in (result.stdout + result.stderr).lower():
        raise RuntimeError('Kamailio RPC failed: ' + args[0])
    return result.stdout


def main_pid():
    result = subprocess.run(['systemctl', 'show', '-p', 'MainPID', '--value', 'kamailio'],
                            capture_output=True, text=True, timeout=10)
    return result.stdout.strip() or '0'


def apply(settings, previous):
    level = core.effective_level(settings, core.low_disk(LOG_DIR))
    marker = {'pid': main_pid(), 'level': level}
    if marker['pid'] == '0':
        return {'pid': '0', 'level': None}  # Not running: apply on the next refresh.
    if marker != previous:
        kamcmd('corex.debug', str(DEBUG[level]))
    return marker


def capture_owner():
    try:
        return 0, grp.getgrnam('kamailio').gr_gid
    except KeyError:
        return None


def maintain(settings):
    days, rotated, deleted = settings['logRetentionDays'], [], 0
    for name, owner, mode in (('kamailio.err.log', None, 0o640), ('kamailio.out.log', None, 0o640),
                              ('cdr-diagnostic-capture.log', capture_owner(), 0o660)):
        result = core.rotate(LOG_DIR / name, core.STATE_ROOT / f'kamailio-{name}-rotated', owner, mode=mode)
        if result:
            rotated.append(str(result))
        deleted += core.purge(LOG_DIR, [f'{name}-*.gz', f'{name}.[0-9]*'], days)
    core.maintain_install_log(days)
    return {'rotated': rotated, 'deleted': deleted}


def fetch():
    base, node, token = core.read_identity(IDENTITY, 'api.token')
    return core.fetch_settings(base, 'softswitch/runtime/log-config', node, token,
                               query={'engine': 'kamailio'})


if __name__ == '__main__':
    os.environ.setdefault('LC_ALL', 'C')
    core.main('kamailio-softswitch', fetch, apply, maintain)

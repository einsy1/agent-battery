#!/usr/bin/env python3
"""Read Codex subscription limits and make at most one tiny turn per 5h."""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import tempfile
import time

HOME = Path.home()
DATA = HOME / 'Library/Application Support/CodexQuotaKeeper'
LABEL = 'local.codex.quota-keeper'
PLIST = HOME / 'Library/LaunchAgents' / (LABEL + '.plist')
BUNDLED = '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'


def codex():
    result = os.environ.get('QUOTA_CODEX_BIN') or shutil.which('codex')
    if not result and Path(BUNDLED).exists():
        result = BUNDLED
    if not result:
        raise RuntimeError('找不到 Codex CLI，请安装或设置 QUOTA_CODEX_BIN')
    return result


class RPC:
    def __init__(self):
        self.proc = subprocess.Popen([codex(), 'app-server'], stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.proc.stdout, selectors.EVENT_READ)
        self.buffer = b''
        self.seq = 0

    def send(self, value):
        self.proc.stdin.write((json.dumps(value) + '\n').encode())
        self.proc.stdin.flush()

    def call(self, method, params=None):
        self.seq += 1
        ident = self.seq
        self.send(dict(id=ident, method=method, params=params or {}))
        deadline = time.monotonic() + 40
        while time.monotonic() < deadline:
            if b'\n' not in self.buffer:
                if not self.selector.select(max(0, deadline - time.monotonic())):
                    break
                chunk = os.read(self.proc.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('Codex app-server 已退出')
                self.buffer += chunk
            while b'\n' in self.buffer:
                line, self.buffer = self.buffer.split(b'\n', 1)
                value = json.loads(line)
                if value.get('id') == ident and ('result' in value or 'error' in value):
                    if 'error' in value:
                        raise RuntimeError('Codex RPC: ' + str(value['error']))
                    return value['result']
                if 'id' in value and 'method' in value:
                    self.send({'id': value['id'], 'error': {'code': -32601, 'message': 'Unsupported'}})
        raise TimeoutError(method + ' 超时')

    def __enter__(self):
        self.call('initialize', {'clientInfo': {'name': 'quota_keeper', 'version': '1.0.0'}})
        self.send({'method': 'initialized'})
        return self

    def __exit__(self, *args):
        self.close()

    def close(self):
        self.selector.close()
        self.proc.terminate()
        try:
            self.proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.communicate()


def read_limits():
    rpc = RPC()
    try:
        rpc.__enter__()
        account = rpc.call('account/read').get('account') or {}
        if account.get('type') != 'chatgpt':
            raise RuntimeError('当前 CLI 不是 ChatGPT 订阅登录，停止以避免使用 API 计费')
        result = rpc.call('account/rateLimits/read')
        bucket = (result.get('rateLimitsByLimitId') or {}).get('codex') or result.get('rateLimits') or {}
        windows = [bucket.get('primary'), bucket.get('secondary')]
        five = next((w for w in windows if w and w.get('windowDurationMins') == 300), None)
        if not five or not isinstance(five.get('usedPercent'), (int, float)):
            raise RuntimeError('未找到有效的 300 分钟额度，停止触发')
        return result, bucket, five
    finally:
        rpc.close()


def eligible(result, bucket, five, state, now):
    if five['usedPercent'] != 0:
        return False, '5 小时额度未满'
    if result.get('ordinaryUsageAllowed') is False or bucket.get('spendControlReached') or bucket.get('rateLimitReachedType'):
        return False, '账户当前限制使用'
    for key in ('primary', 'secondary'):
        window = bucket.get(key)
        if window and window.get('usedPercent', 100) >= 100:
            return False, '其他额度已耗尽'
    last = state.get('last_attempt', 0)
    if now - last < 5 * 3600 + 60:
        return False, '防重复保护：距上次触发不足 5 小时 1 分钟'
    reset = five.get('resetsAt')
    # Zero may be rounded after a tiny turn. Do not repeat within the same server window.
    if reset and reset > now and state.get('window_reset') == reset:
        return False, '此服务端窗口已触发'
    return True, '额度已满，可触发'


def save(state):
    tmp = DATA / 'state.tmp'
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=2))
    tmp.chmod(0o600)
    tmp.replace(DATA / 'state.json')


def check(trigger=False):
    DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (DATA / 'run.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('另一个检查正在进行，跳过')
            return
        state_path = DATA / 'state.json'
        state = json.loads(state_path.read_text()) if state_path.exists() else {}
        result, bucket, five = read_limits()
        now = time.time()
        ok, reason = eligible(result, bucket, five, state, now)
        reset = five.get('resetsAt')
        print(dt.datetime.now().astimezone().isoformat(timespec='seconds'),
              '5 小时剩余：{}%；重置：{}；{}'.format(100-five['usedPercent'],
              dt.datetime.fromtimestamp(reset).astimezone().isoformat() if reset else '未知', reason), flush=True)
        if not trigger or not ok:
            return
        # Persist before sending: timeout/crash must not cause repeated billable turns.
        state.update(last_attempt=now, window_reset=reset, outcome='attempting')
        save(state)
        with tempfile.TemporaryDirectory(prefix='codex-quota-') as work:
            command = [codex(), 'exec', '--ignore-user-config', '--ignore-rules', '--ephemeral',
                       '--skip-git-repo-check', '-s', 'read-only', '-C', work,
                       '-c', 'model_provider="openai"', '-c', 'model_reasoning_effort="low"',
                       'Reply with exactly OK. Do not use any tools, inspect files, or perform any other task.']
            # Remove API credentials; subscription authentication comes from Codex's own login.
            env = {k:v for k,v in os.environ.items() if k not in
                   ('OPENAI_API_KEY', 'OPENAI_BASE_URL', 'CODEX_API_KEY')}
            try:
                completed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=120)
                state['outcome'] = 'success' if completed.returncode == 0 else 'failed'
                state['exit_code'] = completed.returncode
            except subprocess.TimeoutExpired:
                state['outcome'] = 'timeout'
        save(state)
        print('轻量调用结果：' + state['outcome'], flush=True)
        if state['outcome'] != 'success':
            raise RuntimeError('触发未确认成功；保留 5 小时冷却，避免重复消耗。详见 state.json')


def install():
    import plistlib
    DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = DATA / 'quota_keeper.py'
    if Path(__file__).resolve() != target:
        shutil.copy2(__file__, target)
    PLIST.parent.mkdir(parents=True, exist_ok=True)
    python = str(Path(sys.executable).resolve())
    payload = {'Label': LABEL, 'ProgramArguments': [python, str(target), 'tick'],
               'StartInterval': 300, 'RunAtLoad': True,
               'EnvironmentVariables': {'PATH': '/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin',
                                        'QUOTA_CODEX_BIN': codex()},
               'StandardOutPath': str(DATA/'keeper.log'), 'StandardErrorPath': str(DATA/'error.log')}
    PLIST.write_bytes(plistlib.dumps(payload))
    subprocess.run(['launchctl', 'bootout', 'gui/'+str(os.getuid()), str(PLIST)], capture_output=True)
    subprocess.run(['launchctl', 'bootstrap', 'gui/'+str(os.getuid()), str(PLIST)], check=True)
    print('已启用：每 5 分钟检查，登录后自动运行。日志：' + str(DATA/'keeper.log'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['status', 'tick', 'install', 'uninstall'], nargs='?', default='status')
    args = parser.parse_args()
    if args.action == 'install':
        install()
    elif args.action == 'uninstall':
        subprocess.run(['launchctl', 'bootout', 'gui/'+str(os.getuid()), str(PLIST)], capture_output=True)
        PLIST.unlink(missing_ok=True)
        print('已停止并移除自动运行，保留日志和状态。')
    else:
        check(args.action == 'tick')


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)

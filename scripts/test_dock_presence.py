"""真机回归：DEBUG app 的最后一个普通窗口关闭后必须移出 Dock。

用法：make test-dock（先 make build && make run）；会关闭 app 的普通窗口。
"""

from pathlib import Path
import json
import subprocess
import tempfile
import time


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout.strip()


def debug(*args):
    run('swift', 'scripts/transfer_debug.swift', *args)


def assert_presence(expected, label, output):
    for _ in range(20):
        actual = run('osascript', 'scripts/dock_click.applescript', 'check')
        if actual == expected:
            break
        time.sleep(0.1)
    output.unlink(missing_ok=True)
    debug('dump', str(output))
    for _ in range(20):
        if output.exists():
            break
        time.sleep(0.1)
    state = json.loads(output.read_text())
    assert actual == expected, f'{label}: Dock {actual}, expected {expected}; {state}'
    assert state['activationPolicy'] == (0 if expected == 'present' else 1), state
    print(f'PASS: {label}: Dock {actual}, tracked={state["trackedWindows"]}')


def main():
    with tempfile.TemporaryDirectory(prefix='gapless-dock-test-') as directory:
        output = Path(directory) / 'state.json'
        debug('windows', 'close')
        assert_presence('absent', '没有窗口', output)
        debug('fixture', 'failure')
        debug('details')
        assert_presence('present', '仅传输详情', output)
        run('osascript', 'scripts/ax_close_window.applescript', '失败详情')
        assert_presence('absent', '通过标题栏关闭最后一个详情窗口', output)
        debug('windows', 'settings')
        assert_presence('present', '仅设置', output)
        debug('windows', 'preview')
        debug('details')
        run('osascript', 'scripts/ax_close_window.applescript', '失败详情')
        run('osascript', 'scripts/ax_close_window.applescript', '🔍')
        assert_presence('present', '预览和详情已关、设置仍打开', output)
        run('osascript', 'scripts/ax_close_window.applescript', '设置')
        assert_presence('absent', '所有普通窗口已关闭', output)


if __name__ == '__main__':
    main()

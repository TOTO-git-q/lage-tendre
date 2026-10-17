"""Run muted offscreen geometry regression at both resolutions and Ctrl+ zoom."""
from pathlib import Path
import argparse
import json
import os
import subprocess
import sys
from sync_core import sync
from test_results import classify
ROOT = Path(__file__).resolve().parents[1]
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--godot', default=os.environ.get('GODOT', r'E:\tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe' if os.name == 'nt' else str(ROOT / '.tools/godot')))
    p.add_argument('--headless', action='store_true')
    p.add_argument('--quick', action='store_true', help='Development smoke only; does not satisfy 20s playback')
    args = p.parse_args()
    sync()
    out = ROOT / 'dist/layout-stability'; out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    for k in ('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME'):
        env[k] = str(out / k.lower()); Path(env[k]).mkdir(parents=True, exist_ok=True)
    flags = ['--headless'] if args.headless else ['--position', '-5000,-5000', '--rendering-driver', 'opengl3']
    cmd = [args.godot, '--audio-driver', 'Dummy', '--path', str(ROOT / 'charter'), *flags, '-s', 'res://tests/charter_layout.gd', '--']
    if args.quick: cmd.append('--quick')
    label = ('headless' if args.headless else 'offscreen') + ('-quick' if args.quick else '')
    log_path = out / (label + '.log')
    with log_path.open('wb') as sink:
        result = subprocess.run(cmd, env=env, stdout=sink, stderr=subprocess.STDOUT, timeout=300)
    log = log_path.read_text(encoding='utf-8', errors='replace')
    failures, diagnostics = classify('charter_layout', log)
    bad = result.returncode or failures or 'failures=0' not in log
    samples = next((json.loads(line.removeprefix('LAYOUT_SAMPLES ')) for line in log.splitlines() if line.startswith('LAYOUT_SAMPLES ')), [])
    (out / (label + '.json')).write_text(json.dumps({'pass':not bool(bad), 'quick':args.quick, 'samples':samples, 'failures':failures, 'retained_diagnostics':diagnostics, 'log':str(out / (label+'.log'))}, indent=2), encoding='utf-8')
    for line in dict.fromkeys(log.splitlines()):
        if line.startswith(('FAIL ', 'LAYOUT ', 'LAYOUT_SIZE', 'SCRIPT ERROR', 'LAYOUT_SAMPLES')): print(line)
    print(label, 'FAIL' if bad else 'PASS')
    return int(bool(bad))
if __name__ == '__main__': sys.exit(main())

#!/usr/bin/env python3
"""Run the canonical 17-case game suite while retaining every unfiltered result.

The canonical script normally filters stdout. A temporary GODOT shim records
exact engine stdout/stderr and returns the same bytes/status to that script.
The separately documented game-default replay adds the eighteenth case.
"""
from __future__ import annotations
import argparse
import sys
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[2] / "tools"))
from godot_path import default_godot
from workspace_temp import TemporaryWorkspace
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile


def capture(config_path: str, argv: list[str]) -> int:
    config = json.loads(Path(config_path).read_text())
    script_path = argv[argv.index('-s') + 1]
    script = Path(script_path).stem
    extra = argv[argv.index('--') + 1:] if '--' in argv else []
    matched = [case for case in config['cases'] if case['script'] == script and case['args'] == extra]
    if len(matched) != 1:
        print('FAIL canonical shim: unexpected invocation ' + repr(argv), file=sys.stderr)
        return 2
    case = matched[0]
    completed = subprocess.run([config['godot'], *argv], capture_output=True, text=True, timeout=600)
    stdout, stderr = completed.stdout, completed.stderr
    output = stdout + stderr
    out = Path(config['out'])
    (out / 'logs' / (case['name'] + '.txt')).write_text(output)
    record = {
        'script': script,
        'args': [arg.replace(config['project'], '<project>') for arg in extra],
        'exit_code': completed.returncode,
        'lines': [line.rstrip() for line in stdout.splitlines() if line.strip() and not line.startswith('Godot Engine v')],
        'errors': [line for line in output.splitlines() if re.search(r'(?:SCRIPT ERROR|Parse Error|^ERROR:|^LOAD FAIL|^BAD\b|^FAIL\b|:\s*FAIL\b|^bad charts:\s*[1-9])', line)],
        'stdout_sha256': hashlib.sha256(stdout.encode()).hexdigest(),
    }
    (out / 'records' / (case['name'] + '.json')).write_text(json.dumps(record, indent=2) + '\n')
    sys.stdout.write(stdout)
    sys.stderr.write(stderr)
    return completed.returncode


def main() -> int:
    if len(sys.argv) > 2 and sys.argv[1] == '--capture':
        return capture(sys.argv[2], sys.argv[3:])
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--godot')
    parser.add_argument('--project', type=Path, help='Normally inferred from this script location')
    args = parser.parse_args()
    project = args.project.resolve() if args.project else Path(__file__).resolve().parents[1]
    root = project.parent
    godot = str(Path(args.godot or root / '.tools/godot').resolve())
    sys.path.insert(0, str(project / 'tests'))
    from capture_baseline import cases
    expected = [{'name': name, 'script': script, 'args': extra} for name, script, extra in cases()]
    out = args.out.resolve()
    for child in ['logs', 'records']:
        (out / child).mkdir(parents=True, exist_ok=True)
    if any((out / 'records').iterdir()):
        parser.error('Refuse to mix previous records: choose a new output directory')
    with TemporaryWorkspace(dir=Path(__file__).resolve().parents[2] / "dist", prefix='lage-canonical-') as home:
        env = dict(os.environ, HOME=home, XDG_DATA_HOME=home+'/data', XDG_CACHE_HOME=home+'/cache', XDG_CONFIG_HOME=home+'/config')
        for child in ['data', 'cache', 'config']:
            Path(home, child).mkdir()
        version = subprocess.run([godot, '--headless', '--audio-driver', 'Dummy', '--version'], capture_output=True, text=True, env=env, check=True).stdout.strip()
        if not version.startswith('4.7.2.'):
            raise SystemExit('Expected official Godot 4.7.2; got ' + version)
        config = Path(home, 'capture.json')
        config.write_text(json.dumps({'godot':godot, 'project':str(project), 'out':str(out), 'cases':expected}))
        shim = Path(home, 'godot-capture')
        command = [sys.executable, str(Path(__file__).resolve()), '--capture', str(config)]
        shim.write_text('#!/bin/sh\nexec ' + ' '.join(shlex.quote(x) for x in command) + ' "$@"\n')
        shim.chmod(0o700)
        env['GODOT'] = str(shim)
        print('RUN tools/run_tests.sh --canonical with unfiltered recording', flush=True)
        canonical = subprocess.run(['bash', str(root / 'tools/run_tests.sh'), '--canonical'], cwd=root, env=env, capture_output=True, text=True, timeout=3600)
        (out / 'canonical_run_tests.log').write_text(canonical.stdout + canonical.stderr)
        (out / 'canonical_exit_code.txt').write_text(str(canonical.returncode)+'\n')
        # The canonical script also writes a shared results.txt. Derive this
        # phase's tee record from its own captured stdout, avoiding collisions.
        lines = canonical.stdout.splitlines(keepends=True)
        if lines and lines[-1].startswith('results: '):
            lines.pop()
        (out / 'canonical_results.txt').write_text(''.join(lines))
        canonical_count = len(list((out / 'records').glob('*.json')))
        supplement = next(case for case in expected if case['name'] == 'replay_log__game_defaults')
        print('RUN supplemental replay with explicit shipped game defaults', flush=True)
        replay = subprocess.run([str(shim), '--headless', '--audio-driver', 'Dummy', '--path', str(project), '-s', 'res://tests/replay_log.gd', '--', *supplement['args']], cwd=root, env=env, capture_output=True, text=True, timeout=600)
        (out / 'supplemental_invocation.log').write_text(replay.stdout + replay.stderr)
    tests = {case['name']:json.loads((out/'records'/(case['name']+'.json')).read_text()) for case in expected if (out/'records'/(case['name']+'.json')).exists()}
    complete = canonical.returncode == 0 and canonical_count == 17 and replay.returncode == 0 and len(tests) == 18 and all(record['exit_code'] == 0 and record['lines'] and not record['errors'] for record in tests.values())
    run = {'schema':1, 'scope':'numeric', 'source_commit':args.source_commit, 'godot':version, 'tests':tests, 'numeric_capture_complete':complete,
           'capture_protocol':'Canonical tools/run_tests.sh --canonical, GODOT shim retaining unfiltered streams, plus explicit game-default replay.',
           'canonical_invocations':canonical_count, 'canonical_exit_code':canonical.returncode,
           'replay_note':'The construction command uses cut_same_track=false; game_defaults explicitly uses true. No game rule was changed.'}
    (out/'baseline_tests.json').write_text(json.dumps(run, ensure_ascii=False, indent=2)+'\n')
    print('CANONICAL + NUMERIC CAPTURE ' + ('COMPLETE' if complete else 'FAILED'), flush=True)
    return 0 if complete else 1


if __name__ == '__main__':
    raise SystemExit(main())

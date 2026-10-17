"""MOCK-only orchestrator tests; never produce publishable game evidence."""
from pathlib import Path
import json,os,subprocess,tempfile,sys
project=Path(__file__).resolve().parents[1];root=project.parent
sys.path.insert(0,str(project/'tests'));from capture_baseline import cases
baseline=json.load(open(project/'tests/baselines/baseline_tests.json'))
with tempfile.TemporaryDirectory(prefix='lage-canonical-MOCK-') as tmp:
    tmp=Path(tmp)
    fake_root=tmp/'isolated_repo'; fake_project=fake_root/'game'
    (fake_project/'tests').mkdir(parents=True); (fake_root/'tools').mkdir()
    (fake_root/'tools/run_tests.sh').write_bytes((root/'tools/run_tests.sh').read_bytes())
    fake_cases=[(n,s,[v.replace(str(project),str(fake_project)) for v in a]) for n,s,a in cases()]
    (fake_project/'tests/capture_baseline.py').write_text('def cases():\n    return '+repr(fake_cases)+'\n')
    data={'version':baseline['godot'],'cases':[{'script':s,'args':a,'lines':baseline['tests'][n]['lines']} for n,s,a in fake_cases]}
    (tmp/'data.json').write_text(json.dumps(data))
    fake=tmp/'fake_godot'
    fake.write_text('''#!/usr/bin/env python3
import json,sys,os
from pathlib import Path
d=json.load(open(Path(__file__).with_name('data.json')))
if '--version' in sys.argv:
 print(d['version']);sys.exit(0)
script=Path(sys.argv[sys.argv.index('-s')+1]).stem
args=sys.argv[sys.argv.index('--')+1:]
case=next(c for c in d['cases'] if c['script']==script and c['args']==args)
print('Godot Engine vMOCK - orchestrator unit test only\\n')
print('\\n'.join(case['lines']))
if os.environ.get('MOCK_ERROR')=='1' and script=='ranks_test': print('ERROR: deliberate mock failure',file=sys.stderr)
''')
    fake.chmod(0o700)
    for error in [False,True]:
        out=tmp/('bad' if error else 'ok')
        env=dict(os.environ,MOCK_ERROR='1' if error else '0')
        p=subprocess.run([sys.executable,str(project/'tests/capture_canonical.py'),'--project',str(fake_project),'--godot',str(fake),'--out',str(out),'--source-commit','MOCK-ORCHESTRATOR-TEST-ONLY'],env=env,capture_output=True,text=True)
        run=json.load(open(out/'baseline_tests.json'))
        assert run['canonical_invocations']==17 and len(run['tests'])==18
        assert run['numeric_capture_complete']==(not error)
        assert p.returncode==(1 if error else 0)
        if not error:
            for key,case in baseline['tests'].items():
                for field in ['script','args','exit_code','lines','errors']:
                    assert case[field]==run['tests'][key][field],(key,field)
        else: assert run['tests']['ranks_test']['errors']==['ERROR: deliberate mock failure']
        print('MOCK orchestration:', 'fail-closed error' if error else '17 canonical + 1 supplemental exact records', 'PASS')
print('No mock artifacts retained or used as phase evidence.')

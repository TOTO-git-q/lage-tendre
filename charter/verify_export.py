"""Read-only acceptance against the standalone executable; owns/kills only its child PID."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import time
import urllib.request

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'dist/LAgeTendreCharter'
EVIDENCE=ROOT/'charter/evidence'

def main():
    env=os.environ.copy()
    env['APPDATA']=str(ROOT/'charter/runtime')
    log=EVIDENCE/'export_final.log'
    with log.open('wb') as stream:
        process=subprocess.Popen([str(OUT/'LAgeTendreCharter.exe'),'--headless','--audio-driver','Dummy','--','--silent'],cwd=OUT,env=env,stdout=stream,stderr=subprocess.STDOUT)
        try:
            port=None
            for _ in range(120):
                text=log.read_text(encoding='utf-8',errors='replace')
                match=re.search(r'CHARTER_READY.*mcp=(\d+)',text)
                if match:
                    port=int(match.group(1)); break
                if process.poll() is not None: raise RuntimeError(text)
                if 'SCRIPT ERROR' in text: raise RuntimeError(text)
                time.sleep(.1)
            assert port, 'Standalone MCP did not start'
            session=None
            def rpc(method,params=None):
                nonlocal session
                headers={'Content-Type':'application/json'}
                if session: headers['Mcp-Session-Id']=session
                body={'jsonrpc':'2.0','id':1,'method':method}
                if params is not None: body['params']=params
                req=urllib.request.Request(f'http://127.0.0.1:{port}/mcp',data=json.dumps(body).encode(),headers=headers)
                with urllib.request.urlopen(req,timeout=20) as response:
                    session=response.headers['Mcp-Session-Id']
                    return json.load(response)['result']
            rpc('initialize',{'protocolVersion':'2025-03-26','capabilities':{},'clientInfo':{'name':'export-test','version':'2'}})
            tools=rpc('tools/list')['tools']
            assert len(tools) >= 26 and len({t['description'] for t in tools}) == len(tools)
            def call(name,args=None):
                result=rpc('tools/call',{'name':name,'arguments':args or {}})
                assert not result.get('isError'), result
                return json.loads(result['content'][0]['text'])
            info=call('song_info'); notes=call('notes',{'from':'44.1','to':'45.1'})
            versions=call('versions')
            assert info['title'] == 'Original Demo' and info['chart_duration_seconds'] > 0, info
            assert not versions['enabled']
            receipt={'executable':str(OUT/'LAgeTendreCharter.exe'),'sha256':hashlib.sha256((OUT/'LAgeTendreCharter.exe').read_bytes()).hexdigest(),'tool_count':len(tools),'song_info':info,'bar_44_notes':notes,'versions':versions,'passed':True}
            (EVIDENCE/'export_acceptance.json').write_text(json.dumps(receipt,indent=2,ensure_ascii=False),encoding='utf-8')
            print('EXPORTED_ACCEPTANCE PASS: shipped demo and MCP tools, no implicit repository')
        finally:
            if process.poll() is None: process.terminate()
            process.wait(timeout=10)
    result=subprocess.run([str(OUT/'LAgeTendreCharter.exe'),'--audio-driver','Dummy','--position','-5000,-5000','--',f'--shots={ROOT / "charter/shots/exported"}'],cwd=OUT,env=env,capture_output=True,timeout=70)
    text=(result.stdout+result.stderr).decode('utf-8',errors='replace')
    (EVIDENCE/'export_shots.log').write_text(text,encoding='utf-8')
    assert result.returncode==0 and 'SCRIPT ERROR' not in text and 'CHARTER_SHOTS' in text,text
    print('EXPORTED_SCREENSHOTS PASS')

if __name__=='__main__': main()

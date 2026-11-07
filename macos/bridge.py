#!/usr/bin/env python3
"""Local-only integration. Fixed receiver allowlist; argv execution, never a shell.

No simulated telemetry. macOS display facts are added by the native app.
Credentials remain in Keychain. Widget snapshots never contain credentials.
"""
import base64
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import signal
import shutil
import socket
import ssl
import subprocess
import sys
import time
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET

ROOT = Path.home() / 'Library/Application Support/DDMM Connect'
SUN = ROOT / 'Sunshine'
STATE = ROOT / 'session.json'
MODES = ('sunshine', 'opendisplay', 'hdmi')
def installed_app(name):
    system=Path('/Applications')/name
    user=Path.home()/'Applications'/name
    return str(system if system.exists() else user)

APPS = {'sunshine': installed_app('Sunshine.app'), 'opendisplay': installed_app('OpenDisplay.app')}
IDS = {'sunshine': 'dev.lizardbyte.app.Sunshine', 'opendisplay': 'com.peetzweg.opensidecar.mac'}
RECEIVERS = {'sunshine': 'com.limelight', 'opendisplay': 'local.ddmm.opendisplay'}
SERVICE = 'local.ddmm.connect.sunshine'
TV_DEFAULT = '192.168.1.100'

def run(args, timeout=12, check=True):
    p = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=timeout)
    if check and p.returncode:
        # Do not echo argv: it may carry the generated Web UI password.
        raise RuntimeError((p.stderr or p.stdout or '操作失败')[-1000:].strip())
    return p.stdout.strip()

def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.tmp')
    with open(tmp, 'w') as f:
        os.chmod(tmp, 0o600)
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)

def load():
    try: return json.loads(STATE.read_text())
    except (OSError, ValueError): return {'mode':'sunshine','tv':TV_DEFAULT,'owned':False,'phase':'idle'}

def validate_tv(value):
    ip = ipaddress.ip_address(value)
    if ip.version != 4 or not ip.is_private or ip.is_loopback or ip.is_unspecified:
        raise ValueError('电视地址必须是局域网 IPv4 地址')
    return str(ip)

def adb_path():
    candidates = [str(ROOT/'Tools/platform-tools/adb'),shutil.which('adb'), str(Path.home()/'android-platform-tools/platform-tools/adb'),
                  str(Path.home()/'Library/Android/sdk/platform-tools/adb')]
    return next((p for p in candidates if p and Path(p).is_file()), None)

def adb(tv, args, timeout=10, check=True):
    path = adb_path()
    if not path: raise RuntimeError('未找到电视控制工具 adb')
    return run([path, '-s', validate_tv(tv)+':5555', *args], timeout, check)

def ensure_tv(tv):
    path = adb_path()
    if not path: raise RuntimeError('未找到电视控制工具 adb')
    run([path,'connect',validate_tv(tv)+':5555'], timeout=5, check=False)
    if adb(tv,['get-state'],check=False) != 'device':
        raise RuntimeError('电视控制未连接，请打开电视并确认调试授权')

def app_running(mode):
    # Match only exact executable paths, not names or other users' commands.
    path = APPS[mode]+'/Contents/MacOS/'+('Sunshine' if mode=='sunshine' else 'OpenDisplay')
    return any(line.strip().startswith(path) for line in run(['/bin/ps','-axo','command='],check=False).splitlines())

def quit_owned(mode, state):
    if state.get('owned') and mode in IDS and app_running(mode):
        executable=APPS[mode]+'/Contents/MacOS/'+('Sunshine' if mode=='sunshine' else 'OpenDisplay')
        for line in run(['/bin/ps','-axo','pid=,command='],check=False).splitlines():
            fields=line.strip().split(None,1)
            if len(fields)==2 and (fields[1]==executable or fields[1].startswith(executable+' ')):
                os.kill(int(fields[0]),signal.SIGTERM)
        deadline=time.monotonic()+5
        while app_running(mode) and time.monotonic()<deadline: time.sleep(.2)
        if app_running(mode): raise RuntimeError('上一接收会话尚未退出，未启动新方案')

def simple(url):
    if not Path(installed_app('SimpleDisplay.app')).is_dir():raise RuntimeError('SimpleDisplay 未安装')
    run(['/usr/bin/open',url])

def displays():
    status = Path('/tmp/simpledisplay-status.json')
    old = status.stat().st_mtime_ns if status.exists() else 0
    # Upstream suppresses identical URLs within one second.
    simple('simpledisplay://status?request='+str(time.time_ns()))
    for _ in range(25):
        if status.exists() and status.stat().st_mtime_ns != old:
            return json.loads(status.read_text())
        time.sleep(.08)
    raise RuntimeError('显示器状态读取超时')

def ensure_display():
    existing = [d for d in displays() if d.get('name') == 'DDMM-TV']
    if existing:
        if not existing[0].get('virtual'): raise RuntimeError('DDMM-TV 名称已被物理屏幕占用')
        return existing[0]['id']
    # SimpleDisplay dimensions are points: 1920x1080 HiDPI = 3840x2160 pixels.
    simple('simpledisplay://create?name=DDMM-TV&width=1920&height=1080&refresh=60&hidpi=true')
    for _ in range(15):
        for d in displays():
            if d.get('name') == 'DDMM-TV' and d.get('virtual'): return d['id']
        time.sleep(.2)
    raise RuntimeError('未能创建 DDMM-TV 扩展屏')

def remove_display(state):
    if not state.get('display_owned'): return
    for d in displays():
        if d.get('name')=='DDMM-TV' and d.get('virtual'):
            simple('simpledisplay://remove?id='+str(d['id']))

def keychain_password(create=False):
    p=run(['/usr/bin/security','find-generic-password','-s',SERVICE,'-a','ddmm','-w'],check=False)
    if not p and create:
        p=secrets.token_urlsafe(32)
        run(['/usr/bin/security','add-generic-password','-U','-s',SERVICE,'-a','ddmm','-w',p])
    return p

def api(path, payload=None):
    password=keychain_password()
    if not password: raise RuntimeError('Sunshine 管理凭据尚未初始化')
    headers={'Authorization':'Basic '+base64.b64encode(('ddmm:'+password).encode()).decode(), 'Content-Type':'application/json'}
    request=urllib.request.Request('https://127.0.0.1:47990'+path,
                                  data=json.dumps(payload).encode() if payload is not None else None,headers=headers)
    # Sunshine uses a self-signed cert. This exception is only for fixed loopback.
    with urllib.request.urlopen(request,context=ssl._create_unverified_context(),timeout=12) as response:
        return json.load(response)

def configure_sun(display_id, audio='mac'):
    SUN.mkdir(parents=True,exist_ok=True)
    config = {
        'sunshine_name':'DDMM-MacBook', 'output_name':str(display_id),
        'encoder':'videotoolbox', 'vt_software':'disabled','vt_realtime':'enabled',
        'upnp':'disabled','origin_web_ui_allowed':'pc','gamepad':'disabled',
        'file_apps':str(SUN/'apps.json'),'file_state':str(SUN/'sunshine-state.json'),
        'credentials_file':str(SUN/'credentials.json'),'log_path':str(SUN/'sunshine.log'),
        'stream_audio':'enabled' if audio=='tv' else 'disabled',
        'audio_sink':'BlackHole 2ch',
    }
    (SUN/'sunshine.conf').write_text(''.join(k+' = '+v+'\n' for k,v in config.items()))
    if not (SUN/'apps.json').exists():write_json(SUN/'apps.json',{'env':{},'apps':[{'name':'Desktop','image-path':'desktop.png'}]})
    if not (SUN/'credentials.json').exists():
        password=keychain_password(True)
        run([APPS['sunshine']+'/Contents/MacOS/Sunshine',str(SUN/'sunshine.conf'),'--creds','ddmm',password],timeout=15)
    os.chmod(SUN/'sunshine.conf',0o600)

def server_uuid():
    try:
        data=urllib.request.urlopen('http://127.0.0.1:47989/serverinfo?uniqueid=DDMM',timeout=3).read()
        return ET.fromstring(data).findtext('uniqueid') or ''
    except Exception:return ''

def launch_tv(state, pairing=False):
    args=['shell','am','start','-W','-n','local.extmonitor.tv/.ConnectActivity','--es','route',state['mode'],'--ez','launch','true']
    if state['mode']=='sunshine' and not pairing:
        uid=server_uuid()
        if uid:args+=['--es','host_uuid',uid,'--es','hostname','DDMM-MacBook']
    adb(state['tv'],args)

def stop(state):
    warnings=[]
    if state.get('owned') and state['mode'] in RECEIVERS:
        # Only terminate this session's receiver. Never touch unrelated TV apps.
        try:adb(state['tv'],['shell','am','force-stop',RECEIVERS[state['mode']]],check=False)
        except Exception:warnings.append('电视离线，未确认接收端退出')
        quit_owned(state['mode'],state)
        try:adb(state['tv'],['shell','am','start','-n','local.extmonitor.tv/.ConnectActivity'],check=False)
        except Exception:pass
    remove_display(state)
    state.update(owned=False,display_owned=False,phase='idle',error='；'.join(warnings))
    write_json(STATE,state)

def connect(state, mode, tv, audio='mac'):
    if mode not in MODES:raise ValueError('未知方案')
    if audio not in ('mac','tv'):raise ValueError('未知音频输出')
    if mode=='opendisplay' and audio=='tv':raise ValueError('OpenDisplay 当前版本不传音频，请选择 Sunshine 或 HDMI')
    if mode=='hdmi':
        stop(state);state.update(mode=mode,tv=tv,phase='hdmi');write_json(STATE,state);return
    if state.get('owned'):stop(state)
    if app_running(mode):raise RuntimeError('该串流应用已在运行，请先结束其现有会话')
    if not Path(APPS[mode]).is_dir():raise RuntimeError('对应 Mac 接收服务未安装')
    ensure_tv(tv)
    if not adb(tv,['shell','pm','path',RECEIVERS[mode]],check=False).startswith('package:'):raise RuntimeError('电视接收端未安装')
    state.update(mode=mode,tv=tv,audio=audio,phase='starting',error='',owned=True,started=time.time(),display_owned=False)
    write_json(STATE,state)
    try:
        if mode=='sunshine':
            before=any(d.get('name')=='DDMM-TV' for d in displays())
            display_id=ensure_display();state.update(display_owned=not before,display_id=display_id)
            write_json(STATE,state);configure_sun(display_id,audio)
            run(['/usr/bin/open','-g','-a',APPS[mode],'--args',str(SUN/'sunshine.conf')])
            for _ in range(40):
                if server_uuid():break
                time.sleep(.2)
            launch_tv(state, pairing=not state.get('paired',False))
        else:
            # The upstream -host/-port escape hatch is a documented LAN TCP path.
            logs=Path.home()/'Library/Logs/OpenDisplay/opendisplay.log'
            state['log_offset']=logs.stat().st_size if logs.exists() else 0
            write_json(STATE,state);launch_tv(state)
            run(['/usr/bin/open','-g','-a',APPS[mode],'--args','-host',tv,'-port','9000','-autostart','YES','-lowlatency','YES'])
        state['phase']='waiting';write_json(STATE,state)
    except Exception:
        # Best effort rollback, but preserve ownership when cleanup fails.
        try:stop(state)
        except Exception:pass
        raise

def tail(path, limit=65536, offset=0):
    try:
        with open(path,'rb') as f:
            size=f.seek(0,2);f.seek(max(offset if offset<=size else 0,size-limit));return f.read(limit).decode(errors='replace')
    except OSError:return ''

def parse_open_stats(text):
    for line in reversed(text.splitlines()):
        m=re.search(r'PHONE-STATS (\{.*\}) \|',line)
        if m:
            try:
                stamp=re.match(r'\[(\d\d):(\d\d):(\d\d\.\d+)\]',line)
                if not stamp:return {}
                h,mn,s=map(float,stamp.groups())
                now=time.localtime()
                age=(now.tm_hour*3600+now.tm_min*60+now.tm_sec-(h*3600+mn*60+s))%86400
                if age>12 and age<86399:return {}
                return json.loads(m.group(1))
            except ValueError:continue
    return {}

def status(state):
    result={'ok':True,'mode':state.get('mode','sunshine'),'phase':state.get('phase','idle'),
            'tv':state.get('tv',TV_DEFAULT),'owned':state.get('owned',False),
            'error':state.get('error',''),'updated':time.time(),'fps':None,'rtt':None,
            'bitrate':None,'e2e':None,'paired':state.get('paired',False),
            'dependencies':{k:Path(v).exists() for k,v in APPS.items()},'adb':bool(adb_path())}
    if not state.get('owned') or state['mode']=='hdmi':return result
    if not app_running(state['mode']):result.update(phase='error',error='Mac 串流服务已退出');return result
    try:foreground=adb(state['tv'],['shell','dumpsys','activity','activities'],timeout=5)
    except Exception:foreground='';result['tv_control']=False
    foreground='\n'.join(l for l in foreground.splitlines() if 'mResumedActivity' in l or 'topResumedActivity' in l)
    if state['mode']=='sunshine':
        log=tail(SUN/'sunshine.log')
        if 'com.limelight/.Game' in foreground and log.rfind('CLIENT CONNECTED')>log.rfind('CLIENT DISCONNECTED'):
            result['phase']='streaming'
        elif 'no screen capture permission' in log.lower() or ('permission' in log.lower() and ('denied' in log.lower() or 'not granted' in log.lower())):
            result.update(phase='permission',error='请在 macOS 中允许 Sunshine 屏幕录制')
        else:result['phase']='waiting'
    else:
        logfile=Path.home()/'Library/Logs/OpenDisplay/opendisplay.log'
        text=tail(logfile,offset=state.get('log_offset',0))
        captured=re.findall(r'capture started: \d+x\d+ display (\d+)',text)
        if captured:result['display_id']=int(captured[-1])
        stats=parse_open_stats(text)
        fresh=logfile.exists() and time.time()-logfile.stat().st_mtime<12
        # Receiver-generated render telemetry remains valid if the separate ADB
        # control connection drops while the LAN video connection stays alive.
        if stats and fresh:
            result.update(phase='streaming' if stats.get('fps',0)>0 else 'waiting',fps=stats.get('fps'),rtt=stats.get('rtt'),e2e=stats.get('e2e50'),bitrate=stats.get('mbps'))
            if stats.get('fps',0)==0 and 'permission missing' in text.lower():
                result.update(phase='permission',error='请在 macOS 中允许 OpenDisplay 屏幕录制')
        elif 'permission' in text.lower() and any(s in text.lower() for s in ('denied','not granted','permission missing')):
            result.update(phase='permission',error='请在 macOS 中允许 OpenDisplay 屏幕录制')
        else:result['phase']='waiting'
    return result

def dispatch(command, options):
    state=load();tv=validate_tv(options.get('tv',state.get('tv',TV_DEFAULT)))
    if command=='connect':connect(state,options.get('mode','sunshine'),tv,options.get('audio','mac'))
    elif command=='stop':stop(state)
    elif command=='pair':
        pin=str(options.get('pin',''))
        if not re.fullmatch(r'\d{4}',pin):raise ValueError('请输入电视上的四位配对码')
        requests=api('/api/pin').get('pairings',[])
        matches=[p for p in requests if p.get('address','').split(':')[-1]==tv or tv in p.get('address','')]
        if len(matches)!=1:raise RuntimeError('没有唯一匹配的电视配对请求，请在 Moonlight 中选择 DDMM-MacBook')
        reply=api('/api/pin',{'pairing_id':matches[0]['id'],'pin':pin,'name':'DDMM Sony TV'})
        if not reply.get('status'):raise RuntimeError('配对未完成，请重新获取电视配对码')
        state['paired']=True;write_json(STATE,state);launch_tv(state)
    elif command=='receiver':ensure_tv(tv);launch_tv(state,pairing=options.get('pairing',False))
    elif command=='status':pass
    else:raise ValueError('未知操作')
    return status(state)

def main():
    ROOT.mkdir(parents=True,exist_ok=True);os.chmod(ROOT,0o700)
    command=sys.argv[1] if len(sys.argv)>1 else 'status'
    options=json.loads(sys.argv[2]) if len(sys.argv)>2 else {}
    with open(ROOT/'command.lock','w') as lock:
        try:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            result=dispatch(command,options)
        except BlockingIOError:result={'ok':False,'error':'正在处理上一操作'}
        except Exception as e:result={'ok':False,'error':str(e)}
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':main()

#!/usr/bin/env python3
"""Install pinned, independent dependencies. No sudo, no shell interpolation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
import bridge

HERE=Path(__file__).resolve().parent
CACHE=bridge.ROOT/'Downloads'
TOOLS=bridge.ROOT/'Tools'
USER_APPS=Path.home()/'Applications'
LOCK=json.loads((HERE/'dependencies-lock.json').read_text())


def stage(message):
    bridge.write_json(bridge.ROOT/'setup-progress.json',{'message':message})


def dependency(name):
    return next(item for item in LOCK if item['name']==name)


def download(item):
    CACHE.mkdir(parents=True,exist_ok=True)
    target=CACHE/item['name']
    expected=item['digest'].removeprefix('sha256:')
    if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest()!=expected:
        stage('下载 '+item['name'])
        partial=target.with_suffix(target.suffix+'.part')
        bridge.run(['/usr/bin/curl','--fail','--location','--retry','2','--max-time','300','--silent','--show-error',item['url'],'-o',partial],timeout=310)
        if hashlib.sha256(partial.read_bytes()).hexdigest()!=expected:raise RuntimeError('下载校验失败：'+item['name'])
        os.replace(partial,target)
    return target


def app_path(name):
    return next((p for p in (Path('/Applications')/name,USER_APPS/name) if p.is_dir()),None)


def install_app(artifact,name):
    if app_path(name):return '已安装 '+name
    dmg=download(dependency(artifact));stage('安装 '+name)
    mounted=plistlib.loads(subprocess.check_output(['/usr/bin/hdiutil','attach',str(dmg),'-readonly','-nobrowse','-plist']))
    mounts=[Path(x['mount-point']) for x in mounted.get('system-entities',[]) if 'mount-point' in x]
    try:
        source=next((p/name for p in mounts if (p/name).is_dir()),None)
        if source is None:raise RuntimeError('安装包未包含 '+name)
        bridge.run(['/usr/bin/codesign','--verify','--deep','--strict',source])
        USER_APPS.mkdir(exist_ok=True)
        bridge.run(['/usr/bin/ditto',source,USER_APPS/name],timeout=120)
        bridge.run(['/usr/bin/codesign','--verify','--deep','--strict',USER_APPS/name])
        bridge.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-f',USER_APPS/name])
    finally:
        for mount in mounts:bridge.run(['/usr/bin/hdiutil','detach',mount],check=False)
    return '已安装 '+name


def ensure_adb():
    existing=bridge.adb_path()
    if existing:return existing
    archive=download(dependency('platform-tools_r37.0.2-darwin.zip'))
    TOOLS.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for member in z.infolist():
            if member.filename.startswith('/') or '..' in Path(member.filename).parts:raise RuntimeError('无效工具归档')
        z.extractall(TOOLS)
    for name in ('adb','fastboot'):
        (TOOLS/'platform-tools'/name).chmod(0o755)
    return str(TOOLS/'platform-tools/adb')


def install_apk(adb,tv,artifact,package):
    # Existing receivers keep their settings and sessions. Updates are explicit.
    if bridge.run([adb,'-s',tv+':5555','shell','pm','path',package],check=False).startswith('package:'):
        return '已安装 '+package
    apk=download(dependency(artifact));stage('安装电视接收端 '+package)
    bridge.run([adb,'-s',tv+':5555','install','--no-incremental','-r',apk],timeout=90)
    return '已安装 '+package


def install(mode,tv):
    if mode not in bridge.MODES:raise ValueError('未知方案')
    if mode=='hdmi':return {'ok':True,'message':'HDMI 无需串流软件，请接线后选择 HDMI','installed':[]}
    tv=bridge.validate_tv(tv);results=[]
    if mode=='sunshine':
        results.append(install_app('SimpleDisplay.dmg','SimpleDisplay.app'))
        results.append(install_app('Sunshine-macOS-arm64.dmg','Sunshine.app'))
    else:results.append(install_app('OpenDisplay.dmg','OpenDisplay.app'))
    adb=ensure_adb();stage('连接电视，请在电视上确认 ADB 授权')
    bridge.run([adb,'connect',tv+':5555'],timeout=15,check=False)
    if bridge.run([adb,'-s',tv+':5555','get-state'],check=False)!='device':
        raise RuntimeError('Mac 组件已安装。请在电视开启 ADB 调试并批准连接，再点击安装与检查。')
    results.append(install_apk(adb,tv,'eXTMonitor-TV-0.1.0.apk','local.extmonitor.tv'))
    if mode=='sunshine':results.append(install_apk(adb,tv,'app-nonRoot-release.apk','com.limelight'))
    else:results.append(install_apk(adb,tv,'DDMM-OpenDisplay-1.30.2-ddmm.1.apk','local.ddmm.opendisplay'))
    stage('安装检查完成')
    return {'ok':True,'message':'安装检查完成；首次使用请完成录屏授权与配对','installed':results}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--mode',choices=bridge.MODES,default='sunshine')
    parser.add_argument('--tv',default='')
    parser.add_argument('--plan',action='store_true')
    parser.add_argument('--audio-only',action='store_true')
    args=parser.parse_args()
    try:
        if args.plan:result={'ok':True,'mode':args.mode,'tv':args.tv,'dependencies':[x['name'] for x in LOCK]}
        elif args.audio_only:
            package=download(dependency('BlackHole2ch-0.7.1.pkg'))
            bridge.run(['/usr/sbin/spctl','--assess','--type','install',package])
            bridge.run(['/usr/bin/open',package])
            result={'ok':True,'message':'请在系统安装器中完成许可和管理员确认'}
        else:result=install(args.mode,args.tv)
    except Exception as error:result={'ok':False,'error':str(error)}
    print(json.dumps(result,ensure_ascii=False))
    return 0 if result['ok'] else 1

if __name__=='__main__':sys.exit(main())

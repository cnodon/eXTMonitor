import plistlib,sys
from pathlib import Path
app=Path(sys.argv[1]);ext=app/'Contents/PlugIns/DDMMWidget.appex'
base={'CFBundleDevelopmentRegion':'zh_CN','CFBundleShortVersionString':'0.1.0','CFBundleVersion':'1','LSMinimumSystemVersion':'14.0'}
main={**base,'CFBundleIdentifier':'local.ddmm.connect','CFBundleName':'eXTMonitor','CFBundleDisplayName':'eXTMonitor','CFBundleExecutable':'DDMMConnect','CFBundlePackageType':'APPL','LSUIElement':True,'NSHighResolutionCapable':True,'CFBundleURLTypes':[{'CFBundleURLName':'eXTMonitor','CFBundleURLSchemes':['ddmm-connect']}],'NSLocalNetworkUsageDescription':'连接局域网中的 Sony 电视。'}
widget={**base,'CFBundleIdentifier':'local.ddmm.connect.widget','CFBundleName':'DDMMWidget','CFBundleDisplayName':'eXTMonitor','CFBundleExecutable':'DDMMWidget','CFBundlePackageType':'XPC!','NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}
for path,value in [(app,main),(ext,widget)]:
 (path/'Contents/Info.plist').write_bytes(plistlib.dumps(value))

import AppKit
import SwiftUI

final class DesktopPanel:NSPanel {
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
}

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    let model=ConnectController()
    var desktop:NSPanel!
    var statusItem:NSStatusItem!
    func applicationDidFinishLaunching(_ notification:Notification){
        let area=NSScreen.screens.first(where:{screen in let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0;return CGDisplayIsBuiltin(id) != 0})?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        desktop=DesktopPanel(contentRect:NSRect(x:area.minX+24,y:area.maxY-620,width:380,height:380),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        desktop.title="eXTMonitor";desktop.isFloatingPanel=false;desktop.hidesOnDeactivate=false;desktop.isReleasedWhenClosed=false
        desktop.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)
        desktop.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]
        desktop.isOpaque=false;desktop.backgroundColor = .clear;desktop.hasShadow=true;desktop.isMovableByWindowBackground=true
        desktop.contentView=NSHostingView(rootView:ConnectView(model:model))
        desktop.setFrameAutosaveName("eXTMonitorSinglePanel");desktop.orderFrontRegardless()
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image=NSImage(systemSymbolName:"display.2",accessibilityDescription:"eXTMonitor");statusItem.button?.target=self;statusItem.button?.action=#selector(reveal)
    }
    @objc func reveal(){desktop?.orderFrontRegardless()}
    func application(_ application:NSApplication,open urls:[URL]){reveal();for url in urls{model.handle(url)}}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{reveal();return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
}
MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate()
    app.delegate=delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}

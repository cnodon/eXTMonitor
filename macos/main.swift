import AppKit
import SwiftUI

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    let model=ConnectController()
    var window:NSWindow!
    var statusItem:NSStatusItem!
    var desktop:NSPanel!
    func applicationDidFinishLaunching(_ notification:Notification){
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:470,height:390),styleMask:[.titled,.closable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="eXTMonitor";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isOpaque=false;window.backgroundColor = .clear;window.isMovableByWindowBackground=true;window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:ConnectView(model:model));window.center();window.setFrameAutosaveName("DDMMConnect")
        statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image=NSImage(systemSymbolName:"display.2",accessibilityDescription:"eXTMonitor");statusItem.button?.target=self;statusItem.button?.action=#selector(toggle)
        let area=NSScreen.screens.first(where:{screen in let id=(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0;return CGDisplayIsBuiltin(id) != 0})?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        desktop=NSPanel(contentRect:NSRect(x:area.minX+24,y:area.maxY-370,width:350,height:340),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        desktop.title="eXTMonitor Desktop";desktop.isFloatingPanel=false;desktop.hidesOnDeactivate=false;desktop.isReleasedWhenClosed=false
        desktop.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)
        desktop.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle]
        desktop.isOpaque=false;desktop.backgroundColor = .clear;desktop.hasShadow=true;desktop.isMovableByWindowBackground=true
        desktop.contentView=NSHostingView(rootView:DesktopCard(model:model,open:{[weak self] in self?.show()}))
        desktop.setFrameAutosaveName("eXTMonitorDesktop");desktop.orderFrontRegardless()
        show()
    }
    @objc func toggle(){if window.isVisible{window.orderOut(nil)}else{show()}}
    func show(){window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    func application(_ application:NSApplication,open urls:[URL]){show();for url in urls{model.handle(url)}}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{show();return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
}
MainActor.assumeIsolated {
    let app=NSApplication.shared
    let delegate=AppDelegate()
    app.delegate=delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}

import AppKit
import SwiftUI
import WidgetKit
import CoreGraphics

@MainActor final class ConnectController: ObservableObject {
    @Published var snapshot = DDMMShared.read()
    @Published var busy = false
    @Published var details = false
    @Published var comparison = false
    @Published var pin = ""
    @Published var tv = UserDefaults.standard.string(forKey: "tv") ?? "192.168.1.100"
    @Published var side = UserDefaults.standard.string(forKey: "side") ?? "right"
    @Published var audio = UserDefaults.standard.string(forKey:"audio") ?? "mac"
    @Published var history: [DisplaySnapshot] = []
    private var polling = false
    private var ticker: Timer?
    private var lastWidgetUpdate = Date.distantPast
    private var baseline: Set<CGDirectDisplayID> = []
    private var targetID: CGDirectDisplayID?
    private var hdmiOriginal: (CGDirectDisplayID, CGDisplayMode, CGPoint, CGDirectDisplayID)?

    init() {
        baseline = Set(NSScreen.screens.map(id))
        if let data = UserDefaults.standard.data(forKey: "history"), let values = try? JSONDecoder().decode([DisplaySnapshot].self, from: data) { history = values }
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        Task { await refresh() }
    }
    func id(_ screen: NSScreen) -> CGDirectDisplayID { (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0 }
    func call(_ command: String, values: [String:String] = [:]) async -> [String:Any] {
        guard let script = Bundle.main.url(forResource: "bridge", withExtension: "py") else { return ["ok":false,"error":"控制组件缺失"] }
        let arguments = [script.path,command,String(data:(try? JSONSerialization.data(withJSONObject: values)) ?? Data("{}".utf8),encoding:.utf8)!]
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process=Process(), output=Pipe(), errors=Pipe()
                process.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
                process.arguments=arguments;process.standardOutput=output;process.standardError=errors
                do {
                    try process.run()
                    let data=output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if let result=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] { continuation.resume(returning:result) }
                    else { continuation.resume(returning:["ok":false,"error":"控制组件未返回有效状态"]) }
                } catch { continuation.resume(returning:["ok":false,"error":error.localizedDescription]) }
            }
        }
    }
    private func metric(_ result:[String:Any], _ key:String, _ unit:String) -> String {
        guard let number=result[key] as? NSNumber else { return "—" }
        return String(format:"%.1f %@",number.doubleValue,unit)
    }
    private func targetScreen() -> NSScreen? {
        if snapshot.mode == "sunshine" { return NSScreen.screens.first { $0.localizedName == "DDMM-TV" } }
        if snapshot.mode == "hdmi" {
            return NSScreen.screens.first { let n=$0.localizedName.lowercased(); return CGDisplayIsBuiltin(id($0)) == 0 && (n.contains("sony") || n.contains("bravia")) }
        }
        if let targetID, let screen=NSScreen.screens.first(where:{ id($0)==targetID }) { return screen }
        return NSScreen.screens.first { let n=$0.localizedName.lowercased(); return !baseline.contains(id($0)) && (n.contains("bravia") || n.contains("opendisplay") || n.contains("ddmm")) }
    }
    private func apply(_ result:[String:Any]) {
        let previous=snapshot
        if result["ok"] as? Bool != true { snapshot.error=result["error"] as? String ?? "操作失败"; publish(previous); return }
        snapshot.mode=result["mode"] as? String ?? snapshot.mode
        snapshot.phase=result["phase"] as? String ?? "idle"
        snapshot.owned=result["owned"] as? Bool ?? false
        snapshot.tv=result["tv"] as? String ?? tv
        snapshot.error=result["error"] as? String ?? ""
        if snapshot.mode=="opendisplay",let display=result["display_id"] as? NSNumber{targetID=display.uint32Value}
        snapshot.frameRate=metric(result,"fps","fps");snapshot.rtt=metric(result,"rtt","ms");snapshot.e2e=metric(result,"e2e","ms")
        snapshot.bitrate=metric(result,"bitrate","Mbps");snapshot.resolution="—";snapshot.refreshRate="—";snapshot.sound="—"
        if let screen=targetScreen(),let mode=CGDisplayCopyDisplayMode(id(screen)) {
            targetID=id(screen)
            snapshot.resolution="\(mode.pixelWidth) × \(mode.pixelHeight)"
            if mode.refreshRate>0 { snapshot.refreshRate=String(format:"%.0f Hz",mode.refreshRate) }
            if snapshot.mode=="hdmi" { snapshot.phase=hdmiOriginal == nil ? "hdmi-ready" : "hdmi-active" }
        } else if snapshot.mode=="hdmi" { snapshot.phase="no-cable" }
        snapshot.status=["idle":"未连接","starting":"连接中","waiting":"等待接收端","streaming":"串流已建立","permission":"待授权","error":"连接异常","hdmi":"检查接线","hdmi-ready":"HDMI 已接入","hdmi-active":"扩展已开启","no-cable":"未接线"][snapshot.phase] ?? snapshot.phase
        if snapshot.mode=="opendisplay" { snapshot.sound="Mac" }
        if snapshot.isActive && audio=="tv" {
            if let device=snapshot.mode=="sunshine" ? AudioRouter.loopback : (snapshot.mode=="hdmi" ? AudioRouter.television:nil) {
                do{try AudioRouter.route(device)}catch{snapshot.error=error.localizedDescription}
            }
        } else { AudioRouter.restore() }
        if let current=AudioRouter.current {
            snapshot.sound=current.name=="BlackHole 2ch" ? "电视":current.name.contains("MacBook") ? "Mac":current.name
        }
        snapshot.updated=Date()
        publish(previous)
    }
    private func publish(_ previous:DisplaySnapshot) {
        DDMMShared.write(snapshot)
        if previous.status != snapshot.status || previous.mode != snapshot.mode || Date().timeIntervalSince(lastWidgetUpdate)>60 {
            WidgetCenter.shared.reloadTimelines(ofKind:DDMMShared.widgetKind);lastWidgetUpdate=Date()
        }
    }
    func refresh() async {
        guard !busy && !polling else{return};polling=true
        let result=await call("status");apply(result);polling=false
    }
    func connect(_ mode:String) async {
        guard !busy && ["sunshine","opendisplay","hdmi"].contains(mode) else{return}
        busy=true;defer{busy=false}
        if mode=="opendisplay" { audio="mac" }
        if mode=="sunshine" && audio=="tv" && AudioRouter.loopback==nil {snapshot.error="请先安装 BlackHole 2ch 音频组件";return}
        AudioRouter.restore()
        if snapshot.isActive { record() }
        restoreHDMI()
        baseline=Set(NSScreen.screens.map(id));targetID=nil
        UserDefaults.standard.set(tv,forKey:"tv")
        snapshot.error="";snapshot.status="连接中"
        let result=await call("connect",values:["mode":mode,"tv":tv,"audio":audio]);apply(result)
        if result["ok"] as? Bool == true {
            if mode=="hdmi" { configureHDMI() }
            else if let screen=targetScreen(){arrange(id(screen))}
        }
        DDMMShared.write(snapshot);WidgetCenter.shared.reloadTimelines(ofKind:DDMMShared.widgetKind)
    }
    func stop() async {
        guard !busy else{return};busy=true;defer{busy=false}
        record();AudioRouter.restore();restoreHDMI();apply(await call("stop"));targetID=nil
    }
    func changeAudio(_ value:String) async {
        guard !busy else{return}
        audio=value;UserDefaults.standard.set(value,forKey:"audio")
        if value=="mac"{AudioRouter.restore()}
        if snapshot.owned || snapshot.phase=="hdmi-active"{await connect(snapshot.mode)}
    }
    func pair() async {
        guard !busy else{return};busy=true;defer{busy=false}
        apply(await call("pair",values:["pin":pin,"tv":tv]));pin=""
    }
    func openReceiver(pairing:Bool=false) async {
        guard !busy else{return};busy=true;defer{busy=false}
        // Pairing is launched separately with the generic receiver view.
        apply(await call("receiver",values:["tv":tv,"pairing":pairing ? "yes":""]))
    }
    func arrange(_ target:CGDirectDisplayID) {
        let others=NSScreen.screens.filter{id($0) != target}.map{CGDisplayBounds(id($0))}
        let x=side=="right" ? (others.map(\.maxX).max() ?? 0) : (others.map(\.minX).min() ?? 0)-CGDisplayBounds(target).width
        var config:CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success,let config else{return}
        CGConfigureDisplayMirrorOfDisplay(config,target,kCGNullDirectDisplay)
        CGConfigureDisplayOrigin(config,target,Int32(x),0)
        CGCompleteDisplayConfiguration(config,.forSession)
    }
    func changeSide(_ value:String) {
        side=value;UserDefaults.standard.set(side,forKey:"side")
        if let screen=targetScreen(){arrange(id(screen))}
    }
    private func configureHDMI() {
        guard let screen=targetScreen() else{snapshot.status="未接线";snapshot.phase="no-cable";return}
        let display=id(screen)
        guard let current=CGDisplayCopyDisplayMode(display), let modes=CGDisplayCopyAllDisplayModes(display,nil) as? [CGDisplayMode],let mode=modes.first(where:{$0.pixelWidth==3840 && $0.pixelHeight==2160 && abs($0.refreshRate-60)<1}) else {snapshot.error="该输入未提供 4K60 模式";return}
        hdmiOriginal=(display,current,CGDisplayBounds(display).origin,CGDisplayMirrorsDisplay(display))
        guard CGDisplaySetDisplayMode(display,mode,nil) == .success else{snapshot.error="显示模式切换失败";hdmiOriginal=nil;return}
        arrange(display);snapshot.phase="hdmi-active";snapshot.status="扩展已开启";snapshot.resolution="3840 × 2160";snapshot.refreshRate="60 Hz"
    }
    private func restoreHDMI() {
        guard let (display,mode,origin,mirror)=hdmiOriginal else{return};hdmiOriginal=nil
        guard NSScreen.screens.contains(where:{id($0)==display}) else{return}
        CGDisplaySetDisplayMode(display,mode,nil)
        var config:CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success,let config{CGConfigureDisplayMirrorOfDisplay(config,display,mirror);CGConfigureDisplayOrigin(config,display,Int32(origin.x),Int32(origin.y));CGCompleteDisplayConfiguration(config,.forSession)}
    }
    private func record() {
        guard snapshot.isActive else{return}
        history.insert(snapshot,at:0);history=Array(history.prefix(20))
        if let data=try? JSONEncoder().encode(history){UserDefaults.standard.set(data,forKey:"history")}
    }
    func handle(_ url:URL) {
        guard url.scheme=="ddmm-connect" else{return}
        let mode=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems?.first(where:{$0.name=="mode"})?.value ?? "sunshine"
        switch url.host {
        case "connect":Task{await connect(mode)}
        case "stop":Task{await stop()}
        case "settings":details=true
        default:break
        }
    }
}

struct Frost: NSViewRepresentable {
    func makeNSView(context:Context)->NSVisualEffectView {let v=NSVisualEffectView();v.material = .hudWindow;v.blendingMode = .behindWindow;v.state = .active;v.appearance=NSAppearance(named:.darkAqua);return v}
    func updateNSView(_ nsView:NSVisualEffectView,context:Context){}
}

struct ConnectView: View {
    @ObservedObject var model:ConnectController
    private let red=Color(red:0.94,green:0.29,blue:0.42)
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            HStack(alignment:.top){VStack(alignment:.leading,spacing:6){Text("客厅电视").font(.title2.weight(.semibold));Text("SONY XR-75X95EK · 75″").font(.caption).foregroundStyle(.secondary)};Spacer();HStack(spacing:5){Circle().fill(model.snapshot.isActive ? Color.green:Color.gray).frame(width:5,height:5);Text(model.snapshot.status).font(.caption)};Button{model.details.toggle()}label:{Image(systemName:"slider.horizontal.3")}.buttonStyle(.borderless).accessibilityLabel("连接设置")}
            HStack(spacing:4){ForEach([("sunshine","Sunshine"),("opendisplay","OpenDisplay"),("hdmi","HDMI")],id:\.0){m in Button{Task{await model.connect(m.0)}}label:{Text(m.1).font(.caption).frame(maxWidth:.infinity).padding(.vertical,9).background(model.snapshot.mode==m.0 ? Color.white.opacity(0.14):.clear,in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain).disabled(model.busy)}}.padding(4).background(.black.opacity(0.18),in:RoundedRectangle(cornerRadius:12))
            HStack{Text(model.snapshot.mode=="hdmi" ? "HDMI 直连":"局域网 · \(model.snapshot.tv)");Spacer();Text("目标 4K60 · SDR")}.font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),alignment:.leading),count:3),alignment:.leading,spacing:20){
                metric("桌面分辨率",model.snapshot.resolution)
                metric(model.snapshot.mode=="hdmi" ? "刷新率":"解码输出帧率",model.snapshot.mode=="hdmi" ? model.snapshot.refreshRate:model.snapshot.frameRate)
                metric("网络往返",model.snapshot.mode=="hdmi" ? "不适用":model.snapshot.rtt)
                metric("视频码率",model.snapshot.mode=="hdmi" ? "不适用":model.snapshot.bitrate)
                metric("声音输出",model.snapshot.sound)
                metric("屏幕位置",model.side=="right" ? "右侧":"左侧")
            }
            if model.snapshot.mode=="opendisplay"{Text("Android Beta · 声音留在 Mac").font(.caption).foregroundStyle(.secondary)}
            HStack{Text("音频输出").font(.caption).foregroundStyle(.secondary);Picker("音频输出",selection:Binding(get:{model.audio},set:{value in Task{await model.changeAudio(value)}})){Text("Mac").tag("mac");Text("电视").tag("tv").disabled(model.snapshot.mode=="opendisplay")}.labelsHidden().pickerStyle(.segmented).disabled(model.busy)}
            if model.audio=="tv" && model.snapshot.mode=="sunshine" && AudioRouter.loopback==nil{Button("安装电视音频组件"){NSWorkspace.shared.open(URL(string:"https://existential.audio/blackhole/")!)}.font(.caption)}
            if !model.snapshot.error.isEmpty{Text(model.snapshot.error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)}
            Divider()
            HStack{VStack(alignment:.leading,spacing:5){Text(model.snapshot.updated,style:.time).font(.caption2).foregroundStyle(.secondary);Button("方案记录"){model.comparison.toggle()}.font(.caption).buttonStyle(.borderless)};Spacer();if model.busy{ProgressView().controlSize(.small)};Button(model.snapshot.owned || model.snapshot.phase=="hdmi-active" ? "结束扩展":"开启扩展"){Task{if model.snapshot.owned || model.snapshot.phase=="hdmi-active"{await model.stop()}else{await model.connect(model.snapshot.mode)}}}.buttonStyle(.borderedProminent).tint(model.snapshot.isActive ? .gray:red).disabled(model.busy)}
            if model.details{settings}
            if model.comparison{comparison}
        }.padding(24).frame(width:470).background(Frost()).background(Color.black.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius:24)).overlay(RoundedRectangle(cornerRadius:24).strokeBorder(.white.opacity(0.15))).preferredColorScheme(.dark)
    }
    func metric(_ title:String,_ value:String)->some View{VStack(alignment:.leading,spacing:7){Text(title).font(.caption2).foregroundStyle(.secondary);Text(value).font(.system(size:16,weight:.medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)}}
    var settings:some View {
        VStack(alignment:.leading,spacing:12){Divider();HStack{Text("电视 IP");TextField("192.168.1.100",text:$model.tv).textFieldStyle(.roundedBorder)}
            Picker("屏幕位置",selection:Binding(get:{model.side},set:{model.changeSide($0)})){Text("左侧").tag("left");Text("右侧").tag("right")}.pickerStyle(.segmented)
            if model.snapshot.mode=="sunshine" {HStack{TextField("电视配对码",text:$model.pin).textFieldStyle(.roundedBorder);Button("配对"){Task{await model.pair()}}.disabled(model.busy || model.pin.count != 4)};Button("打开 Moonlight 配对页面"){Task{await model.openReceiver(pairing:true)}}}
            HStack{Button("录制权限"){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)};Button("显示设置"){NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Displays-Settings.extension")!)};Spacer()}
            HStack{Text("采集到解码 P50");Spacer();Text(model.snapshot.e2e)}.foregroundStyle(.secondary)
            HStack{Text("桌面刷新率");Spacer();Text(model.snapshot.refreshRate)}.foregroundStyle(.secondary)
            HStack{Text("eXTMonitor · MIT");Spacer();Button("开源声明"){let alert=NSAlert();alert.messageText="eXTMonitor";alert.informativeText="自研控制面板、Widget 和电视入口：MIT License。\nOpenDisplay 电视适配：GPL-3.0，保留原项目版权。\nSunshine、Moonlight、SimpleDisplay、BlackHole 独立安装，遵循各自许可证。\nhttps://github.com/cnodon/eXTMonitor";alert.runModal()}}
            Text("— 表示未采集；网络往返不是完整操作延迟。").font(.caption2).foregroundStyle(.secondary)
        }.font(.caption)
    }
    var comparison:some View {VStack(alignment:.leading,spacing:10){Divider();if model.history.isEmpty{Text("暂无会话记录").font(.caption).foregroundStyle(.secondary)};ForEach(Array(model.history.prefix(6).enumerated()),id:\.offset){_,s in HStack{Text(s.schemeName);Spacer();Text(s.mode=="hdmi" ? s.refreshRate:s.frameRate);Text(s.rtt)}.font(.caption)};Text("会话快照 · 不同方案的统计口径可能不同").font(.caption2).foregroundStyle(.secondary)}}
}

struct DesktopCard:View {
    @ObservedObject var model:ConnectController
    let open:()->Void
    var body:some View {
        VStack(alignment:.leading,spacing:14){
            HStack{VStack(alignment:.leading,spacing:4){Text("eXTMonitor").font(.headline);Text("SONY XR-75X95EK").font(.caption2).foregroundStyle(.secondary)};Spacer();Button(action:open){Image(systemName:"slider.horizontal.3")}.buttonStyle(.plain).accessibilityLabel("打开控制面板")}
            HStack{Circle().fill(model.snapshot.isActive ? Color.green:Color.gray).frame(width:5,height:5);Text(model.snapshot.stale ? "状态待刷新":model.snapshot.status);Spacer();Text(model.snapshot.mode=="hdmi" ? "HDMI":model.snapshot.tv)}.font(.caption2).foregroundStyle(.secondary)
            HStack(spacing:4){ForEach([("sunshine","Sunshine"),("opendisplay","OpenDisplay"),("hdmi","HDMI")],id:\.0){m in Button{Task{await model.connect(m.0)}}label:{Text(m.1).font(.caption2).frame(maxWidth:.infinity).padding(.vertical,7).background(model.snapshot.mode==m.0 ? Color.white.opacity(0.14):.clear,in:RoundedRectangle(cornerRadius:6))}.buttonStyle(.plain).disabled(model.busy)}}
            HStack{metric("桌面分辨率",model.snapshot.resolution);Spacer();metric(model.snapshot.mode=="hdmi" ? "刷新率":"解码帧率",model.snapshot.mode=="hdmi" ? model.snapshot.refreshRate:model.snapshot.frameRate)}
            HStack{metric("网络往返",model.snapshot.mode=="hdmi" ? "—":model.snapshot.rtt);Spacer();metric("音频输出",model.snapshot.sound)}
            HStack{Text(model.snapshot.updated,style:.time).font(.caption2).foregroundStyle(.secondary);Spacer();Button(model.snapshot.owned ? "结束扩展":"开启扩展"){Task{if model.snapshot.owned{await model.stop()}else{await model.connect(model.snapshot.mode)}}}.buttonStyle(.borderedProminent).tint(Color(red:0.8,green:0.16,blue:0.3)).disabled(model.busy)}
        }.padding(20).frame(width:350).background(Frost()).clipShape(RoundedRectangle(cornerRadius:22)).overlay(RoundedRectangle(cornerRadius:22).strokeBorder(.white.opacity(0.12))).preferredColorScheme(.dark)
    }
    func metric(_ title:String,_ value:String)->some View{VStack(alignment:.leading,spacing:6){Text(title).font(.caption2).foregroundStyle(.secondary);Text(value).font(.system(size:16,weight:.medium)).monospacedDigit()}}
}

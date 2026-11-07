import WidgetKit
import SwiftUI

struct DDMMEntry:TimelineEntry{let date:Date;let snapshot:DisplaySnapshot}
struct DDMMProvider:TimelineProvider {
    func placeholder(in context:Context)->DDMMEntry{DDMMEntry(date:Date(),snapshot:DisplaySnapshot())}
    func getSnapshot(in context:Context,completion:@escaping(DDMMEntry)->Void){completion(DDMMEntry(date:Date(),snapshot:DDMMShared.read()))}
    func getTimeline(in context:Context,completion:@escaping(Timeline<DDMMEntry>)->Void){let date=Date();completion(Timeline(entries:[DDMMEntry(date:date,snapshot:DDMMShared.read())],policy:.after(date.addingTimeInterval(60))))}
}
struct DDMMWidgetView:View {
    let entry:DDMMEntry
    @Environment(\.widgetFamily) var family
    var s:DisplaySnapshot{entry.snapshot}
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            HStack{VStack(alignment:.leading,spacing:4){Text("客厅电视").font(.headline);Text("SONY XR-75X95EK · 75″").font(.caption2).foregroundStyle(.secondary)};Spacer();Link(destination:DDMMShared.link("settings")){Image(systemName:"slider.horizontal.3")}}
            HStack{Text(s.stale ? "状态待刷新":s.status);Spacer();Text(s.mode=="hdmi" ? "HDMI":s.tv)}.font(.caption2).foregroundStyle(.secondary)
            HStack(spacing:6){ForEach([("sunshine","Sunshine"),("opendisplay","OpenDisplay"),("hdmi","HDMI")],id:\.0){m in Link(destination:DDMMShared.link("connect",mode:m.0)){Text(m.1).font(.caption2).frame(maxWidth:.infinity).padding(.vertical,6).background(s.mode==m.0 ? Color.primary.opacity(0.13):Color.clear,in:RoundedRectangle(cornerRadius:7))}}}
            if family == .systemLarge {
                LazyVGrid(columns:[GridItem(.flexible(),alignment:.leading),GridItem(.flexible(),alignment:.leading)],alignment:.leading,spacing:14){metric("桌面分辨率",s.resolution);metric(s.mode=="hdmi" ? "刷新率":"解码帧率",s.mode=="hdmi" ? s.refreshRate:s.frameRate);metric("网络往返",s.mode=="hdmi" ? "不适用":s.rtt);metric("声音输出",s.sound)}
            } else {HStack{Text(s.resolution);Spacer();Text(s.mode=="hdmi" ? s.refreshRate:s.frameRate)}.font(.caption)}
            Spacer(minLength:0)
            HStack{if s.updated != .distantPast{Text(s.updated,style:.time).font(.caption2).foregroundStyle(.secondary)};Spacer();Link(destination:DDMMShared.link(s.owned ? "stop":"connect",mode:s.mode)){Text(s.owned ? "结束扩展":"开启扩展").font(.caption.weight(.medium)).padding(.horizontal,12).padding(.vertical,8).background(Color(red:0.8,green:0.16,blue:0.3),in:RoundedRectangle(cornerRadius:9)).foregroundStyle(.white)}}
        }.containerBackground(.ultraThinMaterial,for:.widget)
    }
    func metric(_ label:String,_ value:String)->some View{VStack(alignment:.leading,spacing:5){Text(label).font(.caption2).foregroundStyle(.secondary);Text(value).font(.callout).monospacedDigit()}}
}
@main struct DDMMWidget:Widget {
    var body:some WidgetConfiguration{StaticConfiguration(kind:DDMMShared.widgetKind,provider:DDMMProvider()){DDMMWidgetView(entry:$0)}.configurationDisplayName("eXTMonitor").description("电视扩展屏").supportedFamilies([.systemMedium,.systemLarge])}
}

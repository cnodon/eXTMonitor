// Local moving pattern for capture/decoder verification; exits after 35 seconds.
import AppKit
final class Pattern:NSView {
    var tick=0
    override func draw(_ rect:NSRect) {
        NSColor(calibratedWhite:0.035,alpha:1).setFill();bounds.fill()
        for i in 0..<14 {
            let x=CGFloat((tick*8+i*149)%Int(bounds.width+80))-80
            NSColor(calibratedHue:CGFloat(i)/14,saturation:0.7,brightness:0.8,alpha:1).setFill()
            NSBezierPath(roundedRect:NSRect(x:x,y:80+CGFloat(i%5)*130,width:55,height:420),xRadius:14,yRadius:14).fill()
        }
        let text="DDMM · 4K60 motion test · frame \(tick)"
        text.draw(at:NSPoint(x:60,y:bounds.height-110),withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:34,weight:.medium),.foregroundColor:NSColor.white])
    }
}
let app=NSApplication.shared
app.setActivationPolicy(.accessory)
guard let display=NSScreen.screens.first(where:{$0.localizedName=="DDMM-TV" || $0.localizedName.contains("OpenDisplay") || $0.localizedName.contains("Android") || $0.localizedName.contains("SONY")}) else {fatalError("No DDMM test display")}
let window=NSWindow(contentRect:display.frame,styleMask:.borderless,backing:.buffered,defer:false)
let view=Pattern(frame:NSRect(origin:.zero,size:display.frame.size));window.contentView=view;window.orderFrontRegardless()
var count=0
let timer=Timer.scheduledTimer(withTimeInterval:1/60,repeats:true){_ in count+=1;view.tick=count;view.needsDisplay=true}
Timer.scheduledTimer(withTimeInterval:35,repeats:false){_ in timer.invalidate();app.terminate(nil)}
app.run()

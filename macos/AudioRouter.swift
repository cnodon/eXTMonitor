import Foundation
import CoreAudio

struct AudioDevice {
    let id:AudioDeviceID
    let uid:String
    let name:String
}
enum AudioRouter {
    static func address(_ selector:AudioObjectPropertySelector,_ scope:AudioObjectPropertyScope=kAudioObjectPropertyScopeGlobal)->AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)
    }
    static func string(_ id:AudioDeviceID,_ key:AudioObjectPropertySelector)->String {
        var a=address(key),size=UInt32(MemoryLayout<Unmanaged<CFString>?>.size);var result:Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id,&a,0,nil,&size,&result)==noErr else{return ""}
        return result?.takeUnretainedValue() as String? ?? ""
    }
    static var devices:[AudioDevice] {
        var a=address(kAudioHardwarePropertyDevices),size:UInt32=0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size)==noErr else{return []}
        var ids=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&ids)==noErr else{return []}
        return ids.compactMap { id in
            var streams=address(kAudioDevicePropertyStreams,kAudioDevicePropertyScopeOutput),bytes:UInt32=0
            guard AudioObjectGetPropertyDataSize(id,&streams,0,nil,&bytes)==noErr,bytes>0 else{return nil}
            return AudioDevice(id:id,uid:string(id,kAudioDevicePropertyDeviceUID),name:string(id,kAudioObjectPropertyName))
        }
    }
    static var current:AudioDevice? {
        var a=address(kAudioHardwarePropertyDefaultOutputDevice),id:AudioDeviceID=0,size=UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,&id)==noErr else{return nil}
        return devices.first{$0.id==id}
    }
    static var loopback:AudioDevice?{devices.first{$0.name=="BlackHole 2ch"}}
    static var television:AudioDevice?{devices.first{let n=$0.name.lowercased();return n.contains("sony") || n.contains("bravia")}}
    static func route(_ device:AudioDevice) throws {
        if current?.uid==device.uid{return}
        let defaults=UserDefaults.standard
        if defaults.string(forKey:"audioOriginalUID")==nil,let original=current{defaults.set(original.uid,forKey:"audioOriginalUID")}
        var a=address(kAudioHardwarePropertyDefaultOutputDevice),id=device.id
        let result=AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,UInt32(MemoryLayout<AudioDeviceID>.size),&id)
        guard result==noErr else{throw NSError(domain:"DDMMAudio",code:Int(result),userInfo:[NSLocalizedDescriptionKey:"音频输出切换失败"])}
        defaults.set(device.uid,forKey:"audioOwnedUID")
    }
    static func restore() {
        let defaults=UserDefaults.standard
        guard let original=defaults.string(forKey:"audioOriginalUID") else{return}
        // If the user selected another output meanwhile, preserve that choice.
        if current?.uid==defaults.string(forKey:"audioOwnedUID"),let device=devices.first(where:{$0.uid==original}) {
            var a=address(kAudioHardwarePropertyDefaultOutputDevice),id=device.id
            guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,UInt32(MemoryLayout<AudioDeviceID>.size),&id)==noErr else{return}
        }
        defaults.removeObject(forKey:"audioOriginalUID");defaults.removeObject(forKey:"audioOwnedUID")
    }
}

import Foundation

enum DDMMShared {
    static let group = "9ZF5W6983F.local.ddmm.connect"
    static let widgetKind = "DDMMDisplayWidget"
    static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("display-snapshot.json")
    }
    static func read() -> DisplaySnapshot {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(DisplaySnapshot.self, from: data) else { return DisplaySnapshot() }
        return value
    }
    static func write(_ value: DisplaySnapshot) {
        guard let url = snapshotURL, let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func link(_ action: String, mode: String = "sunshine") -> URL {
        URL(string: "ddmm-connect://\(action)?mode=\(mode)")!
    }
}

struct DisplaySnapshot: Codable {
    var mode = "sunshine"
    var status = "未连接"
    var phase = "idle"
    var tv = "192.168.1.100"
    var resolution = "—"
    var frameRate = "—"
    var refreshRate = "—"
    var rtt = "—"
    var bitrate = "—"
    var sound = "—"
    var e2e = "—"
    var error = ""
    var updated = Date.distantPast
    var owned = false
    var stale: Bool { Date().timeIntervalSince(updated) > 90 }
    var isActive: Bool { phase == "streaming" || phase == "hdmi-active" }
    var schemeName: String { ["sunshine":"Sunshine","opendisplay":"OpenDisplay","hdmi":"HDMI"][mode] ?? mode }
}

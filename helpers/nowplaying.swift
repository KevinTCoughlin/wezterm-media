// SPDX-License-Identifier: MIT
// Query system-wide Now Playing info via Apple's private MediaRemote framework.
//
// Usage:
//   nowplaying
//       Print one "title|artist|playing|bundle_id" line (or an empty line) and exit.
//   nowplaying --watch OUTPUT HEARTBEAT [INTERVAL]
//       Stay running and rewrite OUTPUT every INTERVAL seconds (default 1) with
//       "<unix time>\n<line>\n". Exits once HEARTBEAT has not been touched for
//       IDLE_TIMEOUT seconds, so it goes away when WezTerm does. Only one
//       watcher per OUTPUT runs at a time (flock on OUTPUT.lock).
//
// Watch mode exists because macOS 26 only allows MediaRemote from the
// interpreted script, and interpreting it on every status tick is expensive.

import Foundation
import Darwin

typealias GetNowPlayingInfo = @convention(c) (
    DispatchQueue,
    @escaping @convention(block) (CFDictionary?) -> Void
) -> Void

let idleTimeout: TimeInterval = 30

final class QueryResult {
    var line = ""
    var completed = false
}

func loadGetter() -> GetNowPlayingInfo? {
    // The handle stays open for the life of the process.
    guard
        let handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ),
        let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
    else {
        return nil
    }
    return unsafeBitCast(symbol, to: GetNowPlayingInfo.self)
}

func query(_ getNowPlayingInfo: GetNowPlayingInfo) -> String {
    let result = QueryResult()
    getNowPlayingInfo(DispatchQueue.main) { dictionary in
        defer { result.completed = true }
        guard
            let dictionary,
            let info = dictionary as NSDictionary as? [String: Any],
            let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String,
            !title.isEmpty
        else {
            return
        }

        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let bundleID = info["kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"] as? String ?? ""
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        let clean = { (value: String) in
            value.replacingOccurrences(of: "|", with: "-")
                .replacingOccurrences(of: "\n", with: " ")
        }
        result.line = "\(clean(title))|\(clean(artist))|\(rate > 0)|\(bundleID)"
    }

    let deadline = Date().addingTimeInterval(0.5)
    while !result.completed && Date() < deadline {
        CFRunLoopRunInMode(.defaultMode, 0.01, true)
    }
    return result.line
}

func modificationDate(_ path: String) -> Date? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return attributes?[.modificationDate] as? Date
}

func watch(output: String, heartbeat: String, interval: TimeInterval) -> Never {
    let lockFD = open(output + ".lock", O_CREAT | O_RDWR, 0o600)
    guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else {
        exit(0)  // another watcher already owns this output
    }

    if modificationDate(heartbeat) == nil {
        FileManager.default.createFile(atPath: heartbeat, contents: nil)
    }

    let getter = loadGetter()
    let outputURL = URL(fileURLWithPath: output)
    while true {
        guard
            let beat = modificationDate(heartbeat),
            Date().timeIntervalSince(beat) < idleTimeout
        else {
            break
        }

        let line = getter.map(query) ?? ""
        let payload = "\(Int(Date().timeIntervalSince1970))\n\(line)\n"
        try? payload.write(to: outputURL, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: interval)
    }
    try? FileManager.default.removeItem(at: outputURL)
    exit(0)
}

let arguments = CommandLine.arguments
if arguments.count >= 4, arguments[1] == "--watch" {
    let interval = arguments.count > 4 ? Double(arguments[4]) ?? 1 : 1
    watch(output: arguments[2], heartbeat: arguments[3], interval: max(0.25, interval))
}

print(loadGetter().map(query) ?? "")

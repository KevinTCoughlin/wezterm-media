// SPDX-License-Identifier: MIT
// Query system-wide Now Playing info via Apple's private MediaRemote framework.

import Foundation
import Darwin

guard let handle = dlopen(
    "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
    RTLD_NOW
) else {
    print("")
    exit(0)
}
defer { dlclose(handle) }

typealias GetNowPlayingInfo = @convention(c) (
    DispatchQueue,
    @escaping @convention(block) (CFDictionary?) -> Void
) -> Void

guard let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
    print("")
    exit(0)
}

let getNowPlayingInfo = unsafeBitCast(symbol, to: GetNowPlayingInfo.self)
var result = ""
var completed = false

getNowPlayingInfo(DispatchQueue.main) { dictionary in
    defer { completed = true }
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
    let safeTitle = title.replacingOccurrences(of: "|", with: "-")
    let safeArtist = artist.replacingOccurrences(of: "|", with: "-")
    result = "\(safeTitle)|\(safeArtist)|\(rate > 0)|\(bundleID)"
}

let deadline = Date().addingTimeInterval(0.5)
while !completed && Date() < deadline {
    CFRunLoopRunInMode(.defaultMode, 0.01, true)
}

print(result)

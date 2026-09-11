import AppKit
import Foundation
import SyncCore
import SystemConfiguration

let center = URL(string: ProcessInfo.processInfo.environment["TAILCLIP_CENTER"] ?? "https://<center-url>")!
// The Sharing-pane hostname: ASCII, unlike the computer name, so it survives an HTTP header.
let device = SCDynamicStoreCopyLocalHostName(nil) as String? ?? "unknown-mac"
let pasteboard = NSPasteboard.general
let ownType = NSPasteboard.PasteboardType(ClipDecision.ownType)
var lastChangeCount = pasteboard.changeCount
var lastSeen: Clip?

func log(_ message: String) { FileHandle.standardError.write(Data("\(Date()) \(message)\n".utf8)) }

func snapshot() -> PasteboardSnapshot {
    let types = Set((pasteboard.types ?? []).map(\.rawValue))
    let png = pasteboard.data(forType: .png)
        ?? pasteboard.data(forType: .tiff).flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
    return PasteboardSnapshot(types: types, text: pasteboard.string(forType: .string), png: png)
}

func write(_ clip: Clip) {
    pasteboard.clearContents()
    pasteboard.setData(Data(), forType: ownType)
    switch clip {
    case .text(let string): pasteboard.setString(string, forType: .string)
    case .png(let data): pasteboard.setData(data, forType: .png)
    }
    lastChangeCount = pasteboard.changeCount
    lastSeen = clip
}

func send(_ clip: Clip) {
    var request = URLRequest(url: center.appending(path: "clip"))
    request.httpMethod = "POST"
    request.setValue(clip.contentType, forHTTPHeaderField: "Content-Type")
    request.setValue(device, forHTTPHeaderField: "X-Device")
    request.httpBody = clip.body
    URLSession.shared.dataTask(with: request) { _, response, error in
        if let error { log("send failed: \(error.localizedDescription)") }
        else if let status = (response as? HTTPURLResponse)?.statusCode, status != 204 { log("send refused: \(status)") }
    }.resume()
}

func pollPasteboard() {
    guard pasteboard.changeCount != lastChangeCount else { return }
    lastChangeCount = pasteboard.changeCount
    guard let clip = ClipDecision.clipToSend(from: snapshot(), lastSeen: lastSeen) else { return }
    lastSeen = clip
    send(clip)
}

func fetchLatest() {
    URLSession.shared.dataTask(with: center.appending(path: "clip")) { data, response, error in
        guard let data, let response = response as? HTTPURLResponse, error == nil else { return log("fetch failed: \(error?.localizedDescription ?? "?")") }
        guard response.value(forHTTPHeaderField: "X-Device") != device,
              let clip = Clip(contentType: response.value(forHTTPHeaderField: "Content-Type") ?? "", body: data) else { return }
        DispatchQueue.main.async { write(clip) }
    }.resume()
}

/// Reads Center's SSE stream; every `clip` event from another device is fetched and written to the pasteboard.
final class EventListener: NSObject, URLSessionDataDelegate {
    private var buffer = ""
    private var retryDelay: TimeInterval = 1

    func connect() {
        var request = URLRequest(url: center.appending(path: "events"), timeoutInterval: .infinity)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        URLSession(configuration: .default, delegate: self, delegateQueue: nil).dataTask(with: request).resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        retryDelay = 1
        buffer += String(decoding: data, as: UTF8.self)
        while let range = buffer.range(of: "\n\n") {
            let event = buffer[..<range.lowerBound]
            buffer.removeSubrange(..<range.upperBound)
            if event.contains("event: clip"), !event.contains("\"device\":\"\(device)\"") { fetchLatest() }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        log("events disconnected: \(error?.localizedDescription ?? "closed"); retrying in \(retryDelay)s")
        session.invalidateAndCancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { self.connect() }
        retryDelay = min(retryDelay * 2, 60)
    }
}

log("tailclip-sync on \(device), center \(center)")
let listener = EventListener()
listener.connect()
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in pollPasteboard() }
RunLoop.main.run()

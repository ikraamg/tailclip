// Checks for ClipDecision. Command Line Tools ship no XCTest, so this is a plain executable: `swift run sync-check`.
import Foundation
import SyncCore

var failures = 0

func check(_ name: String, _ expected: Clip?, _ snapshot: PasteboardSnapshot, lastSeen: Clip? = nil) {
    let actual = ClipDecision.clipToSend(from: snapshot, lastSeen: lastSeen)
    if actual == expected { print("ok   \(name)") } else { failures += 1; print("FAIL \(name): got \(String(describing: actual))") }
}

let png = Data([0x89, 0x50, 0x4E, 0x47])
let text = "public.utf8-plain-text"

check("sends text", .text("hello"), .init(types: [text], text: "hello"))
check("sends png", .png(png), .init(types: ["public.png"], png: png))
check("prefers the image when both are present", .png(png), .init(types: ["public.png", text], text: "alt", png: png))
check("skips its own writes", nil, .init(types: [ClipDecision.ownType, text], text: "hello"))
check("skips concealed content such as passwords", nil, .init(types: ["org.nspasteboard.ConcealedType", text], text: "hunter2"))
check("skips transient content", nil, .init(types: ["org.nspasteboard.TransientType", text], text: "tmp"))
check("skips files copied in Finder", nil, .init(types: ["public.file-url", text], text: "report.pdf"))
check("skips empty text", nil, .init(types: [text], text: ""))
check("skips when nothing is readable", nil, .init(types: ["public.rtf"]))
check("skips anything over the size cap", nil, .init(types: ["public.png"], png: Data(count: ClipDecision.maxBytes + 1)))
check("skips what it just sent or received", nil, .init(types: [text], text: "hello"), lastSeen: .text("hello"))
check("sends when content differs from last seen", .text("hello"), .init(types: [text], text: "hello"), lastSeen: .text("bye"))

print(failures == 0 ? "all checks passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)

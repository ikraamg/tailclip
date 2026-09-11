import Foundation

/// What is on the pasteboard right now, read once so the decision below needs no AppKit.
public struct PasteboardSnapshot {
    public var types: Set<String>
    public var text: String?
    public var png: Data?

    public init(types: Set<String>, text: String? = nil, png: Data? = nil) {
        self.types = types
        self.text = text
        self.png = png
    }
}

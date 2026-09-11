import Foundation

public enum ClipDecision {
    /// Written next to everything Sync puts on the pasteboard, so it recognizes its own writes.
    public static let ownType = "com.ikraam.tailclip"
    public static let maxBytes = 10 * 1024 * 1024

    static let concealedType = "org.nspasteboard.ConcealedType"
    static let transientType = "org.nspasteboard.TransientType"
    static let fileURLType = "public.file-url"

    /// The clip to send to Center for this pasteboard change, or nil to leave it alone.
    /// `lastSeen` is the last clip Sync sent or received.
    public static func clipToSend(from snapshot: PasteboardSnapshot, lastSeen: Clip?) -> Clip? {
        let skipped: Set<String> = [ownType, concealedType, transientType, fileURLType]
        guard snapshot.types.isDisjoint(with: skipped) else { return nil }
        let clip: Clip? = snapshot.png.map(Clip.png) ?? snapshot.text.flatMap { $0.isEmpty ? nil : .text($0) }
        guard let clip, clip.body.count <= maxBytes, clip != lastSeen else { return nil }
        return clip
    }
}

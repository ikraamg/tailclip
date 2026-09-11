import Foundation

/// One clipboard item as Center stores it.
public enum Clip: Equatable {
    case text(String)
    case png(Data)

    public var contentType: String {
        switch self {
        case .text: return "text/plain"
        case .png: return "image/png"
        }
    }

    public var body: Data {
        switch self {
        case .text(let string): return Data(string.utf8)
        case .png(let data): return data
        }
    }

    public init?(contentType: String, body: Data) {
        switch contentType.split(separator: ";").first.map(String.init) {
        case "text/plain": self = .text(String(decoding: body, as: UTF8.self))
        case "image/png": self = .png(body)
        default: return nil
        }
    }
}

import Foundation
import CoreFoundation

public enum TextFileEncoding: String, CaseIterable, Identifiable, Sendable {
    case utf8, utf16, shiftJIS, gb18030
    public var id: String { rawValue }
    public var label: String { switch self { case .utf8: return "UTF-8"; case .utf16: return "UTF-16"; case .shiftJIS: return "Shift-JIS（日语）"; case .gb18030: return "GB18030（中文）" } }
}

public enum TextDecoder {
    public static func decode(_ data: Data, encoding: TextFileEncoding? = nil) throws -> String {
        let chosen: String.Encoding
        switch encoding {
        case .utf8: chosen = .utf8
        case .utf16: chosen = .utf16
        case .shiftJIS: chosen = .shiftJIS
        case .gb18030: chosen = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        case nil:
            if data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) || data.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { chosen = .utf32 }
            else if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) { chosen = .utf16 }
            else { chosen = .utf8 }
        }
        guard var text = String(data: data, encoding: chosen), !text.unicodeScalars.contains(where: { $0.value == 0 }) else { throw RepositoryError.invalidEncoding }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

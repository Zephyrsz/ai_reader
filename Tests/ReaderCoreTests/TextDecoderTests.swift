import XCTest
@testable import ReaderCore

final class TextDecoderTests: XCTestCase {
    func testUTF8BOMIsRemovedAndNewlinesNormalized() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("日本語\r\n朝です。\r夕方".utf8)
        XCTAssertEqual(try TextDecoder.decode(data), "日本語\n朝です。\n夕方")
    }
    func testUTF16BOMIsDetected() throws {
        XCTAssertEqual(try TextDecoder.decode(Data([0xFF, 0xFE, 0xE5, 0x65, 0x2C, 0x67])), "日本")
    }
    func testShiftJISRequiresExplicitChoiceInsteadOfSilentMojibake() throws {
        let bytes = Data([0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA])
        XCTAssertThrowsError(try TextDecoder.decode(bytes))
        XCTAssertEqual(try TextDecoder.decode(bytes, encoding: .shiftJIS), "日本語")
    }
    func testMalformedUTF8IsRejected() throws {
        XCTAssertThrowsError(try TextDecoder.decode(Data([0xFF, 0x80, 0xFE]), encoding: .utf8))
    }
}

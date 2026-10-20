import LaWalletKit
import XCTest
@testable import LaWallet

final class L10nTests: XCTestCase {
    private func table(_ locale: String) throws -> [String: String] {
        var out: [String: String] = [:]
        for name in ["wallet", "ios", "ios-onboarding", "ios-payments", "ios-settings"] {
            guard let url = Bundle(for: AppModel.self).url(forResource: name, withExtension: "json", subdirectory: nil, localization: locale)
            else { continue }
            out.merge(try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) { $1 }
        }
        return out
    }

    func testLocalesHaveSameKeys() throws {
        let en = try table("en"), es = try table("es")
        XCTAssertGreaterThan(en.count, 900)
        XCTAssertEqual(Set(en.keys).subtracting(es.keys), [], "missing in es")
        XCTAssertEqual(Set(es.keys).subtracting(en.keys), [], "missing in en")
    }

    /// Every literal `t("…")` key used in the app source exists in both locales.
    func testEveryUsedKeyExists() throws {
        let en = try table("en"), es = try table("es")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LaWallet")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let regex = try NSRegularExpression(pattern: #"\bt\("([A-Za-z0-9_.\-]+)"[,)]"#)
        var missing: [String] = []
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
            for m in regex.matches(in: src, range: NSRange(src.startIndex..., in: src)) {
                let key = String(src[Range(m.range(at: 1), in: src)!])
                if en[key] == nil || es[key] == nil { missing.append("\(file.lastPathComponent): \(key)") }
            }
        }
        XCTAssertEqual(missing, [], "Unknown i18n keys")
    }

    func testInterpolation() {
        XCTAssertEqual(L10n.shared.string("common.sats", ["n": "21"]), L10n.shared.string("common.sats").replacingOccurrences(of: "{n}", with: "21"))
        XCTAssertEqual(t("does.not.exist"), "does.not.exist")
    }
}

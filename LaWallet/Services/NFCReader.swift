import Foundation

/// Reads a Bolt Card's NDEF URL (prefers `lnurlw://`, like `lib/client/ndef-url.ts`).
/// Interface is fixed; the payments feature fills in the CoreNFC implementation.
@MainActor
enum NFCReader {
    static var isAvailable: Bool { false }
    static func readURL(prompt: String) async throws -> String { throw CancellationError() }
}

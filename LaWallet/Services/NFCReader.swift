import CoreNFC
import Foundation

/// Reads a Bolt Card's NDEF URL (prefers `lnurlw://`, like `lib/client/ndef-url.ts`).
@MainActor
enum NFCReader {
    static var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    /// Presents the system NFC sheet and returns the card's payment link. Throws `CancellationError` when the user dismisses it.
    static func readURL(prompt: String) async throws -> String {
        guard isAvailable else { throw NFCReadFailure(t("ios.nfc.unavailable")) }
        let reader = NDEFURLReader()
        return try await reader.read(prompt: prompt)
    }

    /// `firstBoltcardUrl`: LNURL-withdraw links win over a generic https URL (an app record can't shadow the card link).
    nonisolated static func firstBoltcardURL(_ texts: [String]) -> String? {
        let urls = texts.map { $0.replacingOccurrences(of: "\u{0}", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.range(of: #"^(https?://|lnurlw://|lnurlp://|lnurl1)"#, options: [.regularExpression, .caseInsensitive]) != nil }
        return urls.first { $0.range(of: #"^(lnurlw://|lnurl1)"#, options: [.regularExpression, .caseInsensitive]) != nil } ?? urls.first
    }

    /// Candidate strings in one NDEF record: URI records expand their prefix byte, text records drop their language header.
    nonisolated static func texts(in record: NFCNDEFPayload) -> [String] {
        var out: [String] = []
        if let url = record.wellKnownTypeURIPayload() { out.append(url.absoluteString) }
        if let text = record.wellKnownTypeTextPayload().0 { out.append(text) }
        if let raw = String(data: record.payload, encoding: .utf8) { out.append(raw) }
        if record.payload.count > 1, let rest = String(data: record.payload.dropFirst(), encoding: .utf8) { out.append(rest) }
        return out
    }
}

struct NFCReadFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// One-shot NDEF read bridged to async. Callbacks arrive on the main queue, so the continuation is only touched there.
private final class NDEFURLReader: NSObject, NFCNDEFReaderSessionDelegate, @unchecked Sendable {
    private var session: NFCNDEFReaderSession?
    private var continuation: CheckedContinuation<String, Error>?

    @MainActor
    func read(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            let s = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
            s.alertMessage = prompt
            session = s
            s.begin()
        }
    }

    private func finish(_ result: Result<String, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        session = nil
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let texts = messages.flatMap(\.records).flatMap(NFCReader.texts(in:))
        if let url = NFCReader.firstBoltcardURL(texts) {
            finish(.success(url))
        } else {
            session.invalidate(errorMessage: t("errors.nfc.noLink"))
            finish(.failure(NFCReadFailure(t("errors.nfc.noLink"))))
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        guard continuation != nil else { return }
        switch (error as? CoreNFC.NFCReaderError)?.code {
        case .readerSessionInvalidationErrorUserCanceled?, .readerSessionInvalidationErrorSessionTimeout?:
            finish(.failure(CancellationError()))
        case .readerSessionInvalidationErrorFirstNDEFTagRead?:
            finish(.failure(NFCReadFailure(t("errors.nfc.noLink"))))
        case .readerErrorUnsupportedFeature?, .readerErrorSecurityViolation?, .readerSessionInvalidationErrorSystemIsBusy?:
            finish(.failure(NFCReadFailure(t("errors.nfc.startError"))))
        default:
            finish(.failure(NFCReadFailure(t("errors.nfc.readError"))))
        }
    }
}

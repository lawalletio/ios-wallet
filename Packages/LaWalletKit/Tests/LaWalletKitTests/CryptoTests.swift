import Foundation
import Testing
@testable import LaWalletKit

private func vectors() throws -> JSONValue {
    let url = Bundle.module.url(forResource: "nip44.vectors", withExtension: "json")!
    return try JSONValue.parse(Data(contentsOf: url))["v2"]!
}

@Suite struct NostrCryptoTests {
    @Test func nip19RoundTrip() throws {
        // NIP-19 spec example.
        #expect(NIP19.npub("7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e")
            == "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg")
        #expect(NIP19.secret("nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5")?.hex
            == "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa")
        let k = NostrKeys.generate()
        #expect(try NostrKeys(nsecOrHex: k.nsec) == k)
        #expect(NIP19.pubkeyHex(k.npub) == k.publicKey)
    }

    @Test func eventSerializationEscapes() {
        let s = NostrEvent.serialize(pubkey: "ab", createdAt: 1, kind: 1, tags: [["t", "a\"b"]], content: "l1\nl2\\/é\u{01}")
        #expect(s == #"[0,"ab",1,1,[["t","a\"b"]],"l1\nl2\\/é\u0001"]"#)
    }

    @Test func signAndVerify() throws {
        let keys = NostrKeys.generate()
        let ev = try NostrEvent.sign(UnsignedEvent(kind: 1, tags: [["p", keys.publicKey]], content: "hi"), with: keys)
        #expect(ev.isValid)
        let tampered = NostrEvent(id: ev.id, pubkey: ev.pubkey, created_at: ev.created_at, kind: 1, tags: ev.tags, content: "bye", sig: ev.sig)
        #expect(!tampered.isValid)
        let decoded = try JSONDecoder().decode(NostrEvent.self, from: Data(ev.json.utf8))
        #expect(decoded == ev && decoded.isValid)
    }

    @Test func nip04RoundTrip() throws {
        let a = NostrKeys.generate(), b = NostrKeys.generate()
        let ct = try NIP04.encrypt("{\"method\":\"get_balance\"}", keys: a, peer: b.publicKey)
        #expect(try NIP04.decrypt(ct, keys: b, peer: a.publicKey) == "{\"method\":\"get_balance\"}")
    }

    @Test func nip44ConversationKeys() throws {
        for v in try vectors()["valid"]!["get_conversation_key"]!.array! {
            let keys = try NostrKeys(secret: Data(hex: v["sec1"]!.string!)!)
            #expect(try NIP44.conversationKey(keys: keys, peer: v["pub2"]!.string!).hex == v["conversation_key"]!.string!)
        }
    }

    @Test func nip44MessageKeys() throws {
        let v = try vectors()["valid"]!["get_message_keys"]!
        let ck = Data(hex: v["conversation_key"]!.string!)!
        for k in v["keys"]!.array! {
            let m = NIP44.messageKeys(conversationKey: ck, nonce: Data(hex: k["nonce"]!.string!)!)
            #expect(m.chachaKey.hex == k["chacha_key"]!.string!)
            #expect(m.chachaNonce.hex == k["chacha_nonce"]!.string!)
            #expect(m.hmacKey.hex == k["hmac_key"]!.string!)
        }
    }

    @Test func nip44Padding() throws {
        for pair in try vectors()["valid"]!["calc_padded_len"]!.array! {
            #expect(NIP44.paddedLength(pair.array![0].int!) == pair.array![1].int!)
        }
    }

    @Test func nip44EncryptDecrypt() throws {
        for v in try vectors()["valid"]!["encrypt_decrypt"]!.array! {
            let ck = Data(hex: v["conversation_key"]!.string!)!
            let k1 = try NostrKeys(secret: Data(hex: v["sec1"]!.string!)!)
            let k2 = try NostrKeys(secret: Data(hex: v["sec2"]!.string!)!)
            #expect(try NIP44.conversationKey(keys: k1, peer: k2.publicKey) == ck)
            let payload = try NIP44.encrypt(v["plaintext"]!.string!, conversationKey: ck, nonce: Data(hex: v["nonce"]!.string!)!)
            #expect(payload == v["payload"]!.string!)
            #expect(try NIP44.decrypt(payload, conversationKey: ck) == v["plaintext"]!.string!)
        }
    }

    @Test func nip44RejectsInvalid() throws {
        for v in try vectors()["invalid"]!["decrypt"]!.array! {
            let ck = Data(hex: v["conversation_key"]!.string!)!
            #expect(throws: (any Error).self) { try NIP44.decrypt(v["payload"]!.string!, conversationKey: ck) }
        }
    }
}

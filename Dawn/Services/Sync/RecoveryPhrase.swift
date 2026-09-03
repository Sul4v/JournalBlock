import Foundation
import CryptoKit

/// The twelve words that are the only way back into a backup when no device
/// holds the key.
///
/// This is BIP39, the scheme crypto wallets use — not because journals have
/// anything to do with wallets, but because it solves the exact problem we
/// have: getting 128 bits of randomness out of a phone, through a human, and
/// back into a phone without corruption.
///
/// Words beat a string of characters here for one reason above the rest: the
/// phrase carries a checksum. Four of its bits are derived from the other 128,
/// so a mistyped or reordered phrase is caught instantly and offline, before
/// any network call, and we can say "check your phrase" rather than the far
/// more alarming "that doesn't match this account".
enum RecoveryPhrase {
    /// 16 bytes of entropy + 4 checksum bits = 132 bits = 12 words of 11 bits.
    /// 128 bits is the standard security level; nothing is gained by making a
    /// person write down more words.
    static let entropyBytes = 16
    static let wordCount = 12

    private static let bitsPerWord = 11
    private static var checksumBits: Int { entropyBytes * 8 / 32 }

    // MARK: - Making one

    static func generate() -> [String] {
        var bytes = [UInt8](repeating: 0, count: entropyBytes)
        guard SecRandomCopyBytes(kSecRandomDefault, entropyBytes, &bytes) == errSecSuccess else {
            fatalError("The system random number generator is unavailable.")
        }
        // Force-unwrapped deliberately: encoding our own freshly generated
        // entropy cannot fail, and a nil here would mean the encoder is broken.
        return encode(Data(bytes))!
    }

    /// Turns entropy into words. Nil if the entropy is the wrong length.
    static func encode(_ entropy: Data) -> [String]? {
        guard entropy.count == entropyBytes else { return nil }

        var bits = entropy.flatMap { byte in (0..<8).map { (byte >> (7 - $0)) & 1 } }
        let digest = Array(SHA256.hash(data: entropy))
        // The checksum is simply the leading bits of the hash of the entropy,
        // which is what lets a decoder verify a phrase with no other context.
        bits += (0..<checksumBits).map { (digest[$0 / 8] >> (7 - UInt8($0 % 8))) & 1 }

        return stride(from: 0, to: bits.count, by: bitsPerWord).map { offset in
            let index = bits[offset..<offset + bitsPerWord]
                .reduce(0) { ($0 << 1) | Int($1) }
            return BIP39Wordlist.words[index]
        }
    }

    // MARK: - Reading one back

    /// Splits typed input into candidate words. Doesn't validate them — the
    /// entry field wants to show partial progress as someone types.
    static func words(in input: String) -> [String] {
        input.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
    }

    /// Any words that aren't in the list, so the field can point at them.
    static func unknownWords(in input: String) -> [String] {
        words(in: input).filter { BIP39Wordlist.index(of: $0) == nil }
    }

    /// Recovers the entropy, or nil if the phrase is the wrong length, holds a
    /// word we don't know, or fails its checksum. The checksum is what catches
    /// two swapped words — every individual word is valid, but the whole is not.
    static func decode(_ input: String) -> Data? {
        let words = words(in: input)
        guard words.count == wordCount else { return nil }

        var bits = [UInt8]()
        for word in words {
            guard let index = BIP39Wordlist.index(of: word) else { return nil }
            bits += (0..<bitsPerWord).map { UInt8((index >> (bitsPerWord - 1 - $0)) & 1) }
        }

        let entropyBits = entropyBytes * 8
        let entropy = Data(
            stride(from: 0, to: entropyBits, by: 8).map { offset in
                bits[offset..<offset + 8].reduce(UInt8(0)) { ($0 << 1) | $1 }
            }
        )

        guard encode(entropy) == words else { return nil }
        return entropy
    }

    static func isValid(_ input: String) -> Bool { decode(input) != nil }

    // MARK: - Entry help

    /// Completions for a half-typed word, for the suggestion strip above the
    /// keyboard. Every word is unique in its first four letters, so this
    /// collapses to a single answer almost immediately.
    static func completions(for fragment: String, limit: Int = 3) -> [String] {
        let prefix = fragment.lowercased()
        guard !prefix.isEmpty else { return [] }
        return BIP39Wordlist.words.lazy
            .filter { $0.hasPrefix(prefix) }
            .prefix(limit)
            .map { $0 }
    }

    /// How the phrase is written when it's shown or copied.
    static func formatted(_ words: [String]) -> String {
        words.joined(separator: " ")
    }
}

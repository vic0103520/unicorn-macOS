import Foundation

/// A node in the symbol lookup Trie.
/// This is a reference type (`final class`) to allow for efficient sharing of subtrees
/// without deep copying. All properties are immutable (`let`), making it safe to share.
public final class Trie: Decodable, Equatable {
    public let candidates: [String]?
    public let children: [Character: Trie]

    public static func == (lhs: Trie, rhs: Trie) -> Bool {
        // Structural equality check: identical if they are the same instance (fast path)
        // or if their contents match.
        return lhs === rhs || (lhs.candidates == rhs.candidates && lhs.children == rhs.children)
    }

    struct DynamicKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { return nil }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var candidates: [String]?
        var children: [Character: Trie] = [:]

        for key in container.allKeys {
            if key.stringValue == ">>" {
                candidates = try container.decode([String].self, forKey: key)
            } else if key.stringValue.count == 1, let char = key.stringValue.first {
                let child = try container.decode(Trie.self, forKey: key)
                children[char] = child
            }
        }
        self.candidates = candidates
        self.children = children
    }
}

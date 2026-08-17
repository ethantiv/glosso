import Foundation

enum DiffPart: Identifiable {
    case same(id: Int, text: String)
    case change(id: Int, removed: String, added: String)

    var id: Int {
        switch self {
        case .same(let id, _): id
        case .change(let id, _, _): id
        }
    }
}

enum GrammarDiff {
    static func parts(original: String, corrected: String) -> [DiffPart] {
        let before = Tokenizer.segments(original).map(\.text)
        let after = Tokenizer.segments(corrected).map(\.text)
        let diff = after.difference(from: before)

        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removedOffsets.insert(offset)
            case .insert(let offset, _, _): insertedOffsets.insert(offset)
            }
        }

        enum Op { case same(String), remove(String), insert(String) }
        var ops: [Op] = []
        var bi = 0, ai = 0
        while bi < before.count || ai < after.count {
            if bi < before.count, removedOffsets.contains(bi) {
                ops.append(.remove(before[bi])); bi += 1
            } else if ai < after.count, insertedOffsets.contains(ai) {
                ops.append(.insert(after[ai])); ai += 1
            } else {
                ops.append(.same(before[bi])); bi += 1; ai += 1
            }
        }

        var parts: [DiffPart] = []
        var nextID = 0
        var i = 0
        while i < ops.count {
            if case .same(let text) = ops[i] {
                var joined = text
                i += 1
                while i < ops.count, case .same(let next) = ops[i] { joined += next; i += 1 }
                parts.append(.same(id: nextID, text: joined))
            } else {
                var removed = "", added = ""
                loop: while i < ops.count {
                    switch ops[i] {
                    case .remove(let text): removed += text
                    case .insert(let text): added += text
                    case .same: break loop
                    }
                    i += 1
                }
                // A whitespace-only change (the model reflowing "\n" into " ") is not a correction: rendered,
                // it is an invisible tappable chunk, and enough of them flip splitFixView with no word changed.
                if removed.allSatisfy(\.isWhitespace), added.allSatisfy(\.isWhitespace) {
                    if !added.isEmpty { parts.append(.same(id: nextID, text: added)) }
                } else {
                    parts.append(.change(id: nextID, removed: removed, added: added))
                }
            }
            nextID += 1
        }
        return parts
    }
}

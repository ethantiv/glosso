import Foundation

/// One span of the word-level diff between the learner's original text and the
/// `fixGrammar` correction (issue #51). `.same` is unchanged; `.change` is one
/// contiguous edit region — `removed` is the struck-through error, `added` the
/// correction (either may be "" for a pure insertion or deletion). Lossless per
/// side: joining the `.same` texts with each `.change`'s `removed` reproduces the
/// original; joining them with each `.change`'s `added` reproduces the correction.
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
    /// Word-level diff via `CollectionDifference` over `Tokenizer` segments — no
    /// model call, no new dependency. Adjacent removals and insertions between two
    /// unchanged spans collapse into a single `.change`, so a substitution reads as
    /// one tappable unit (struck error → correction) rather than scattered tokens.
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

        // Merge both token streams in order: a removed token, an inserted token, or
        // a kept token shared by both (the kept tokens line up 1:1 in both streams).
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

        // Coalesce: a run of `same` ops becomes one `.same`; a run touching any
        // remove/insert becomes one `.change` with its removed and added text
        // concatenated separately.
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
                parts.append(.change(id: nextID, removed: removed, added: added))
            }
            nextID += 1
        }
        return parts
    }
}

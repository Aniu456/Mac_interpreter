import Foundation

struct IncomingCaption: Identifiable, Equatable, Sendable {
    let id: UUID
    var original: String
    var revision = 1
    var chinese = ""
    var translatedRevision = 0
    var translationError: String?
}

struct IncomingCaptions {
    private(set) var rows: [IncomingCaption] = []

    mutating func update(id: UUID, text: String) {
        guard !text.isEmpty else { return }
        if let index = rows.firstIndex(where: { $0.id == id }) {
            guard rows[index].original != text else { return }
            rows[index].original = text
            rows[index].revision += 1
            rows[index].translationError = nil
        } else {
            rows.append(IncomingCaption(id: id, original: text))
            if rows.count > 6 { rows.removeFirst(rows.count - 6) }
        }
    }

    mutating func commit(id: UUID, revision: Int, chinese: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              revision > rows[index].translatedRevision,
              revision <= rows[index].revision else { return }
        rows[index].chinese = chinese
        rows[index].translatedRevision = revision
        rows[index].translationError = nil
    }

    mutating func fail(id: UUID, message: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].translationError = message
    }
}

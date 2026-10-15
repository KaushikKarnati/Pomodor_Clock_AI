import Foundation

/// Queue ownership provides FIFO writes. Enqueue from the store's main actor.
final class StateFileWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.focustalk.persistence", qos: .utility)
    private let url: URL
    private let write: @Sendable (Data, URL) throws -> Void

    init(url: URL, write: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }) {
        self.url = url
        self.write = write
    }

    func save(_ state: SavedState, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        queue.async { [self] in
            completion(Result {
                let data = try JSONEncoder().encode(state)
                try write(data, url)
            })
        }
    }
}

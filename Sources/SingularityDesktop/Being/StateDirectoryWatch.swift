import Foundation

/// The runtime's writes to a being's state directory, as a stream of
/// "something changed" signals, so the window reads the being after a write
/// instead of on a clock.
///
/// The runtime replaces `state.json` by renaming a finished temporary file
/// over it, which is a `.write` on the directory, and appends events to
/// `activity.jsonl` in place, which is an `.extend` on that file. Both are
/// watched. Every directory change opens the watches again, because the
/// journal appears with the runtime's first append and the directory itself
/// may be created, moved or removed; while the directory does not exist its
/// nearest existing ancestor is watched, where creating it is a change.
/// Changes that arrive while a signal waits to be taken add nothing to it, so
/// a burst of writes during one read asks for exactly one more read.
final class StateDirectoryWatch: @unchecked Sendable {
    struct Failure: LocalizedError {
        let path: String
        let reason: String
        var errorDescription: String? {
            "The state directory cannot be watched: \(path) cannot be opened (\(reason))."
        }
    }

    let changes: AsyncThrowingStream<Void, Error>
    private let continuation: AsyncThrowingStream<Void, Error>.Continuation
    private let directory: URL
    private let journal: URL
    private let queue = DispatchQueue(label: "ai.wisent.singularity.state-watch")
    private let lock = NSLock()
    private var signalled = false
    // Touched only on `queue`.
    private var sources: [DispatchSourceFileSystemObject] = []

    init(directory: URL, journal: URL) throws {
        let made = AsyncThrowingStream<Void, Error>.makeStream()
        changes = made.stream
        continuation = made.continuation
        self.directory = directory
        self.journal = journal
        try queue.sync { try arm() }
    }

    /// Takes the waiting signal: a change after this asks for another read.
    func taken() {
        lock.withLock { signalled = false }
    }

    /// Ends `changes` without a failure, as when another directory is chosen.
    func stop() {
        continuation.finish()
    }

    deinit {
        continuation.finish()
        sources.forEach { $0.cancel() }
    }

    private func signal() {
        let first = lock.withLock {
            defer { signalled = true }
            return !signalled
        }
        if first { continuation.yield() }
    }

    private func directoryChanged() {
        do {
            try arm()
            signal()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func arm() throws {
        sources.forEach { $0.cancel() }
        sources = []
        var watched = directory.path(percentEncoded: false)
        var descriptor = open(watched, O_EVTONLY)
        while descriptor < .zero, errno == ENOENT, watched != "/" {
            watched = (watched as NSString).deletingLastPathComponent
            descriptor = open(watched, O_EVTONLY)
        }
        guard descriptor >= .zero else {
            throw Failure(path: watched, reason: String(cString: strerror(errno)))
        }
        sources.append(
            source(over: descriptor, events: [.write, .delete, .rename]) {
                [weak self] in self?.directoryChanged()
            })
        // An absent journal is no failure: its creation is a directory change,
        // which arms this watch again. Any other refusal is the read's to say,
        // and the read that follows every change says it with its cause.
        let journalDescriptor = open(journal.path(percentEncoded: false), O_EVTONLY)
        if journalDescriptor >= .zero {
            sources.append(
                source(over: journalDescriptor, events: [.extend, .write, .delete, .rename]) {
                    [weak self] in self?.signal()
                })
        }
    }

    private func source(
        over descriptor: Int32,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping @Sendable () -> Void
    ) -> DispatchSourceFileSystemObject {
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}

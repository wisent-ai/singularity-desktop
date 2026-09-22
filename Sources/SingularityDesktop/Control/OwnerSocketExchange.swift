import Darwin
import Dispatch
import Foundation

/// Mutable state is confined to `queue`; descriptors close only after source cancellation completes.
final class OwnerSocketExchange: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.wisent.singularity.owner-exchange")
    private let cleanup = DispatchGroup()
    private let request: Data
    private let path: String
    private let maximumResponseBytes: Int
    private var descriptor: Int32?
    private var writer: (any DispatchSourceWrite)?
    private var reader: (any DispatchSourceRead)?
    private var continuation: CheckedContinuation<Data, Error>?
    private var result: Result<Data, Error>?
    private var cleaned = false
    private var connected = false
    private var sent = 0
    private var response = Data()
    private var buffer: [UInt8] = []

    init(request: Data, path: String, maximumResponseBytes: Int) {
        self.request = request
        self.path = path
        self.maximumResponseBytes = maximumResponseBytes
    }

    func start(_ continuation: CheckedContinuation<Data, Error>) {
        queue.async {
            self.continuation = continuation
            guard self.result == nil else {
                self.deliver()
                return
            }
            do { try self.connect() }
            catch { self.finish(.failure(error)) }
        }
    }

    func cancel() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    private func connect() throws {
        let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard path.utf8.count < capacity, !path.utf8.contains(OwnerProtocol.zeroByte) else {
            throw OwnerConnectionFailure(message: "The owner socket path is too long or contains a null byte: \(path)")
        }
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw failure("create socket") }
        self.descriptor = descriptor
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            throw failure("configure nonblocking socket")
        }
        var noSignal: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal))) == 0 else {
            throw failure("configure socket signal handling")
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                _ = path.withCString { strcpy(destination, $0) }
            }
        }
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: OwnerProtocol.addressCount) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if status == 0 {
            try verifyPeer(descriptor)
            connected = true
        } else if errno != EINPROGRESS {
            throw failure("connect to live state owner")
        }
        let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
        cleanup.enter()
        source.setCancelHandler { [cleanup] in cleanup.leave() }
        source.setEventHandler { self.writeReady() }
        writer = source
        source.activate()
    }

    private func verifyPeer(_ descriptor: Int32) throws {
        var uid = uid_t()
        var gid = gid_t()
        guard getpeereid(descriptor, &uid, &gid) == 0 else { throw failure("read owner identity") }
        let expected = geteuid()
        guard uid == expected else {
            throw OwnerConnectionFailure(message: "The socket at \(path) belongs to UID \(uid), not this user's UID \(expected).")
        }
    }

    private func writeReady() {
        guard result == nil, reader == nil, let descriptor else { return }
        do {
            if !connected {
                var error: Int32 = 0
                var length = socklen_t(MemoryLayout.size(ofValue: error))
                guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &error, &length) == 0 else {
                    throw failure("read connection result")
                }
                guard error == 0 else { throw failure("connect to live state owner", code: error) }
                try verifyPeer(descriptor)
                connected = true
            }
            while sent < request.count {
                let count = request.withUnsafeBytes { raw in
                    Darwin.write(descriptor, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                }
                if count < 0 && errno == EINTR { continue }
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
                guard count > 0 else { throw failure("write request") }
                sent += count
            }
            guard Darwin.shutdown(descriptor, SHUT_WR) == 0 else { throw failure("finish request") }
            buffer = [UInt8](repeating: OwnerProtocol.zeroByte, count: OwnerProtocol.bufferBytes)
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            cleanup.enter()
            source.setCancelHandler { [cleanup] in cleanup.leave() }
            source.setEventHandler { self.readReady() }
            reader = source
            source.activate()
            writer?.cancel()
            writer = nil
        } catch { finish(.failure(error)) }
    }

    private func readReady() {
        guard result == nil, let descriptor else { return }
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            guard count >= 0 else { finish(.failure(failure("read response"))); return }
            if count == 0 { finish(.success(response)); return }
            guard response.count + count <= maximumResponseBytes else {
                finish(.failure(OwnerConnectionFailure(message: "The state owner's response exceeds \(maximumResponseBytes) bytes: \(path)")))
                return
            }
            response.append(contentsOf: buffer.prefix(count))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        guard self.result == nil else { return }
        self.result = result
        writer?.cancel()
        reader?.cancel()
        writer = nil
        reader = nil
        cleanup.notify(queue: queue) {
            if let descriptor = self.descriptor { Darwin.close(descriptor) }
            self.descriptor = nil
            self.cleaned = true
            self.deliver()
        }
    }

    private func deliver() {
        guard cleaned, let result, let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private func failure(_ operation: String, code: Int32 = errno) -> OwnerConnectionFailure {
        OwnerConnectionFailure(message: "Could not \(operation) at \(path): \(String(cString: strerror(code))). No final owner state was confirmed.")
    }
}

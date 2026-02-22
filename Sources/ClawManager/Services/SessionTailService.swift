import Foundation

/// Watches a single JSONL file for new lines appended by Claude Code,
/// parsing them into `ParsedMessage` objects in real time.
///
/// Uses `DispatchSource.makeFileSystemObjectSource` for near-instant
/// change detection (millisecond latency) without spawning any processes.
actor SessionTailService {

    // MARK: - State

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private(set) var lastOffset: UInt64 = 0
    private var continuation: AsyncStream<ParsedMessage>.Continuation?
    private(set) var currentPath: String?

    /// Cumulative count of messages yielded since tailing started.
    private(set) var messagesTailed: Int = 0

    // MARK: - Public API

    /// Start tailing a JSONL file from a given byte offset.
    /// - `fromOffset`: byte position to start reading new lines from.
    ///   Pass the file size after `readAll()` to avoid re-reading existing content.
    /// - Returns an `AsyncStream` that yields new `ParsedMessage` objects as they appear.
    func startTailing(path: String, fromOffset: UInt64) -> AsyncStream<ParsedMessage> {
        stopTailing()

        currentPath = path
        lastOffset = fromOffset
        messagesTailed = 0

        let (stream, cont) = AsyncStream<ParsedMessage>.makeStream()
        self.continuation = cont

        let fd = open(path, O_RDONLY | O_EVTONLY)
        guard fd >= 0 else {
            Diag.log(.error, .tail, "Failed to open file descriptor", data: ["path": path])
            cont.finish()
            return stream
        }
        self.fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.readNewLines() }
        }

        source.setCancelHandler { [fd] in
            close(fd)
        }

        source.resume()
        self.source = source

        Diag.log(.info, .tail, "Started tailing", data: [
            "path": (path as NSString).lastPathComponent,
            "fromOffset": fromOffset
        ])

        return stream
    }

    /// Stop tailing and clean up resources.
    func stopTailing() {
        let wasTailing = source != nil
        source?.cancel()
        source = nil
        fileDescriptor = -1

        if wasTailing {
            Diag.log(.info, .tail, "Stopped tailing", data: [
                "messagesTailed": messagesTailed,
                "finalOffset": lastOffset
            ])
        }

        lastOffset = 0
        messagesTailed = 0
        currentPath = nil
        continuation?.finish()
        continuation = nil
    }

    var isTailing: Bool {
        source != nil
    }

    /// Snapshot of tail state for diagnostics.
    var diagnosticInfo: (path: String?, offset: UInt64, messagesTailed: Int, active: Bool) {
        (currentPath, lastOffset, messagesTailed, source != nil)
    }

    // MARK: - Private

    private func readNewLines() {
        guard let path = currentPath else { return }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            Diag.log(.error, .tail, "Cannot open file for reading")
            return
        }
        defer { try? handle.close() }

        // Check current file size — if it hasn't grown past our offset, nothing to do
        let fileSize = handle.seekToEndOfFile()
        guard fileSize > lastOffset else { return }

        let bytesToRead = fileSize - lastOffset
        handle.seek(toFileOffset: lastOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        lastOffset = handle.offsetInFile

        guard let text = String(data: data, encoding: .utf8) else { return }

        var newCount = 0
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let msg = JSONLParser.parseLine(trimmed) {
                continuation?.yield(msg)
                newCount += 1
            }
        }

        messagesTailed += newCount

        if newCount > 0 {
            Diag.log(.info, .tail, "Read new lines", data: [
                "newMessages": newCount,
                "bytesRead": bytesToRead,
                "totalTailed": messagesTailed,
                "offset": lastOffset
            ])
        }
    }
}

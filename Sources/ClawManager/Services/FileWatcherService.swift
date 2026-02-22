import Foundation
import Combine

final class FileWatcherService: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let subject = PassthroughSubject<Set<String>, Never>()
    private var cancellable: AnyCancellable?

    /// Publisher that emits batched changed file paths, debounced at 500ms.
    var changes: AnyPublisher<Set<String>, Never> {
        subject
            .collect(.byTime(DispatchQueue.main, .milliseconds(500)))
            .map { sets in sets.reduce(into: Set<String>()) { $0.formUnion($1) } }
            .eraseToAnyPublisher()
    }

    func startWatching() {
        let pathsToWatch = [
            PathUtilities.projectsDir.path,
            PathUtilities.ideDir.path
        ]

        // Verify directories exist
        let fm = FileManager.default
        for path in pathsToWatch {
            if !fm.fileExists(atPath: path) {
                try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
        }

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let flags: FSEventStreamCreateFlags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

                let relevant = paths.filter { path in
                    path.hasSuffix(".jsonl") || path.hasSuffix(".lock") || path.hasSuffix(".json")
                }

                if !relevant.isEmpty {
                    watcher.subject.send(Set(relevant))
                }
            },
            &context,
            pathsToWatch as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stopWatching() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stopWatching()
    }
}

import Foundation

/// Watches a single file path for writes and atomic-rename saves.
/// Atomic-save handling: many editors (Vim, VSCode, Sublime) write to a
/// temp file then rename it over the target. The original inode disappears,
/// so we re-open the path after a short debounce. While the path is missing
/// it's re-polled with backoff (0.15 s doubling to 2 s), and `onMissing` fires
/// once if it's still gone after ~1 s (a delete or move, not a save).
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let onMissing: (() -> Void)?
    private let queue = DispatchQueue(label: "com.markee.filewatcher", qos: .utility)

    private var source: DispatchSourceFileSystemObject?
    private var reattachItem: DispatchWorkItem?
    private var changeDebounce: DispatchWorkItem?

    init(url: URL, onMissing: (() -> Void)? = nil, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        self.onMissing = onMissing
        attach()
    }

    deinit { cancelInternal() }

    func cancel() {
        queue.sync { cancelInternal() }
    }

    private func cancelInternal() {
        reattachItem?.cancel(); reattachItem = nil
        changeDebounce?.cancel(); changeDebounce = nil
        releaseSource()
    }

    private func releaseSource() {
        source?.cancel()
        source = nil
    }

    private func attach() {
        queue.async { [weak self] in
            guard let self else { return }
            // Only release the previous source — do NOT cancel pending reattach
            // or debounce work items; the caller may have just scheduled them.
            self.releaseSource()
            let descriptor = open(self.url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                self.scheduleReattach()
                return
            }
            let s = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .delete, .rename, .revoke, .attrib],
                queue: self.queue
            )
            s.setEventHandler { [weak self] in
                guard let self, let src = self.source else { return }
                let flags = src.data
                if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                    // File gone — re-attach to the path after a brief debounce.
                    self.scheduleReattach()
                } else {
                    self.debouncedFire()
                }
            }
            s.setCancelHandler { [fd = descriptor] in
                if fd >= 0 { close(fd) }
            }
            self.source = s
            s.resume()
        }
    }

    /// Attempts after which a still-missing file is reported (~1 s in).
    private static let missingReportAttempt = 3

    private func scheduleReattach(attempt: Int = 0) {
        reattachItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.url.path) {
                self.attach()
                self.debouncedFire()
            } else {
                if attempt + 1 == Self.missingReportAttempt, let onMissing = self.onMissing {
                    DispatchQueue.main.async { onMissing() }
                }
                self.scheduleReattach(attempt: attempt + 1)
            }
        }
        reattachItem = item
        let delay = min(0.15 * pow(2, Double(attempt)), 2.0)
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func debouncedFire() {
        changeDebounce?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        changeDebounce = item
        queue.asyncAfter(deadline: .now() + 0.05, execute: item)
    }
}

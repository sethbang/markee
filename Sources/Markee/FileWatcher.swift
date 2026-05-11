import Foundation

/// Watches a single file path for writes and atomic-rename saves.
/// Atomic-save handling: many editors (Vim, VSCode, Sublime) write to a
/// temp file then rename it over the target. The original inode disappears,
/// so we re-open the path after a short debounce.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "com.markee.filewatcher", qos: .utility)

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var reattachItem: DispatchWorkItem?
    private var changeDebounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        attach()
    }

    deinit { cancelInternal() }

    func cancel() {
        queue.sync { cancelInternal() }
    }

    private func cancelInternal() {
        reattachItem?.cancel(); reattachItem = nil
        changeDebounce?.cancel(); changeDebounce = nil
        source?.cancel()
        source = nil
    }

    private func attach() {
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelInternal()
            let descriptor = open(self.url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                self.scheduleReattach()
                return
            }
            self.fd = descriptor
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

    private func scheduleReattach() {
        reattachItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if FileManager.default.fileExists(atPath: self.url.path) {
                self.attach()
                self.debouncedFire()
            } else {
                self.scheduleReattach()
            }
        }
        reattachItem = item
        queue.asyncAfter(deadline: .now() + 0.15, execute: item)
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

import Foundation
import Security

/// A dotted numeric version (e.g. "0.4.0"), tolerant of a leading "v" and of a
/// pre-release/build suffix. Used only to compare the running app against the
/// latest GitHub release.
struct AppVersion: Comparable, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        // Drop any pre-release suffix ("1.0.0-rc1" -> "1.0.0"). Harmless:
        // the updater only reads /releases/latest, which excludes pre-releases.
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var nums: [Int] = []
        for p in parts {
            guard let n = Int(p), n >= 0 else { return nil }
            nums.append(n)
        }
        self.components = nums
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return false }
        }
        return true
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

/// The subset of a GitHub Release that Markee uses, decoded from the
/// `/releases/latest` API response.
struct GitHubRelease: Sendable {
    let version: AppVersion
    let tagName: String
    let pageURL: URL
    let zipURL: URL
    let notes: String

    /// Parse the GitHub `/releases/latest` JSON. Returns nil if the payload is
    /// missing required fields or has no `Markee.app.zip` asset.
    init?(json data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let version = AppVersion(tag),
              let htmlURLString = obj["html_url"] as? String,
              let pageURL = URL(string: htmlURLString),
              let assets = obj["assets"] as? [[String: Any]]
        else { return nil }

        guard let zip = assets.first(where: { ($0["name"] as? String) == "Markee.app.zip" }),
              let zipURLString = zip["browser_download_url"] as? String,
              let zipURL = URL(string: zipURLString)
        else { return nil }

        self.version = version
        self.tagName = tag
        self.pageURL = pageURL
        self.zipURL = zipURL
        self.notes = (obj["body"] as? String) ?? ""
    }
}

enum UpdaterError: LocalizedError {
    case badResponse
    case unparseable
    case downloadFailed
    case subprocessFailed
    case invalidBundle

    var errorDescription: String? {
        switch self {
        case .badResponse:      return "GitHub returned an unexpected response."
        case .unparseable:      return "Couldn't read the release information."
        case .downloadFailed:   return "The update download failed."
        case .subprocessFailed: return "Unpacking the update failed."
        case .invalidBundle:    return "The downloaded update isn't a validly signed copy of Markee."
        }
    }
}

import AppKit

/// A minimal modal-free panel shown while an update downloads and installs.
@MainActor
final class UpdateProgressPanel {
    private let panel: NSPanel
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "Downloading update…")
        label.alignment = .center

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 32, bottom: 24, right: 32)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 130),
            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Markee"
        panel.contentView = stack
        panel.center()
        // No close button: styleMask is `.titled` only (no `.closable`), so the
        // panel can't be dismissed mid-update — which would orphan the download.
    }

    func show() { panel.makeKeyAndOrderFront(nil) }
    func setMessage(_ text: String) { label.stringValue = text }
    func close() { panel.close() }
}

@MainActor
final class Updater {
    static let shared = Updater()

    private let repo = "sethbang/markee"
    private var isRunning = false
    private var isInstalling = false

    private static let lastCheckKey = "MarkeeLastUpdateCheck"
    private static let skippedVersionKey = "MarkeeSkippedVersion"

    private init() {}

    static var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private var currentVersion: AppVersion {
        AppVersion(Self.currentVersionString) ?? AppVersion("0.0.0")!
    }

    /// Once-a-day silent launch check. Throttled by a UserDefaults timestamp.
    func checkOnLaunch() {
        guard SettingsStore.shared.updateCheckEnabled else { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        Task { await check(userInitiated: false) }
    }

    /// "Check for Updates…" menu action. Always reports its result.
    func checkForUpdatesMenuAction() {
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        guard !isRunning, !isInstalling else { return }
        isRunning = true
        defer { isRunning = false }

        let release: GitHubRelease
        do {
            release = try await Self.fetchLatestRelease(repo: repo)
        } catch {
            if userInitiated {
                presentError(error.localizedDescription)
            }
            return
        }
        // Stamp the throttle only after a successful fetch, so a check that
        // fails (offline, GitHub down) is retried on the next launch rather
        // than suppressed for 24h.
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

        guard release.version > currentVersion else {
            if userInitiated { presentUpToDate() }
            return
        }

        if !userInitiated,
           UserDefaults.standard.string(forKey: Self.skippedVersionKey) == release.tagName {
            return
        }

        presentUpdateAvailable(release)
    }

    nonisolated static func fetchLatestRelease(repo: String) async throws -> GitHubRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError.badResponse
        }
        guard let release = GitHubRelease(json: data) else {
            throw UpdaterError.unparseable
        }
        return release
    }

    // MARK: - UI

    func presentUpdateAvailable(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "A new version of Markee is available"
        var info = "Markee \(release.tagName) is available — you have \(Self.currentVersionString)."
        if !release.notes.isEmpty {
            let notes = release.notes.count > 500
                ? String(release.notes.prefix(500)) + "…"
                : release.notes
            info += "\n\n" + notes
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await installUpdate(release) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.tagName, forKey: Self.skippedVersionKey)
        default:
            break  // Remind Me Later — nothing persisted; the next check re-offers.
        }
    }

    func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Markee \(Self.currentVersionString) is the latest version."
        alert.runModal()
    }

    func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = message
        alert.runModal()
    }

    /// Used when self-replace can't proceed (read-only location, bad download).
    /// Sends the user to the release page to update by hand.
    func presentManualFallback(_ release: GitHubRelease, reason: String) {
        let alert = NSAlert()
        alert.messageText = "Update Markee manually"
        alert.informativeText = "\(reason)\n\nOpen the download page to get \(release.tagName) in your browser."
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
    }

    // MARK: - Download / stage

    /// Run a subprocess to completion; throw if it exits non-zero.
    nonisolated static func runProcess(_ launchPath: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdaterError.subprocessFailed }
    }

    /// Download `Markee.app.zip`, unzip it with `ditto`, and validate the
    /// result. Returns the URL of the staged, validated `Markee.app`. Runs off
    /// the main actor — the unzip is blocking work.
    nonisolated static func downloadAndStage(_ release: GitHubRelease) async throws -> URL {
        let (tempZip, response) = try await URLSession.shared.download(from: release.zipURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError.downloadFailed
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("markee-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            let zipURL = work.appendingPathComponent("Markee.app.zip")
            try FileManager.default.moveItem(at: tempZip, to: zipURL)

            // `ditto` unzips reliably, preserving the bundle's symlinks/structure.
            try runProcess("/usr/bin/ditto", ["-x", "-k", zipURL.path, work.path])

            let bundle = work.appendingPathComponent("Markee.app")
            try validateStagedBundle(bundle, expectedVersion: release.version)
            return bundle
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    /// Code requirement every update must satisfy: signed by Apple-issued
    /// Developer ID Application certificate of Markee's team, with Markee's
    /// bundle id. HTTPS alone only proves the bytes came from GitHub — this
    /// proves they came from us, so a hijacked release can't ship a foreign app.
    nonisolated static let updateRequirement = """
        anchor apple generic and identifier "com.markee.preview" \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and certificate leaf[subject.OU] = "N8427TN2XH"
        """

    /// Validate a staged `Markee.app` before it may replace the running app:
    /// executable present, bundle id and version as expected, and a strict
    /// (all architectures, nested code) signature check against `requirement`.
    nonisolated static func validateStagedBundle(
        _ bundle: URL,
        expectedVersion: AppVersion,
        bundleID: String = "com.markee.preview",
        requirement: String = updateRequirement
    ) throws {
        let exec = bundle.appendingPathComponent("Contents/MacOS/Markee")
        guard FileManager.default.isExecutableFile(atPath: exec.path) else {
            throw UpdaterError.invalidBundle
        }
        let infoPlist = bundle.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoPlist),
              info["CFBundleIdentifier"] as? String == bundleID,
              let versionString = info["CFBundleShortVersionString"] as? String,
              let parsed = AppVersion(versionString),
              parsed == expectedVersion else {
            throw UpdaterError.invalidBundle
        }

        var code: SecStaticCode?
        var req: SecRequirement?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req
        else { throw UpdaterError.invalidBundle }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidityWithErrors(code, flags, req, nil) == errSecSuccess else {
            throw UpdaterError.invalidBundle
        }
    }

    // MARK: - Install

    func installUpdate(_ release: GitHubRelease) async {
        // `isRunning` only covers the check; a second "Update Now" (from a
        // later check) must not start a parallel download + swap.
        guard !isInstalling else { return }
        isInstalling = true
        defer { isInstalling = false }
        let installPath = Bundle.main.bundlePath
        let parent = (installPath as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else {
            presentManualFallback(release, reason: "Markee can't replace itself from this location.")
            return
        }

        let progress = UpdateProgressPanel()
        progress.show()

        let stagedBundle: URL
        do {
            stagedBundle = try await Self.downloadAndStage(release)
        } catch {
            progress.close()
            presentManualFallback(release, reason: error.localizedDescription)
            return
        }

        progress.setMessage("Installing update…")
        do {
            try Self.stripQuarantine(stagedBundle)
            try Self.launchSwapHelper(newBundle: stagedBundle, installPath: installPath)
        } catch {
            progress.close()
            presentManualFallback(release, reason: error.localizedDescription)
            return
        }

        // The helper waits for this process to exit, then swaps and relaunches.
        NSApp.terminate(nil)
    }

    nonisolated static func stripQuarantine(_ bundle: URL) throws {
        try runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", bundle.path])
    }

    /// The detached swap helper: waits for this process (`$1`) to quit, swaps
    /// `$2` into `$3` keeping a `.old` backup until success, and relaunches
    /// (with `$4`, default `open`).
    /// If the app is still running after ~60 s it gives up without touching
    /// the installed copy — replacing a live bundle corrupts it. Exits 0 on
    /// success, 1 on a recoverable failure (previous version restored), 2 if
    /// restoring failed (backup left in place), 3 if the app never quit.
    nonisolated static let swapScript = """
        #!/bin/bash
        PID="$1"; NEW="$2"; DEST="$3"; OPEN="${4:-open}"   # $4: tests stub out relaunch
        trap 'rm -f "$0"' EXIT
        WAITED=0
        while kill -0 "$PID" 2>/dev/null; do
          sleep 0.2
          WAITED=$((WAITED + 1))
          if [ "$WAITED" -ge 300 ]; then
            osascript -e "display alert \\"Markee update not installed\\" message \\"Markee didn't quit, so the update was skipped. Quit Markee and check for updates again.\\"" 2>/dev/null || true
            exit 3
          fi
        done
        BACKUP="${DEST}.old"
        rm -rf "$BACKUP"
        if ! mv "$DEST" "$BACKUP"; then
          "$OPEN" "$DEST" 2>/dev/null || true
          exit 1
        fi
        if /usr/bin/ditto "$NEW" "$DEST"; then
          rm -rf "$BACKUP"
          rm -rf "$(dirname "$NEW")"
          "$OPEN" "$DEST"
        else
          rm -rf "$DEST"
          if ! mv "$BACKUP" "$DEST"; then
            osascript -e "display alert \\"Markee update failed\\" message \\"Could not restore Markee. Your previous version is saved at: $BACKUP\\"" 2>/dev/null || true
            exit 2
          fi
          "$OPEN" "$DEST"
          exit 1
        fi
        """

    /// Write `swapScript` to a temp file and launch it detached. It outlives
    /// this process by design — not waited on.
    nonisolated static func launchSwapHelper(newBundle: URL, installPath: String) throws {
        let script = swapScript
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("markee-swap-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            newBundle.path,
            installPath,
        ]
        try process.run()
        // Intentionally not waited on — it must outlive this process.
    }
}

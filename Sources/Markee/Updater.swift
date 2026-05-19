import Foundation

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

import AppKit
import Combine
import Foundation

enum SupportConfig {
    static let productionOrganizationID = "c183b314-d233-473e-8efb-4f2c9ff5061f"
    static let productionBaseURL = "https://api.polar.sh"

    static let checkoutURL = URL(string: "https://markee.sbang.dev/support")!

    // Polar never surfaces this in the dashboard — it's derived from the org
    // slug. Customers sign in with an email one-time code, then manage (and
    // deactivate) their license-key activations.
    static let customerPortalURL = "https://polar.sh/sbang/portal"

    // Sandbox/e2e override, resolved from the environment at call time. Unset on
    // a normal install, so the production constants are used. These exist only
    // to point a local build at the Polar sandbox during testing; shipping the
    // capability is harmless because faking supporter status is meaningless for
    // an ungated honor-system feature (UserDefaults is already user-editable).
    static func resolveOrganizationID(env: [String: String]) -> String {
        if let o = env["MARKEE_POLAR_ORG_ID"], !o.isEmpty { return o }
        return productionOrganizationID
    }

    static func resolveBaseURL(env: [String: String]) -> String {
        let raw: String
        if let s = env["MARKEE_POLAR_BASE_URL"], !s.isEmpty {
            raw = s
        } else {
            raw = productionBaseURL
        }
        var base = raw
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    static var polarOrganizationID: String {
        resolveOrganizationID(env: ProcessInfo.processInfo.environment)
    }

    static var polarBaseURL: String {
        resolveBaseURL(env: ProcessInfo.processInfo.environment)
    }

    // Dev-only preview switch (see `just reset-nudges`): forces the nudges on
    // immediately, skipping the grace period and the org-configured gate.
    // Harmless to ship — it only makes a non-supporter see the nudges sooner.
    static func resolveForceNudges(env: [String: String]) -> Bool {
        let v = env["MARKEE_FORCE_NUDGES"]
        return v == "1" || v == "true"
    }

    static var forceNudges: Bool {
        resolveForceNudges(env: ProcessInfo.processInfo.environment)
    }

    static func resolveDevTools(env: [String: String]) -> Bool {
        let v = env["MARKEE_DEV_TOOLS"]
        return v == "1" || v == "true"
    }

    static var devTools: Bool {
        resolveDevTools(env: ProcessInfo.processInfo.environment)
    }

    static func resolveForceSupporter(env: [String: String]) -> Bool {
        let v = env["MARKEE_FORCE_SUPPORTER"]
        return v == "1" || v == "true"
    }

    static var forceSupporter: Bool {
        resolveForceSupporter(env: ProcessInfo.processInfo.environment)
    }
}

@MainActor
final class SupportController: ObservableObject {
    static let shared = SupportController()

    @Published private(set) var isSupporter: Bool = false
    // Ambient titlebar affordance: always present for a non-supporter once
    // nudges are active, and removed the moment they become a supporter.
    @Published private(set) var showSupportButton: Bool = false

    private let defaults: UserDefaults
    private let now: () -> Date
    // Nudges stay dormant until a Polar org is wired in. This keeps a build
    // that ships before SupportConfig.productionOrganizationID is filled in from
    // steering users to a checkout/activation that dead-ends at "isn't configured."
    private let isConfigured: () -> Bool
    private let forceNudges: Bool

    // Nudges are live when a Polar org is configured, or when the dev preview
    // switch is on.
    var nudgesActive: Bool { isConfigured() || forceNudges }

    private enum Keys {
        static let licenseKey = "support.licenseKey"
        static let activationID = "support.activationId"
        static let active = "support.active"
        static let firstLaunchDate = "support.firstLaunchDate"
        static let launchCount = "support.launchCount"
        static let lastSupportDocShownDate = "support.lastSupportDocShownDate"
    }

    init(defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         isConfigured: @escaping () -> Bool = { !SupportConfig.polarOrganizationID.isEmpty },
         forceNudges: Bool = SupportConfig.forceNudges,
         forceSupporter: Bool = SupportConfig.forceSupporter) {
        self.defaults = defaults
        self.now = now
        self.isConfigured = isConfigured
        self.forceNudges = forceNudges
        let state = loadState()
        isSupporter = state.isSupporter || forceSupporter
        refreshSupportButton()
    }

    private func refreshSupportButton() {
        showSupportButton = nudgesActive && !isSupporter
    }

    private func loadState() -> SupportNudgeState {
        SupportNudgeState(
            isSupporter: defaults.bool(forKey: Keys.active),
            firstLaunchDate: defaults.object(forKey: Keys.firstLaunchDate) as? Date,
            launchCount: defaults.integer(forKey: Keys.launchCount),
            lastSupportDocShownDate: defaults.object(forKey: Keys.lastSupportDocShownDate) as? Date)
    }

    func registerLaunch() {
        if defaults.object(forKey: Keys.firstLaunchDate) as? Date == nil {
            defaults.set(now(), forKey: Keys.firstLaunchDate)
        }
        defaults.set(defaults.integer(forKey: Keys.launchCount) + 1, forKey: Keys.launchCount)
    }

    /// True at most once per doc quiet-period; stamps the shown date when it
    /// fires so callers can't double-open.
    func consumeSupportDocTrigger() -> Bool {
        guard nudgesActive,
              loadState().shouldOpenSupportDoc(now: now(), ignoringGracePeriod: forceNudges) else {
            return false
        }
        defaults.set(now(), forKey: Keys.lastSupportDocShownDate)
        return true
    }

    func markSupporter(key: String, activationID: String) {
        defaults.set(key, forKey: Keys.licenseKey)
        defaults.set(activationID, forKey: Keys.activationID)
        defaults.set(true, forKey: Keys.active)
        isSupporter = true
        refreshSupportButton()
    }

    func setSupporter(_ on: Bool) {
        defaults.set(on, forKey: Keys.active)
        isSupporter = on
        refreshSupportButton()
    }

    func resetNudgeTimers() {
        defaults.removeObject(forKey: Keys.firstLaunchDate)
        defaults.removeObject(forKey: Keys.launchCount)
        defaults.removeObject(forKey: Keys.lastSupportDocShownDate)
    }

    func debugStateSummary() -> String {
        let org = SupportConfig.polarOrganizationID
        return """
        isSupporter: \(isSupporter)
        showSupportButton: \(showSupportButton)
        nudgesActive: \(nudgesActive)
        persisted support.active: \(defaults.bool(forKey: Keys.active))
        MARKEE_FORCE_SUPPORTER: \(SupportConfig.forceSupporter)
        MARKEE_FORCE_NUDGES: \(SupportConfig.forceNudges)
        activationId: \(defaults.string(forKey: Keys.activationID) ?? "none")
        organization: \(org.isEmpty ? "unconfigured" : org)
        base URL: \(SupportConfig.polarBaseURL)

        heart: \(heartExplanation)
        """
    }

    /// The heart has two independent gates, and "toggled supporter off but no
    /// heart" is confusing without naming which one is holding it down.
    private var heartExplanation: String {
        if !nudgesActive {
            return "hidden — nudges inactive (org unconfigured and MARKEE_FORCE_NUDGES unset)"
        }
        return isSupporter ? "hidden — you're a supporter" : "visible"
    }

    /// Frees this Mac's activation slot. Run BEFORE `just reset` — wiping the
    /// defaults domain first strands the activation on Polar's side.
    func deactivateThisMac() async -> String {
        guard let key = defaults.string(forKey: Keys.licenseKey),
              let activationID = defaults.string(forKey: Keys.activationID) else {
            return "No stored key/activation on this Mac."
        }
        guard !SupportConfig.polarOrganizationID.isEmpty else {
            return "License activation isn't configured in this build."
        }
        guard let request = LicenseActivation.deactivateRequest(
            key: key,
            organizationID: SupportConfig.polarOrganizationID,
            activationID: activationID,
            baseURL: SupportConfig.polarBaseURL) else {
            return "Unexpected configuration."
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 404 means Polar has no such activation — already freed from the
            // portal. Clearing local state anyway is what stops a stale id from
            // stranding the slot forever.
            guard code == 204 || code == 200 || code == 404 else {
                return "Polar returned HTTP \(code)."
            }
            defaults.removeObject(forKey: Keys.activationID)
            defaults.removeObject(forKey: Keys.licenseKey)
            setSupporter(false)
            return code == 404
                ? "That activation was already gone on Polar. Cleared it locally."
                : "Deactivated. This Mac's slot is free."
        } catch {
            return "Couldn't reach Polar."
        }
    }

    nonisolated static func redeem(key: String, organizationID: String) async -> ActivationResult {
        guard !organizationID.isEmpty else {
            return .failure(message: "License activation isn't configured in this build.")
        }
        guard let request = LicenseActivation.activateRequest(
            key: key,
            organizationID: organizationID,
            label: LicenseActivation.deviceLabel(hostName: Host.current().localizedName),
            baseURL: SupportConfig.polarBaseURL) else {
            return .failure(message: "Unexpected configuration. Try again later.")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(message: "Unexpected response from Polar. Try again later.")
            }
            return LicenseActivation.parseActivationResponse(status: http.statusCode, data: data)
        } catch {
            return .failure(message: "Couldn't reach Polar — check your connection and try again.")
        }
    }
}

@MainActor
extension SupportController {
    func openCheckout() {
        NSWorkspace.shared.open(SupportConfig.checkoutURL)
    }

    func presentLicenseEntry() {
        let alert = NSAlert()
        alert.messageText = "Enter License Key"
        alert.informativeText = "Paste the license key from your Polar purchase email."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "Activate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Task { await redeem(key: key) }
    }

    func redeem(key: String) async {
        switch await Self.redeem(key: key, organizationID: SupportConfig.polarOrganizationID) {
        case .activated(let activationID):
            markSupporter(key: key, activationID: activationID)
            let alert = NSAlert()
            alert.messageText = "Thank you ❤️"
            alert.informativeText = "You're a Markee supporter. The nudges are gone for good."
            alert.runModal()
        case .limitReached(let detail):
            let alert = NSAlert()
            alert.messageText = "Couldn't Activate This Mac"
            let reason = detail.map { "Polar said: \($0)\n\n" } ?? ""
            alert.informativeText = reason
                + "This usually means the key is already active on \(LicenseActivation.deviceLimit) Macs. "
                + "Deactivate one in the Polar customer portal, then try again."
            alert.addButton(withTitle: "OK")
            if let portal = URL(string: SupportConfig.customerPortalURL), !SupportConfig.customerPortalURL.isEmpty {
                alert.addButton(withTitle: "Manage Devices")
                if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(portal) }
            } else {
                alert.runModal()
            }
        case .invalid(let message):
            let alert = NSAlert()
            alert.messageText = "Key Not Accepted"
            alert.informativeText = message
            alert.runModal()
        case .failure(let message):
            let alert = NSAlert()
            alert.messageText = "Couldn't Activate"
            alert.informativeText = message
            alert.runModal()
        }
    }
}

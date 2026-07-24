import Foundation

enum ActivationResult: Equatable {
    case activated(activationID: String)
    /// `detail` carries Polar's own explanation when it sends one. We can't
    /// distinguish every 4xx cause from the status code alone, so we quote the
    /// server rather than asserting a cause we haven't confirmed.
    case limitReached(detail: String?)
    case invalid(message: String)
    case failure(message: String)
}

/// Pure wire format for Polar's customer-portal license endpoints. All
/// persistence and UI live in SupportController; this exists so the request
/// shape and response parsing are testable without a network.
enum LicenseActivation {
    static let deviceLimit = 3

    private static let unexpected = "Unexpected response from Polar. Try again later."
    private static let badKey = "That key doesn't look valid. Check your purchase email and try again."

    /// Polar requires a non-empty label; it names the device in the customer
    /// portal's deactivation list, so a real machine name is worth sending.
    static func deviceLabel(hostName: String?) -> String {
        guard let name = hostName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return "Mac" }
        return name
    }

    /// Deliberately NOT shared with the deleted validate parser: the two
    /// endpoints disagree on what 422 means, and any unclassified 4xx here is
    /// far more likely to be the activation limit than a bad key.
    static func parseActivationResponse(status: Int, data: Data) -> ActivationResult {
        switch status {
        case 200:
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let activationID = obj["id"] as? String,
                  let licenseKey = obj["license_key"] as? [String: Any],
                  let keyStatus = licenseKey["status"] as? String else {
                return .failure(message: unexpected)
            }
            switch keyStatus {
            case "granted":
                return .activated(activationID: activationID)
            case "revoked", "disabled":
                return .invalid(message: "This license key has been \(keyStatus).")
            default:
                return .failure(message: unexpected)
            }
        // 403 = {"error":"NotPermitted","detail":"License key activation limit
        // already reached"} — confirmed against the sandbox, not inferred.
        case 403:
            return .limitReached(detail: serverDetail(data))
        case 404:
            return .invalid(message: badKey)
        case 422:
            return .failure(message: unexpected)
        case 429:
            return .failure(message: "Polar is rate-limiting requests right now. Wait a moment and try again.")
        // Every 4xx used to fall through to .limitReached, which reported a
        // rate-limit as "already active on 3 Macs". With 403 pinned down, an
        // unclassified 4xx quotes Polar instead of inventing a cause.
        case 400...499:
            return .failure(message: serverDetail(data) ?? unexpected)
        default:
            return .failure(message: "Couldn't reach Polar (HTTP \(status)). Try again later.")
        }
    }

    /// Polar reports the specific reason in `detail` (sometimes `error`). The
    /// activation limit is only the most likely cause of an unclassified 4xx,
    /// not the only one, so surfacing this beats inventing a cause.
    static func serverDetail(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["detail", "error"] {
            if let text = obj[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    static func activateRequest(key: String, organizationID: String, label: String, baseURL: String) -> URLRequest? {
        request(path: "/v1/customer-portal/license-keys/activate",
                baseURL: baseURL,
                body: ["key": key, "organization_id": organizationID, "label": label])
    }

    static func deactivateRequest(key: String, organizationID: String, activationID: String, baseURL: String) -> URLRequest? {
        request(path: "/v1/customer-portal/license-keys/deactivate",
                baseURL: baseURL,
                body: ["key": key, "organization_id": organizationID, "activation_id": activationID])
    }

    private static func request(path: String, baseURL: String, body: [String: String]) -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }
}

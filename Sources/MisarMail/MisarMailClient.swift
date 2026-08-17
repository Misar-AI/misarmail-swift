import Foundation

// On Linux, URLSession/URLRequest/HTTPURLResponse live in FoundationNetworking
// rather than Foundation. Without this the module does not build there at all —
// HTTPURLResponse resolves to AnyObject and URLRequest is not in scope.
#if canImport(FoundationNetworking)
import FoundationNetworking

/// swift-corelibs-foundation has no async `data(for:)` or `bytes(for:)`, so the
/// client would not build on Linux. Bridging the completion-handler API keeps
/// the SDK one implementation on every platform instead of two behind `#if`.
extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, let response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(
                        throwing: URLError(.badServerResponse)
                    )
                }
            }
            task.resume()
        }
    }
}
#endif

// MisarMailError is declared in Errors.swift. A second, narrower copy used to
// live here, which made the module fail to compile with "invalid redeclaration".

// MARK: - Client

public final class MisarMailClient {

    public let apiKey: String
    public let baseURL: String
    public let maxRetries: Int
    public let session: URLSession

    private static let retryableStatuses: Set<Int> = [429, 500, 502, 503, 504]

    public init(
        apiKey: String,
        baseURL: String = "https://api.misar.io/mail/v1",
        maxRetries: Int = 3,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        let trimmed = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.baseURL = trimmed
        self.maxRetries = maxRetries
        self.session = session
    }

    /// Base for billing/workspaces — strips /v1 suffix.
    internal var apiBase: String {
        if baseURL.hasSuffix("/v1") {
            return String(baseURL.dropLast(3))
        }
        return baseURL
    }

    // MARK: Core request

    internal func request(
        method: String,
        path: String,
        body: [String: Any]? = nil,
        useApiBase: Bool = false
    ) async throws -> [String: Any] {
        let base = useApiBase ? apiBase : baseURL
        guard let url = URL(string: base + path) else {
            throw MisarMailError.networkError(message: "Invalid URL: \(base + path)")
        }

        var urlRequest = URLRequest(url: url, timeoutInterval: 30)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else if method == "POST" {
            urlRequest.httpBody = Data("{}".utf8)
        }

        var lastError: Error?

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                let delayNs = UInt64(500_000_000) * UInt64(1 << (attempt - 1))
                try await Task.sleep(nanoseconds: delayNs)
            }

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch {
                lastError = error
                continue
            }

            guard let http = response as? HTTPURLResponse else {
                lastError = MisarMailError.networkError(message: "Non-HTTP response")
                continue
            }

            let status = http.statusCode

            // A rate-limit 429 and a spent-allowance 429 are identical by
            // status, so the body decides. Only the first is worth retrying.
            if Self.isPlanLimit(data) {
                throw Self.parsePlanLimit(status: status, data: data, response: http)
            }

            if Self.retryableStatuses.contains(status) && attempt < maxRetries - 1 {
                lastError = MisarMailError.apiError(status: status, message: "retryable")
                continue
            }

            if (200..<300).contains(status) {
                if data.isEmpty { return [:] }
                guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return [:]
                }
                return parsed
            }

            let msg = extractError(from: data)
            throw MisarMailError.apiError(status: status, message: msg)
        }

        throw MisarMailError.networkError(message: "max retries exceeded: \(lastError?.localizedDescription ?? "unknown")")
    }

    private func extractError(from data: Data) -> String {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let msg = obj["error"] as? String
        else {
            return String(data: data, encoding: .utf8) ?? "error"
        }
        return msg
    }

    // MARK: - Resource accessors

    public var plan:         PlanResource { PlanResource(client: self) }
    public var streaming:    StreamingResource { StreamingResource(client: self) }
    public var ai:              AiResource { AiResource(client: self) }
    public var creditRates:     CreditRatesResource { CreditRatesResource(client: self) }
    public var deliverability:  DeliverabilityResource { DeliverabilityResource(client: self) }
    public var dmarc:           DmarcResource { DmarcResource(client: self) }
    public var emailAccounts:   EmailAccountsResource { EmailAccountsResource(client: self) }
    public var emails:          EmailsResource { EmailsResource(client: self) }
    public var landingPages:    LandingPagesResource { LandingPagesResource(client: self) }
    public var monetization:    MonetizationResource { MonetizationResource(client: self) }
    public var revenue:         RevenueResource { RevenueResource(client: self) }
    public var segments:        SegmentsResource { SegmentsResource(client: self) }
    public var subscription:    SubscriptionResource { SubscriptionResource(client: self) }
    public var teamMembers:     TeamMembersResource { TeamMembersResource(client: self) }
    public var wallet:          WalletResource { WalletResource(client: self) }
    public var warmup:          WarmupResource { WarmupResource(client: self) }
    public var email:        EmailResource { EmailResource(client: self) }
    public var contacts:     ContactsResource { ContactsResource(client: self) }
    public var campaigns:    CampaignsResource { CampaignsResource(client: self) }
    public var templates:    TemplatesResource { TemplatesResource(client: self) }
    public var automations:  AutomationsResource { AutomationsResource(client: self) }
    public var domains:      DomainsResource { DomainsResource(client: self) }
    public var aliases:      AliasesResource { AliasesResource(client: self) }
    public var dedicatedIPs: DedicatedIPsResource { DedicatedIPsResource(client: self) }
    public var abTests:      ABTestsResource { ABTestsResource(client: self) }
    public var sandbox:      SandboxResource { SandboxResource(client: self) }
    public var inbound:      InboundResource { InboundResource(client: self) }
    public var analytics:    AnalyticsResource { AnalyticsResource(client: self) }
    public var track:        TrackResource { TrackResource(client: self) }
    public var keys:         KeysResource { KeysResource(client: self) }
    public var validate:     ValidateResource { ValidateResource(client: self) }
    public var webhooks:     WebhooksResource { WebhooksResource(client: self) }
    public var usage:        UsageResource { UsageResource(client: self) }
    public var billing:      BillingResource { BillingResource(client: self) }
    public var workspaces:   WorkspacesResource { WorkspacesResource(client: self) }
}

// MARK: - EmailResource

public class EmailResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// POST /send
    public func send(_ data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/send", body: data)
    }
}

// MARK: - ContactsResource

public class ContactsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /contacts
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/contacts?\($0)" } ?? "/contacts"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /contacts
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/contacts", body: data)
    }

    /// GET /contacts/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/contacts/\(id)")
    }

    /// PATCH /contacts/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/contacts/\(id)", body: data)
    }

    /// DELETE /contacts/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/contacts/\(id)")
    }

    /// POST /contacts/import
    public func importContacts(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/contacts/import", body: data)
    }
}

// MARK: - CampaignsResource

public class CampaignsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /campaigns
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/campaigns?\($0)" } ?? "/campaigns"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /campaigns
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/campaigns", body: data)
    }

    /// GET /campaigns/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/campaigns/\(id)")
    }

    /// PATCH /campaigns/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/campaigns/\(id)", body: data)
    }

    /// POST /campaigns/{id}/send
    public func sendCampaign(id: String) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/campaigns/\(id)/send")
    }

    /// DELETE /campaigns/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/campaigns/\(id)")
    }
}

// MARK: - TemplatesResource

public class TemplatesResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /templates
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/templates")
    }

    /// POST /templates
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/templates", body: data)
    }

    /// GET /templates/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/templates/\(id)")
    }

    /// PATCH /templates/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/templates/\(id)", body: data)
    }

    /// DELETE /templates/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/templates/\(id)")
    }

    /// POST /templates/render
    public func render(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/templates/render", body: data)
    }
}

// MARK: - AutomationsResource

public class AutomationsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /automations
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/automations?\($0)" } ?? "/automations"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /automations
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/automations", body: data)
    }

    /// GET /automations/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/automations/\(id)")
    }

    /// PATCH /automations/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/automations/\(id)", body: data)
    }

    /// DELETE /automations/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/automations/\(id)")
    }

    /// POST /automations/{id}/activate
    public func activate(id: String, active: Bool) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/automations/\(id)/activate", body: ["active": active])
    }
}

// MARK: - DomainsResource

public class DomainsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /domains
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/domains")
    }

    /// POST /domains
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/domains", body: data)
    }

    /// GET /domains/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/domains/\(id)")
    }

    /// POST /domains/{id}/verify
    public func verify(id: String) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/domains/\(id)/verify")
    }

    /// DELETE /domains/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/domains/\(id)")
    }
}

// MARK: - AliasesResource

public class AliasesResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /aliases
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/aliases")
    }

    /// POST /aliases
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/aliases", body: data)
    }

    /// GET /aliases/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/aliases/\(id)")
    }

    /// PATCH /aliases/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/aliases/\(id)", body: data)
    }

    /// DELETE /aliases/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/aliases/\(id)")
    }
}

// MARK: - DedicatedIPsResource

public class DedicatedIPsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /dedicated-ips
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/dedicated-ips")
    }

    /// POST /dedicated-ips
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/dedicated-ips", body: data)
    }

    /// PATCH /dedicated-ips/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/dedicated-ips/\(id)", body: data)
    }

    /// DELETE /dedicated-ips/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/dedicated-ips/\(id)")
    }
}

// MARK: - ABTestsResource

public class ABTestsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /ab-tests
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/ab-tests")
    }

    /// POST /ab-tests
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/ab-tests", body: data)
    }

    /// GET /ab-tests/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/ab-tests/\(id)")
    }

    /// POST /ab-tests/{id}/winner
    public func setWinner(id: String, variantId: String) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/ab-tests/\(id)/winner", body: ["variantId": variantId])
    }
}

// MARK: - SandboxResource

public class SandboxResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// POST /sandbox/send
    public func send(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/sandbox/send", body: data)
    }

    /// GET /sandbox
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/sandbox?\($0)" } ?? "/sandbox"
        return try await client.request(method: "GET", path: path)
    }

    /// DELETE /sandbox/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/sandbox/\(id)")
    }
}

// MARK: - InboundResource

public class InboundResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /inbound
    public func list(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/inbound?\($0)" } ?? "/inbound"
        return try await client.request(method: "GET", path: path)
    }

    /// POST /inbound
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/inbound", body: data)
    }

    /// GET /inbound/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/inbound/\(id)")
    }

    /// DELETE /inbound/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/inbound/\(id)")
    }
}

// MARK: - AnalyticsResource

public class AnalyticsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /analytics
    public func overview(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/analytics?\($0)" } ?? "/analytics"
        return try await client.request(method: "GET", path: path)
    }
}

// MARK: - TrackResource

public class TrackResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// POST /track/event
    public func event(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/track/event", body: data)
    }

    /// POST /track/purchase
    public func purchase(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/track/purchase", body: data)
    }
}

// MARK: - KeysResource

public class KeysResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /keys
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/keys")
    }

    /// POST /keys
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/keys", body: data)
    }

    /// GET /keys/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/keys/\(id)")
    }

    /// DELETE /keys/{id}
    public func revoke(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/keys/\(id)")
    }
}

// MARK: - ValidateResource

public class ValidateResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// POST /validate
    public func email(address: String) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/validate", body: ["email": address])
    }
}

// MARK: - WebhooksResource

public class WebhooksResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /webhooks
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/webhooks")
    }

    /// POST /webhooks
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/webhooks", body: data)
    }

    /// GET /webhooks/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/webhooks/\(id)")
    }

    /// PATCH /webhooks/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/webhooks/\(id)", body: data)
    }

    /// DELETE /webhooks/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/webhooks/\(id)")
    }

    /// POST /webhooks/{id}/test
    public func test(id: String) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/webhooks/\(id)/test")
    }
}

// MARK: - UsageResource

public class UsageResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET /usage
    public func get(params: String? = nil) async throws -> [String: Any] {
        let path = params.map { "/usage?\($0)" } ?? "/usage"
        return try await client.request(method: "GET", path: path)
    }
}

// MARK: - BillingResource

public class BillingResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET {apiBase}/billing/subscription
    public func subscription() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/billing/subscription", useApiBase: true)
    }

    /// POST {apiBase}/billing/checkout
    public func checkout(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/billing/checkout", body: data, useApiBase: true)
    }
}

// MARK: - WorkspacesResource

public class WorkspacesResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// GET {apiBase}/workspaces
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/workspaces", useApiBase: true)
    }

    /// POST {apiBase}/workspaces
    public func create(data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/workspaces", body: data, useApiBase: true)
    }

    /// GET {apiBase}/workspaces/{id}
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/workspaces/\(id)", useApiBase: true)
    }

    /// PATCH {apiBase}/workspaces/{id}
    public func update(id: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/workspaces/\(id)", body: data, useApiBase: true)
    }

    /// DELETE {apiBase}/workspaces/{id}
    public func delete(id: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/workspaces/\(id)", useApiBase: true)
    }

    /// GET {apiBase}/workspaces/{wsId}/members
    public func listMembers(wsId: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/workspaces/\(wsId)/members", useApiBase: true)
    }

    /// POST {apiBase}/workspaces/{wsId}/members
    public func inviteMember(wsId: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/workspaces/\(wsId)/members", body: data, useApiBase: true)
    }

    /// PATCH {apiBase}/workspaces/{wsId}/members/{userId}
    public func updateMember(wsId: String, userId: String, data: [String: Any]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/workspaces/\(wsId)/members/\(userId)", body: data, useApiBase: true)
    }

    /// DELETE {apiBase}/workspaces/{wsId}/members/{userId}
    public func removeMember(wsId: String, userId: String) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/workspaces/\(wsId)/members/\(userId)", useApiBase: true)
    }
}

// MARK: - Plan limits

extension MisarMailClient {
    /// True when the body carries the API's plan-refusal marker.
    static func isPlanLimit(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return obj["code"] as? String == "plan_limit_exceeded"
            || obj["error_type"] as? String == "plan_limit_exceeded"
            || obj["upgrade"] is [String: Any]
    }

    static func parsePlanLimit(status: Int, data: Data, response: HTTPURLResponse) -> MisarMailError {
        parsePlanLimit(
            status: status,
            data: data,
            plan: response.value(forHTTPHeaderField: "X-Misar-Plan"),
            upgradeURL: response.value(forHTTPHeaderField: "X-Misar-Upgrade-Url"),
            retryAfter: response.value(forHTTPHeaderField: "Retry-After")
        )
    }

    /// Header-value overload, so the SSE delegate — which only ever holds the
    /// strings it captured — can build the same error.
    static func parsePlanLimit(
        status: Int,
        data: Data,
        plan planHeader: String?,
        upgradeURL upgradeHeader: String?,
        retryAfter retryAfterHeader: String?
    ) -> MisarMailError {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let offer = obj["upgrade"] as? [String: Any] ?? [:]

        // Headers are authoritative; the offer body is the fallback when a
        // proxy has stripped them.
        let plan = planHeader
            ?? offer["currentPlanSlug"] as? String
            ?? (offer["current_plan"] as? [String: Any])?["slug"] as? String
        let upgradeURL = upgradeHeader
            ?? (offer["urls"] as? [String: Any])?["pricing"] as? String

        return .planLimitExceeded(
            status: status,
            message: obj["error"] as? String ?? "plan limit exceeded",
            plan: plan,
            upgradeURL: upgradeURL,
            retryAfter: retryAfterHeader.flatMap(Int.init),
            feature: offer["feature"] as? String
        )
    }
}

// MARK: - PlanResource

/// Live subscription standing for the key's owner.
///
/// Read this before an expensive call rather than discovering the ceiling
/// through `MisarMailError.planLimitExceeded`: `usage` reports every metered
/// feature and `upgrade` is non-null as soon as one is spent.
public final class PlanResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /plan` — plan, allowances, per-feature usage, upgrade offer.
    public func get() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/plan")
    }

    /// `GET /monetization/stats` — revenue and monetization counters.
    public func monetization() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/monetization/stats")
    }
}

// ── Generated from scripts/sdk-endpoint-spec.json ────────────────────────────
//
// These twenty endpoints were missing from every SDK except TypeScript.

/// Renders `?a=b&c=d` for the pairs that are set, percent-encoding values.
func misarMailQuery(_ pairs: [(String, String?)]) -> String {
    let set = pairs.compactMap { name, value -> String? in
        guard let value else { return nil }
        let allowed = CharacterSet.urlQueryAllowed
        let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return "\(name)=\(v)"
    }
    return set.isEmpty ? "" : "?" + set.joined(separator: "&")
}

/// `ai` — generated.
public final class AiResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `POST /ai/subject-lines`
    public func subjectLines(body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/ai/subject-lines", body: body)
    }

}

/// `creditRates` — generated.
public final class CreditRatesResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /credit-rates`
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/credit-rates")
    }

}

/// `deliverability` — generated.
public final class DeliverabilityResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /deliverability/audit`
    public func audit() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/deliverability/audit")
    }

    /// `GET /deliverability/score`
    public func score() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/deliverability/score")
    }

}

/// `dmarc` — generated.
public final class DmarcResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /dmarc/check`
    public func check(domain: String? = nil, dkim_selector: String? = nil) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/dmarc/check" + misarMailQuery([("domain", domain), ("dkim_selector", dkim_selector)]))
    }

    /// `GET /dmarc/domains`
    public func listDomains() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/dmarc/domains")
    }

    /// `POST /dmarc/domains`
    public func addDomain(body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/dmarc/domains", body: body)
    }

    /// `DELETE /dmarc/domains`
    public func removeDomain(domain_id: String? = nil) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/dmarc/domains" + misarMailQuery([("domain_id", domain_id)]))
    }

}

/// `emailAccounts` — generated.
public final class EmailAccountsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /email-accounts`
    public func list() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/email-accounts")
    }

}

/// `emails` — generated.
public final class EmailsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /emails`
    public func list(folder: String? = nil, search: String? = nil, limit: Int? = nil) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/emails" + misarMailQuery([("folder", folder), ("search", search), ("limit", limit.map(String.init))]))
    }

    /// `GET /emails/:id`
    public func get(id: String) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/emails/\(id)")
    }

    /// `PATCH /emails/:id`
    public func update(id: String, body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "PATCH", path: "/emails/\(id)", body: body)
    }

}

/// `landingPages` — generated.
public final class LandingPagesResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `POST /landing-pages`
    public func create(body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/landing-pages", body: body)
    }

}

/// `monetization` — generated.
public final class MonetizationResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `POST /monetization/tip`
    public func tip(body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/monetization/tip", body: body)
    }

}

/// `revenue` — generated.
public final class RevenueResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /revenue/attribution`
    public func attribution(campaign_id: String? = nil, period: String? = nil) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/revenue/attribution" + misarMailQuery([("campaign_id", campaign_id), ("period", period)]))
    }

}

/// `segments` — generated.
public final class SegmentsResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /segments/:id/members`
    public func members(id: String, page: Int? = nil, limit: Int? = nil) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/segments/\(id)/members" + misarMailQuery([("page", page.map(String.init)), ("limit", limit.map(String.init))]))
    }

}

/// `subscription` — generated.
public final class SubscriptionResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /subscription`
    public func get(product: String? = nil) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/subscription" + misarMailQuery([("product", product)]))
    }

    /// `POST /subscription`
    public func upsert(body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/subscription", body: body)
    }

    /// `DELETE /subscription`
    public func cancel(body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "DELETE", path: "/subscription", body: body)
    }

}

/// `teamMembers` — generated.
public final class TeamMembersResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /team-members`
    public func get(owner_id: String? = nil) async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/team-members" + misarMailQuery([("owner_id", owner_id)]))
    }

}

/// `wallet` — generated.
public final class WalletResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /wallet`
    public func get() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/wallet")
    }

    /// `POST /wallet/credit`
    public func credit(body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/wallet/credit", body: body)
    }

    /// `POST /wallet/debit`
    public func debit(body: [String: Any] = [:]) async throws -> [String: Any] {
        try await client.request(method: "POST", path: "/wallet/debit", body: body)
    }

}

/// `warmup` — generated.
public final class WarmupResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `GET /warmup`
    public func get() async throws -> [String: Any] {
        try await client.request(method: "GET", path: "/warmup")
    }

}

// MARK: - Server-Sent Events

/// One decoded SSE frame.
///
/// MisarMail emits unnamed frames — `data: {...}` with no `event:` line — so
/// `event` is normally nil. `data` is the decoded JSON; `raw` is always the
/// payload exactly as received.
// `data` is a JSON dictionary of `Any`, which the compiler cannot prove
// Sendable. It is never mutated after init, so the guarantee holds by
// construction rather than by the type system.
public struct MisarMailStreamEvent: @unchecked Sendable {
    public let event: String?
    public let data: [String: Any]?
    public let raw: String
}

/// The two Server-Sent Events endpoints.
///
/// Both live outside `/v1`, so they use the API base. Both are API-key
/// authenticated and metered, so a plan refusal on open throws
/// `MisarMailError.planLimitExceeded` exactly as a non-streaming call would.
public final class StreamingResource {
    private let client: MisarMailClient
    init(client: MisarMailClient) { self.client = client }

    /// `POST /api/ai/generate-email/stream` — token-by-token generation.
    ///
    /// ```swift
    /// for try await frame in mail.streaming.generateEmail(["prompt": "…"]) {
    ///     print(frame.data?["delta"] as? String ?? "", terminator: "")
    /// }
    /// ```
    public func generateEmail(_ options: [String: Any]) -> AsyncThrowingStream<MisarMailStreamEvent, Error> {
        client.sseStream(method: "POST", path: "/ai/generate-email/stream", body: options)
    }

    /// `GET /api/campaigns/{id}/send-stream` — live send progress.
    public func campaignSend(_ campaignID: String) -> AsyncThrowingStream<MisarMailStreamEvent, Error> {
        let escaped = campaignID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? campaignID
        return client.sseStream(method: "GET", path: "/campaigns/\(escaped)/send-stream", body: nil)
    }
}

// MARK: - SSE transport

/// Bridges `URLSession`'s delegate callbacks into an async sequence of chunks.
///
/// `URLSession.bytes(for:)` would be far simpler, but it does not exist in
/// swift-corelibs-foundation — using it made the package Darwin-only. A data
/// delegate is available on every platform, so this is one implementation
/// rather than two behind `#if`.
final class SSEChunkDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let onResponse: (HTTPURLResponse) -> Void
    private let onChunk: (Data) -> Void
    private let onComplete: (Error?) -> Void

    init(
        onResponse: @escaping (HTTPURLResponse) -> Void,
        onChunk: @escaping (Data) -> Void,
        onComplete: @escaping (Error?) -> Void
    ) {
        self.onResponse = onResponse
        self.onChunk = onChunk
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            onResponse(http)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onChunk(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete(error)
    }
}

extension MisarMailClient {
    /// Opens an SSE connection and yields each frame as it arrives.
    ///
    /// Uses the API base, since both streaming routes sit outside `/v1`. The
    /// delegate hands over raw chunks rather than lines, so frames are found by
    /// buffering and splitting on the blank line; `data: [DONE]` ends the
    /// stream and is not yielded.
    ///
    /// Deliberately not retried: replaying a stream that failed mid-flight would
    /// duplicate whatever the caller already consumed.
    func sseStream(
        method: String,
        path: String,
        body: [String: Any]?
    ) -> AsyncThrowingStream<MisarMailStreamEvent, Error> {
        let apiBase = self.apiBase
        let apiKey = self.apiKey

        return AsyncThrowingStream { continuation in
            guard let url = URL(string: apiBase + path) else {
                continuation.finish(
                    throwing: MisarMailError.networkError(message: "Invalid URL: \(apiBase + path)")
                )
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
            }

            // All mutable parsing state is confined to this serial queue, so the
            // delegate callbacks never race with each other.
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1

            let state = SSEParseState()

            let delegate = SSEChunkDelegate(
                onResponse: { http in
                    state.status = http.statusCode
                    state.planHeader = http.value(forHTTPHeaderField: "X-Misar-Plan")
                    state.upgradeHeader = http.value(forHTTPHeaderField: "X-Misar-Upgrade-Url")
                    state.retryAfterHeader = http.value(forHTTPHeaderField: "Retry-After")
                },
                onChunk: { chunk in
                    // A refusal body is JSON, not SSE: collect it and report it
                    // once the transfer ends.
                    guard (200..<300).contains(state.status) else {
                        state.errorBody.append(chunk)
                        return
                    }
                    guard !state.finished else { return }
                    state.buffer.append(chunk)

                    while let frame = state.nextFrame() {
                        switch state.parse(frame) {
                        case .done:
                            state.finished = true
                            continuation.finish()
                            return
                        case .event(let event):
                            continuation.yield(event)
                        case .none:
                            continue
                        }
                    }
                },
                onComplete: { error in
                    guard !state.finished else { return }
                    state.finished = true

                    if let error {
                        continuation.finish(
                            throwing: MisarMailError.networkError(message: error.localizedDescription)
                        )
                        return
                    }
                    if state.status >= 400 {
                        continuation.finish(throwing: state.refusal())
                        return
                    }
                    // A trailing frame the server never closed with a blank line.
                    if case .event(let event) = state.parse(state.drain()) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                }
            )

            // The client's own configuration, not a fresh .default: it carries the
            // caller's timeouts, proxy settings and protocolClasses, so an
            // injected session's behaviour applies to streams too.
            let session = URLSession(
                configuration: self.session.configuration,
                delegate: delegate,
                delegateQueue: queue
            )
            let task = session.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                // Invalidation waits for the delegate queue to drain, and the
                // stream is normally finished from inside a delegate callback on
                // that very queue — calling it there deadlocks the queue and the
                // process never exits. Hand it to another thread.
                DispatchQueue.global().async { session.finishTasksAndInvalidate() }
            }
            task.resume()
        }
    }
}

/// Mutable SSE parse state, owned by the delegate's serial queue.
final class SSEParseState: @unchecked Sendable {
    enum Parsed {
        case event(MisarMailStreamEvent)
        case done
        case none
    }

    var status = 0
    var finished = false
    var buffer = Data()
    var errorBody = Data()
    var planHeader: String?
    var upgradeHeader: String?
    var retryAfterHeader: String?

    /// Pops the next complete frame, or nil when the buffer holds a partial one.
    func nextFrame() -> String? {
        let lf = Data("\n\n".utf8)
        let crlf = Data("\r\n\r\n".utf8)

        let lfRange = buffer.range(of: lf)
        let crlfRange = buffer.range(of: crlf)

        let chosen: Range<Data.Index>?
        switch (lfRange, crlfRange) {
        case (nil, nil):            chosen = nil
        case (let l?, nil):         chosen = l
        case (nil, let c?):         chosen = c
        case (let l?, let c?):      chosen = l.lowerBound <= c.lowerBound ? l : c
        }
        guard let range = chosen else { return nil }

        let frame = String(decoding: buffer[buffer.startIndex..<range.lowerBound])
        buffer.removeSubrange(buffer.startIndex..<range.upperBound)
        return frame
    }

    /// Whatever is left once the socket closes.
    func drain() -> String {
        let rest = String(decoding: buffer)
        buffer.removeAll()
        return rest
    }

    func parse(_ frame: String) -> Parsed {
        var eventName: String?
        var dataLines: [String] = []

        for rawLine in frame.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false
        ) {
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix(":") { continue }  // blank or keepalive
            if line.hasPrefix("event:") {
                eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                var rest = String(line.dropFirst(5))
                if rest.hasPrefix(" ") { rest.removeFirst() }
                dataLines.append(rest)
            }
        }

        guard !dataLines.isEmpty else { return .none }

        let raw = dataLines.joined(separator: "\n")
        if raw == "[DONE]" { return .done }

        let decoded = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]
        return .event(MisarMailStreamEvent(event: eventName, data: decoded, raw: raw))
    }

    /// Builds the error for a stream the server refused before any frame.
    func refusal() -> Error {
        if MisarMailClient.isPlanLimit(errorBody) {
            return MisarMailClient.parsePlanLimit(
                status: status,
                data: errorBody,
                plan: planHeader,
                upgradeURL: upgradeHeader,
                retryAfter: retryAfterHeader
            )
        }
        let raw = String(decoding: errorBody)
        var message = raw
        if let object = (try? JSONSerialization.jsonObject(with: errorBody)) as? [String: Any],
           let error = object["error"] as? String {
            message = error
        }
        return MisarMailError.apiError(status: status, message: message.isEmpty ? "stream error" : message)
    }
}

private extension String {
    /// UTF-8 decode that tolerates a multi-byte character split across chunks.
    init(decoding data: Data) {
        self = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}

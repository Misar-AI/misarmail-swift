import XCTest
@testable import MisarMail

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - URLSession stub

/// Intercepts requests and replays a scripted response.
///
/// SSE bodies are delivered as several `didLoad:` calls so a frame boundary
/// lands mid-chunk — the case where buffering bugs show up.
final class StubURLProtocol: URLProtocol {

    /// Response for the next request, keyed by URL path.
    struct Stub {
        var status: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        /// Delivered in order, one `didLoad:` per element.
        var pieces: [String] = []
    }

    static var stubs: [String: Stub] = [:]
    static var requestedPaths: [String] = []

    static func reset() {
        stubs = [:]
        requestedPaths = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        StubURLProtocol.requestedPaths.append(path)

        guard let stub = StubURLProtocol.stubs[path] else {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"error":"no stub for \#(path)"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.status,
            httpVersion: "HTTP/1.1", headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for piece in stub.pieces {
            client?.urlProtocol(self, didLoad: Data(piece.utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

final class MisarMailClientTests: XCTestCase {

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func client(maxRetries: Int = 1) -> MisarMailClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return MisarMailClient(
            apiKey: "test-key",
            maxRetries: maxRetries,
            session: URLSession(configuration: config)
        )
    }

    private func stub(_ path: String, status: Int = 200, headers: [String: String] = [:], _ body: String) {
        var merged = ["Content-Type": "application/json"]
        headers.forEach { merged[$0.key] = $0.value }
        StubURLProtocol.stubs[path] = .init(status: status, headers: merged, pieces: [body])
    }

    private func stubStream(_ path: String, pieces: [String]) {
        StubURLProtocol.stubs[path] = .init(
            status: 200,
            headers: ["Content-Type": "text/event-stream"],
            pieces: pieces
        )
    }

    // MARK: REST

    func testEmailSendReturnsParsedBody() async throws {
        stub("/mail/v1/send", #"{"success":true,"message_id":"msg_123"}"#)

        let result = try await client().email.send(["from": "a@b.com", "to": ["c@d.com"]])

        XCTAssertEqual(result["success"] as? Bool, true)
        XCTAssertEqual(result["message_id"] as? String, "msg_123")
    }

    func testContactsListReturnsData() async throws {
        stub("/mail/v1/contacts", #"{"data":[{"id":"c1","email":"a@b.com"}],"total":1}"#)

        let result = try await client().contacts.list()
        let data = result["data"] as? [[String: Any]]

        XCTAssertEqual(data?.first?["email"] as? String, "a@b.com")
    }

    func testPlanReportsTheSubscriptionBehindTheKey() async throws {
        stub("/mail/v1/plan", #"{"plan":{"slug":"pro"},"limits":{"emails_per_month":50000}}"#)

        let result = try await client().plan.get()
        let plan = result["plan"] as? [String: Any]

        XCTAssertEqual(plan?["slug"] as? String, "pro")
    }

    func testUnauthorizedThrowsWithStatus() async throws {
        stub("/mail/v1/contacts", status: 401, #"{"error":"unauthorized"}"#)

        do {
            _ = try await client().contacts.list()
            XCTFail("expected an error")
        } catch let error as MisarMailError {
            guard case .apiError(let status, _) = error else {
                return XCTFail("expected apiError, got \(error)")
            }
            XCTAssertEqual(status, 401)
        }
    }

    // MARK: Plan limits

    func testSpentAllowanceThrowsPlanLimitAndIsNotRetried() async throws {
        stub(
            "/mail/v1/campaigns",
            status: 429,
            headers: ["X-Misar-Plan": "starter", "Retry-After": "3600"],
            """
            {"code":"plan_limit_exceeded","error":"monthly campaign allowance spent",
             "upgrade":{"feature":"campaigns",
             "urls":{"pricing":"https://misarmail.com/pricing"}}}
            """
        )

        // maxRetries 3, so a plain retryable 429 would have been retried twice more.
        do {
            _ = try await client(maxRetries: 3).campaigns.create(data: ["name": "Blast"])
            XCTFail("expected a plan-limit error")
        } catch let error as MisarMailError {
            guard case .planLimitExceeded(let status, _, let plan, let upgradeURL, let retryAfter, let feature) = error else {
                return XCTFail("expected planLimitExceeded, got \(error)")
            }
            XCTAssertEqual(status, 429)
            XCTAssertEqual(plan, "starter")
            XCTAssertEqual(feature, "campaigns")
            XCTAssertEqual(retryAfter, 3600)
            XCTAssertEqual(upgradeURL, "https://misarmail.com/pricing")
        }

        // A spent allowance cannot be fixed by retrying.
        XCTAssertEqual(StubURLProtocol.requestedPaths.count, 1)
    }

    // MARK: Server-Sent Events

    func testGenerateEmailYieldsEachFrame() async throws {
        // The frame boundary between "Hel" and "lo" is split across two chunks.
        stubStream("/mail/ai/generate-email/stream", pieces: [
            "data: {\"delta\":\"Hel\"}\n",
            "\ndata: {\"delta\":\"lo\"}\n\n",
            ": keepalive\n\n",
            "data: {\"delta\":\"!\"}\n\n",
            "data: [DONE]\n\n",
        ])

        var deltas: [String] = []
        for try await frame in client().streaming.generateEmail(["prompt": "hi"]) {
            if let delta = frame.data?["delta"] as? String { deltas.append(delta) }
        }

        XCTAssertEqual(deltas, ["Hel", "lo", "!"])
    }

    func testStreamStopsAtDoneSentinel() async throws {
        stubStream("/mail/campaigns/camp1/send-stream", pieces: [
            "data: {\"sent\":1}\n\n",
            "data: [DONE]\n\n",
            "data: {\"sent\":999}\n\n",
        ])

        var seen: [String] = []
        for try await frame in client().streaming.campaignSend("camp1") {
            seen.append(frame.raw)
        }

        // Anything after the sentinel must never be delivered.
        XCTAssertEqual(seen, [#"{"sent":1}"#])
    }

    func testStreamUsesTheUnversionedApiBase() async throws {
        stubStream("/mail/campaigns/camp1/send-stream", pieces: ["data: [DONE]\n\n"])

        for try await _ in client().streaming.campaignSend("camp1") {}

        // Both SSE routes live outside /v1, so the path must not carry it.
        XCTAssertEqual(StubURLProtocol.requestedPaths, ["/mail/campaigns/camp1/send-stream"])
    }

    func testStreamRefusalThrowsPlanLimitBeforeAnyFrame() async throws {
        stub(
            "/mail/campaigns/locked/send-stream",
            status: 402,
            headers: ["X-Misar-Plan": "free"],
            """
            {"code":"plan_limit_exceeded","error":"streaming is not on your plan",
             "upgrade":{"feature":"campaign_streaming",
             "urls":{"pricing":"https://misarmail.com/pricing"}}}
            """
        )

        do {
            for try await _ in client().streaming.campaignSend("locked") {
                XCTFail("no frame should be delivered on a refusal")
            }
            XCTFail("expected a plan-limit error")
        } catch let error as MisarMailError {
            guard case .planLimitExceeded(let status, _, let plan, _, _, let feature) = error else {
                return XCTFail("expected planLimitExceeded, got \(error)")
            }
            XCTAssertEqual(status, 402)
            XCTAssertEqual(plan, "free")
            XCTAssertEqual(feature, "campaign_streaming")
        }
    }

    func testNonJSONStreamPayloadStillArrivesAsRaw() async throws {
        stubStream("/mail/campaigns/camp1/send-stream", pieces: [
            "data: not json\n\n",
            "data: [DONE]\n\n",
        ])

        var seen: [MisarMailStreamEvent] = []
        for try await frame in client().streaming.campaignSend("camp1") {
            seen.append(frame)
        }

        XCTAssertEqual(seen.count, 1)
        XCTAssertNil(seen.first?.data)
        XCTAssertEqual(seen.first?.raw, "not json")
    }
}

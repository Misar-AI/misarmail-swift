# MisarMail Swift SDK

> Send transactional email and run marketing campaigns from Swift — async/await on Apple platforms and Linux.

[![Swift](https://img.shields.io/badge/swift-5.9%2B-F05138)](https://swift.org)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)](https://github.com/Misar-AI/misarmail-swift)
[![platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-lightgrey)](https://github.com/Misar-AI/misarmail-swift)
[![license](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

**33 resource groups · 90 methods · SSE streaming · no dependencies beyond Foundation**

MisarMail is one API for both halves of your email: the receipts and password resets your product sends, and the campaigns, segments and automations your marketing team runs on the same contact list and the same verified domains.

macOS 12+, iOS 15+, tvOS 15+, watchOS 8+ and Linux. Because `URLSession.data(for:)` and `.bytes(for:)` do not exist in swift-corelibs-foundation, the package bridges the delegate API instead — one implementation, every platform.

---

## Install

### Package.swift

```swift
.package(url: "https://github.com/Misar-AI/misarmail-swift.git", from: "5.0.2")
```

and add the product to your target:

```swift
.product(name: "MisarMail", package: "misarmail-swift")
```

### Xcode

File → Add Package Dependencies → `https://github.com/Misar-AI/misarmail-swift.git`

> SwiftPM requires `Package.swift` at the repository root, so this SDK is mirrored to its
> own repository. The monorepo URL will not resolve.

---

## Authentication

Create a developer key at https://mail.misar.io/developers. It starts with `msk_` and is
sent as `Authorization: Bearer msk_…`.

Every call is metered against the subscription attached to that key. There is no
client-side limit checking — the server decides, and the SDK surfaces its answer. A plan
refusal answers **403** with `code: "plan_limit_exceeded"` and is never retried.

```swift
import MisarMail

let mail = MisarMailClient(apiKey: ProcessInfo.processInfo.environment["MISARMAIL_API_KEY"]!)
```

---

## Resources

Every group the client exposes, and every public method on it.

### Send

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.email` | `send` | Transactional send — cc/bcc/reply-to, tags, metadata, `idempotency_key`. |
| `mail.sandbox` | `send`, `list`, `delete` | Test sends captured instead of delivered. |

### Campaigns and tests

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.campaigns` | `list`, `create`, `get`, `update`, `sendCampaign`, `delete` | Marketing campaigns: draft, edit, queue for send. |
| `mail.abTests` | `list`, `create`, `get`, `setWinner` | Subject, content, send-time, from-name and preheader splits, and winner selection. |

### Audience

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.contacts` | `list`, `create`, `get`, `update`, `delete`, `importContacts` | Subscribers, plus bulk import. |
| `mail.segments` | `members` | Dynamic audience segments and their membership. |
| `mail.landingPages` | `create` | Hosted landing pages with an email capture form. |

### Content

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.templates` | `list`, `create`, `get`, `update`, `delete`, `render` | Reusable templates and server-side variable rendering. |
| `mail.ai` | `subjectLines` | AI-generated subject lines. |

### Automations

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.automations` | `list`, `create`, `get`, `update`, `delete`, `activate` | Trigger-based workflows — welcome series, drips, re-engagement. |

### Deliverability and sending infrastructure

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.domains` | `list`, `create`, `get`, `verify`, `delete` | Sending domains and their DNS verification. |
| `mail.dmarc` | `check`, `listDomains`, `addDomain`, `removeDomain` | Live SPF/DKIM/DMARC record checks and monitored domains. |
| `mail.deliverability` | `audit`, `score` | Deliverability score, audit and remediation guidance. |
| `mail.dedicatedIPs` | `list`, `create`, `update`, `delete` | Dedicated sending IPs. |
| `mail.warmup` | `get` | IP/domain warm-up progress and today's remaining capacity. |
| `mail.inbound` | `list`, `create`, `get`, `delete` | Inbound routing domains, so replies land in the unified inbox. |

### Mailbox and inbox

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.emails` | `list`, `get`, `update` | Stored messages in the mailbox. |
| `mail.emailAccounts` | `list` | Connected mailbox accounts. |

### Analytics and attribution

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.analytics` | `overview` | Delivery and engagement stats — aggregate, or one campaign. |
| `mail.track` | `event`, `purchase` | Custom events and ecommerce purchases. |
| `mail.revenue` | `attribution` | Revenue attributed back to email. |
| `mail.usage` | `get` | Metered usage for a period. |

### Validation

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.validate` | `email` | Address validation, and the credit balance behind it. |

### Plan, billing and credits

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.plan` | `get`, `monetization` | Current plan, quotas and monetization stats. |
| `mail.billing` | `subscription`, `checkout` | Subscription state and checkout. |
| `mail.subscription` | `get`, `upsert`, `cancel` | Subscription read/write and per-product plan limits. |
| `mail.wallet` | `get`, `credit`, `debit` | Credit balance, credit and debit. |
| `mail.creditRates` | `list` | What each metered action costs in credits. |
| `mail.teamMembers` | `get` | Team members on the account. |
| `mail.monetization` | `tip` | Newsletter tips. |

### Developer

| Resource | Methods | What it covers |
| --- | --- | --- |
| `mail.keys` | `list`, `create`, `get`, `revoke` | API keys — create, list, revoke. |
| `mail.webhooks` | `list`, `create`, `get`, `update`, `delete`, `test` | Webhook endpoints, plus a test delivery. |
| `mail.streaming` | `generateEmail`, `campaignSend` | The two Server-Sent Events endpoints. |

---

## Client

| Thing | Detail |
| --- | --- |
| Entry point | `MisarMailClient(apiKey:baseURL:maxRetries:session:)` — every resource is a computed property. |
| Defaults | `https://api.misar.io/mail/v1`, `maxRetries` 3, `URLSession.shared`. |
| Payloads | `[String: Any]` in and out. List filters go in as a raw query string (`params: "page=1&limit=50"`). |
| Transport | `URLRequest`, 30-second timeout; SSE reuses the same session configuration. |
| Retried | `429`, `500`, `502`, `503`, `504` and transport failures, 500 ms then 1 s. |
| Never retried | Plan refusals, and streams. |
| Errors | One `MisarMailError` enum: `.apiError`, `.planLimitExceeded`, `.networkError`. |
| Webhook verifier | Not shipped here — verify `HMAC-SHA256(timestamp + "." + rawBody)` yourself with CryptoKit's `HMAC<SHA256>` and a constant-time compare. (Go, Python, Ruby and Dart ship one.) |

---

## Quick start

```swift
import MisarMail

let mail = MisarMailClient(apiKey: ProcessInfo.processInfo.environment["MISARMAIL_API_KEY"]!)

let sent = try await mail.email.send([
    "from": ["email": "you@yourdomain.com", "name": "Your App"],
    "to": [["email": "someone@example.com"]],
    "subject": "Hello",
    "html": "<p>Hi there</p>",
])

print(sent["message_id"] as? String ?? "")
```

## Primary functions

### Send a transactional email

`from` is a single address dictionary and `to` is an array of them. Pass an
`idempotency_key` and a retry can never send twice — the response comes back with
`idempotent: true` the second time.

```swift
let res = try await mail.email.send([
    "from": ["email": "receipts@yourdomain.com", "name": "Acme"],
    "to": [["email": "customer@example.com"]],
    "reply_to": ["email": "support@yourdomain.com"],
    "subject": "Your receipt",
    "html": "<p>Thanks for your order.</p>",
    "text": "Thanks for your order.",
    "tags": ["receipt"],
    "metadata": ["order_id": "ord-1041"],
    "idempotency_key": "ord-1041-receipt",
])

res["message_id"] as? String   // "msg-…"
```

### List and create contacts

Responses are enveloped. `list` returns `success`, `data` and `pagination`, and takes its
filters as a raw query string; `create` returns `success` and `data`, with the contact
under `data`.

```swift
let page = try await mail.contacts.list(params: "page=1&limit=50&status=subscribed")
let rows = page["data"] as? [[String: Any]] ?? []
let pagination = page["pagination"] as? [String: Any] ?? [:]
print("\(rows.count) of \(pagination["total"] ?? 0)")

let created = try await mail.contacts.create(data: [
    "email": "new@example.com",
    "firstName": "Ada",
    "lastName": "Lovelace",
    "tags": ["beta"],
    "customFields": ["plan": "pro"],
])

print((created["data"] as? [String: Any])?["id"] as? String ?? "")
```

`get(id:)` and `delete(id:)` take the contact id, which the route reads from the query
string rather than a path segment. `update` is different again: it identifies the contact
by **email address**, not by id.

```swift
_ = try await mail.contacts.update(email: "ada@example.com", data: ["status": "unsubscribed"])
```

### Bulk import contacts

The method is `importContacts` — `import` is a Swift keyword. Counts come back under
`summary`, and `errors` is a separate list of messages.

```swift
let imported = try await mail.contacts.importContacts(data: [
    "contacts": [
        ["email": "a@example.com", "firstName": "A"],
        ["email": "b@example.com", "firstName": "B"],
    ],
    "updateExisting": true,
])

imported["summary"]   // ["imported": …, "updated": …, "skipped": …, "errors": …]
imported["errors"]    // [String]
```

### Create and send a campaign

Campaigns take `fromName` and `fromEmail` as separate fields — there is no `from`
dictionary here, unlike `email.send`. `sendCampaign` queues it and reports it as
`scheduled`.

```swift
let campaign = try await mail.campaigns.create(data: [
    "name": "March launch",
    "subject": "We just shipped",
    "fromName": "Ada at Acme",
    "fromEmail": "hello@yourdomain.com",
    "replyTo": "support@yourdomain.com",
    "bodyHtml": "<h1>It's live</h1>",
    "segmentId": "seg-123",
])

let id = (campaign["data"] as? [String: Any])?["id"] as? String ?? ""
let queued = try await mail.campaigns.sendCampaign(id: id)
print("\(queued["campaignId"] ?? "") \(queued["status"] ?? "")")   // … scheduled
```

Only `draft`, `scheduled` or `paused` campaigns can be updated, and only `draft`
campaigns can be deleted.

### Validate an address

Each call spends a credit, and the response tells you what is left.

```swift
let check = try await mail.validate.email(address: "someone@example.com")
let verdict = check["data"] as? [String: Any] ?? [:]

verdict["is_valid"] as? Bool
verdict["score"] as? Double                                    // 0–1 confidence
verdict["checks"]                                              // syntax, mx, smtp
(verdict["flags"] as? [String: Any])?["disposable"] as? Bool
(check["credits"] as? [String: Any])?["balance_after"]         // credits remaining
```

### Render a template

```swift
let rendered = try await mail.templates.render(data: [
    "template_id": "tpl-123",
    "variables": ["name": "Ada", "plan": "Pro"],
])

(rendered["data"] as? [String: Any])?["subject"] as? String   // "Welcome, Ada"
```

### Track events and revenue

The event name field is `event_name`, and purchase totals are integer **cents** in
`total_cents`.

```swift
_ = try await mail.track.event(data: [
    "email": "customer@example.com",
    "event_name": "viewed_pricing",
    "event_data": ["plan": "pro"],
])

let purchase = try await mail.track.purchase(data: [
    "email": "customer@example.com",
    "order_id": "ord-1041",
    "total_cents": 9900,
    "currency": "USD",
    "items": [["name": "Pro annual", "quantity": 1, "price_cents": 9900]],
])

purchase["attribution"]   // which campaign or automation earned it
```

### Read analytics and manage keys

Without `campaignId` you get aggregate usage and totals for the period; with one you get
that campaign's stats and rates. `keys.list()` returns the keys under **`keys`**, not
`data`, and `create` returns the raw key exactly once.

```swift
let overall = try await mail.analytics.overview(params: "startDate=2026-04-01&endDate=2026-04-30")
let one = try await mail.analytics.overview(params: "campaignId=\(id)")

let keys = try await mail.keys.list()
(keys["keys"] as? [[String: Any]] ?? []).count

let fresh = try await mail.keys.create(data: ["name": "CI", "scopes": ["send", "read"]])
fresh["key"] as? String   // shown once and never again
```

## Errors

Everything the SDK throws is a `MisarMailError`:

| Case | When |
| --- | --- |
| `.apiError(status:message:)` | Any non-2xx API response. |
| `.planLimitExceeded(status:message:plan:upgradeURL:retryAfter:feature:)` | The subscription behind the key does not cover the call. |
| `.networkError(message:)` | The request never got an answer, or every retry was spent. |

`error.upgradeURL` returns the pricing URL for a plan refusal and `nil` for everything
else, so you can offer an upgrade without matching on the case. `MisarMailError`
conforms to `CustomStringConvertible`, so `error.description` is loggable as-is.

### Plan limits

Both a spent allowance and a feature that is not on the plan answer **`403`**, carrying
`code: "plan_limit_exceeded"`. The SDK keys on that code rather than the status, which is
why a refusal is typed correctly even though 403 is otherwise an authorization failure.
It throws `.planLimitExceeded` and **does not retry** — retrying cannot help until the
allowance resets or the plan changes. Read `upgradeURL` to send the user somewhere
useful.

```swift
do {
    _ = try await mail.campaigns.create(data: [
        "name": "Blast", "subject": "We just shipped",
        "fromName": "Your Name", "fromEmail": "you@yourdomain.com",
    ])
} catch MisarMailError.planLimitExceeded(_, _, let plan, let upgradeURL, let retryAfter, let feature) {
    print("\(feature ?? "?") exhausted on \(plan ?? "?"): \(upgradeURL ?? "")")
    // retryAfter is seconds until the allowance resets, when the API says so
}
```

`mail.plan.get()` returns `plan`, `sending` (the per-day and per-month email caps),
`usage` — an array with one entry per metered feature, each carrying `used`, `limit` and
`remaining` — and `upgrade`, which is null until a quota is tight. A null `limit` means
unlimited, and `remaining` is null alongside it rather than 0. Read it before an
expensive call rather than discovering the ceiling through a refusal.

The key needs the `read` or `subscription` scope.

```swift
let plan = try await mail.plan.get()
print(plan["sending"] ?? [:], plan["usage"] ?? [])
```

## Streaming

Two endpoints stream Server-Sent Events. Both sit **outside** `/v1`, which the SDK
handles for you:

| Method | Route |
| --- | --- |
| `streaming.generateEmail` | `POST /api/ai/generate-email/stream` |
| `streaming.campaignSend` | `GET /api/campaigns/{id}/send-stream` |

Frames are unnamed (`data: {…}`, with no `event:` line) and the stream ends with
`data: [DONE]`, which the SDK consumes rather than handing on. Each
`MisarMailStreamEvent` carries `event` (normally nil), `data` (the parsed dictionary, or
nil when the payload was not JSON) and `raw`. A plan refusal on open throws
`.planLimitExceeded`, exactly as for a non-streaming call. A stream is never retried:
replaying one that failed mid-flight would duplicate whatever you had already read.
Breaking out of the loop cancels the underlying task.

```swift
for try await frame in mail.streaming.generateEmail(["prompt": "a launch email"]) {
    print(frame.data?["delta"] as? String ?? "", terminator: "")
}

for try await frame in mail.streaming.campaignSend(campaignID) {
    print(frame.raw)
}
```

---

## Links

- Website — https://www.misarmail.com
- App — https://mail.misar.io
- Parent — https://misar.io
- Documentation — https://docs.misar.io/mail
- Source — https://github.com/Misar-AI/misarmail-sdks
- Swift Package — https://github.com/Misar-AI/misarmail-swift

MIT © [Misar AI](https://misar.io)

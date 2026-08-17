# MisarMail Swift SDK

Official Swift SDK for the [MisarMail](https://misarmail.com) API — transactional
send, campaigns, contacts, templates, automations, deliverability, warmup,
monetization and the two AI streams.

Full reference: [`misarmail.com/docs`](https://misarmail.com/docs).

## Install

```swift
.package(url: "https://github.com/Misar-AI/misarmail-swift.git", from: "1.0.0")
```

> SwiftPM requires `Package.swift` at the repository root, so this SDK is
> mirrored to its own repository. The monorepo URL will not resolve.

## Auth

Use a MisarMail developer key (`msk_…`), created at
[misarmail.com/developers](https://misarmail.com/developers). It is sent as
`Authorization: Bearer msk_…`.

Every call is metered against the subscription attached to that key. There is no
client-side limit checking — the server decides, and the SDK surfaces its answer.

## Quick start

```swift
import MisarMail

let mail = MisarMailClient(apiKey: "msk_your_key")

try await mail.email.send([
    "from": "you@yourdomain.com",
    "to": ["someone@example.com"],
    "subject": "Hello",
    "html": "<p>Hi there</p>",
])

let contacts = try await mail.contacts.list()
```

## Plan limits

A spent allowance answers `429` and a feature that is not on the plan answers
`402`; both carry `code: "plan_limit_exceeded"`. The SDK raises
`MisarMailError.planLimitExceeded` for either, and **does not retry** it — retrying cannot
help until the allowance resets or the plan changes. Read ``upgradeURL`` to
send the user somewhere useful.

`GET /plan` reports the plan, its allowances and per-feature usage, so an
expensive call can be checked before it is attempted rather than after it is
refused.

```swift
let plan = try await mail.plan.get()

do {
    _ = try await mail.campaigns.create(data: ["name": "Blast"])
} catch MisarMailError.planLimitExceeded(_, _, let plan, let upgradeURL, _, let feature) {
    print("\(feature ?? "?") exhausted on \(plan ?? "?"): \(upgradeURL ?? "")")
}
```

## Streaming

Two endpoints stream Server-Sent Events. Both sit **outside** `/v1`, which the
SDK handles for you:

| Method | Route |
| --- | --- |
| `streaming.generateEmail` | `POST /api/ai/generate-email/stream` |
| `streaming.campaignSend` | `GET /api/campaigns/{id}/send-stream` |

Frames are unnamed (`data: {…}`) and the stream ends with `data: [DONE]`, which
the SDK consumes rather than handing on. A stream is never retried: replaying one
that failed mid-flight would duplicate whatever you had already read.

```swift
for try await chunk in mail.streaming.generateEmail(["prompt": "a launch email"]) {
    print(chunk.data?["delta"] as? String ?? "", terminator: "")
}
```

## License

MIT — see [LICENSE](LICENSE).

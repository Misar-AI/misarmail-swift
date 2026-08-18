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

> The standalone repository carries **no version tag yet**, so a `from:`
> requirement cannot resolve until the first release publishes one. Until
> then, depend on `branch: "main"`.

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
    "from": ["email": "you@yourdomain.com"],
    "to": [["email": "someone@example.com"]],
    "subject": "Hello",
    "html": "<p>Hi there</p>",
])

let contacts = try await mail.contacts.list()
```

## Plan limits

Both a spent allowance and a feature that is not on the plan answer **`403`**,
carrying `code: "plan_limit_exceeded"`. The SDK keys on that code rather than
the status, which is why a refusal is typed correctly even though 403 is
otherwise an authorization failure. The SDK raises
`MisarMailError.planLimitExceeded` for either, and **does not retry** it — retrying cannot
help until the allowance resets or the plan changes. Read ``upgradeURL`` to
send the user somewhere useful.

`GET /plan` returns `plan`, `sending` (the per-day and per-month email caps),
`usage` — an array with one entry per metered feature, each carrying `used`,
`limit` and `remaining` — and `upgrade`, which is null until a quota is tight.
A null `limit` means unlimited, and `remaining` is null alongside it rather than
0. Read it before an expensive call rather than discovering the ceiling through
a refusal.

The key needs the `read` or `subscription` scope.

```swift
let plan = try await mail.plan.get()

do {
    _ = try await mail.campaigns.create(data: [
        "name": "Blast", "subject": "We just shipped",
        "fromName": "Your Name", "fromEmail": "you@yourdomain.com",
    ])
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

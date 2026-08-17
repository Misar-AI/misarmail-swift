# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-08-17

First release.

### Added

- Full coverage of the MisarMail REST API, authenticated with a `msk_` developer
  key sent as `Authorization: Bearer msk_…`.
- Server-Sent Events for `POST /api/ai/generate-email/stream` and
  `GET /api/campaigns/{id}/send-stream`. Unnamed frames terminated by
  `data: [DONE]`, which the SDK consumes rather than handing on.
- `GET /plan` for reading the subscription's allowances and per-feature usage,
  so an expensive call can be checked before it is attempted rather than after
  it is refused.
- Retries with exponential back-off on genuinely transient statuses
  (429 rate limits, 500, 502, 503, 504).

### Notes

- Plan limits are enforced server-side against the subscription attached to the
  API key. A spent allowance answers 429 and a feature not on the plan answers
  402; both carry `code: "plan_limit_exceeded"`. Surfaced as a distinct error
  type and never retried, since retrying cannot help until the allowance resets
  or the plan changes.
- Streams are never retried: replaying one that failed mid-flight would
  duplicate whatever the caller had already consumed.

[1.0.0]: https://misarmail.com/docs

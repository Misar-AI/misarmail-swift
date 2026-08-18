# Changelog

All notable changes to this SDK are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.0.3] — 2026-08-19

Republished so that every SDK, including the tag-versioned ones, ships through the same automated release pipeline. No API changes.

## [5.0.2] — 2026-08-19

Republished so that every SDK, including the tag-versioned ones, ships through the same automated release pipeline. No API changes.

## [5.0.1] — 2026-08-19

Republished so that every SDK, including the tag-versioned ones, ships through the same automated release pipeline. No API changes.

## [5.0.0] — 2026-08-19

One version across every SDK in every Misar product, replacing the drift between separately-numbered clients.

### Documentation

- Rewritten README: every resource and method is listed with the endpoint it calls, the examples are verified against the API contract, and package links are consistent across all SDKs.
- Manifest metadata filled in — homepage, repository, issue tracker, documentation and author.

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
  API key. Both a spent allowance and a locked feature answer 403 carrying
  `code: "plan_limit_exceeded"`. The client keys on that code rather than the
  status — 403 is otherwise an authorization failure — and surfaces a distinct
  error type that is never retried, since retrying cannot help until the
  allowance resets or the plan changes.
- Streams are never retried: replaying one that failed mid-flight would
  duplicate whatever the caller had already consumed.

[1.0.0]: https://misarmail.com/docs

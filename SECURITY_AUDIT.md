# flutter_sharing_intent — Security Audit (Relocat fork)

**Audit date started:** 2026-04-21
**Auditor:** Relocat maintainers
**Scope:** everything under this repository except `example/` and `build/`.
**Methodology:** STRIDE-lite per-entry-point + remediation-commit review + dependency & license audit.
**Status:** Draft — findings populated as the audit progresses.

Task labels C1-C4 in the revision history are the audit's own work phases:
C1 scaffold, C2 entry-point enumeration, C3 fixes, C4 dependency and licence review.

## Upstream & Fork

- **Upstream:** https://github.com/bhagat-techind/flutter_sharing_intent
- **Upstream license:** Apache-2.0
- **Fork purpose:** Relocat vendors this plugin because upstream release cadence is slow and several iOS/Android issues affect Relocat directly. Divergence rationale lives in `README.relocat.md`.
- **Earlier fork fixes** (made before this audit):
  - FSI-24 — Android: intent handling moved off main thread.
  - FSI-31 — Android/iOS/Dart: cleanup API for App Group files.
  - FSI-61 — iOS: surface decode errors instead of swallowing.
  - FSI-72 — iOS: PHAsset resolution off main thread.
  - FSI-81 — iOS: UIScene lifecycle bridging.

## Summary Table

Updated as findings are filed. Severity: Critical / High / Medium / Low / Info.

| Finding ID | Severity | Title | Status | Fix commit |
|---|---|---|---|---|
| _(populated during C3 / C4)_ | | | | |

## Entry Points

_(populated by Task C2)_

## Findings

_(populated per finding during C3; each finding's detail section lands in the same commit as its fix)_

## Dependency & License Review

_(populated by Task C4)_

## Accepted Residual Risks

_(populated during C5 sign-off)_

## Related

- Upstream: https://github.com/bhagat-techind/flutter_sharing_intent
- Fork rationale & licensing: `README.relocat.md` and `LICENSE.relocat`

## Revision History

| Date | Change | Author |
|---|---|---|
| 2026-04-21 | Initial scaffold (C1). | Relocat maintainers |

# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **What a session cost, not just what it did.** `UsageLedger` keeps three levels — session, turn,
  step — because a turn is what the user asked for and a step is one model call, and a turn is
  often several once tools are involved. Totals alone hide the reason a single question was
  expensive. Costs come from `LLMCore`'s `CostCalculator` rather than a second implementation, so
  cache reads, cache writes and reasoning are billed the way that type already gets right.
- A model with no price sheet records `nil`, not zero. Zero would quietly understate the bill; the
  totals report `hasUnpricedSteps` so a screen can say the figure is a floor.
- `TokenBreakdown` splits a usage two ways — by token count and by cost — and `TokenBreakdownView`
  draws both bars. They disagree on purpose: cached input is usually most of the tokens and almost
  none of the money, and a count-only bar points at the wrong thing to optimise.
- `CostDisplaySettings` for currency, a ×1…×10000 scale ("the same work run N times"), and a
  USD→JPY rate via `ExchangeRateService`. Sub-yen amounts keep significant digits instead of
  rounding to ¥0.
- `AgentConsole` and `AgentConsoleView`: one object holding the catalog, keys and instruments, and
  a screen laid out by the things there are rather than the tasks one might do to them. The console
  deliberately holds no sheet state — that belongs to the screen, and putting it here is what makes
  two screens fight over one flag.
- `CredentialsView` puts every provider's key on one page, since the question is nearly always
  "which of these is set" and that is a comparison.
- `PayloadInspectorView` for structured blobs a host names — a rendered UI description, a tool's
  arguments — so nobody writes another JSON viewer.
- Debug building blocks: `DebugCard`, `DebugRow`, `DebugMetric`, `DebugEmptyHint`, `CopyButton`,
  `FilterChips`, `WrappingRow`.

### Changed

- `AgentTraceLog.Kind` gained `label` and `tintName`, and the trace list now shows a coloured
  category badge and timestamp per row. Failures are the only red.

## [0.1.0] - 2026-08-17

### Added

- First release. The three screens an LLM app ends up building anyway: a model picker, an API key
  field, and a view over what a run did.
- `ModelPickerView` and `ModelDetailView`, driven by `ModelCatalog`. The picker reads descriptors
  and never names a provider, so offering one more provider is a change to the catalog and not to
  a view.
- `CredentialResolver`, `CredentialProvider`, `CredentialStoring`, and
  `UserDefaultsCredentialStore`, with `CredentialFieldView` over them. The resolver answers "what
  key" and "where from" together, so a screen cannot show one source and call with another — the
  first question when a call fails on auth. A stored key wins over the environment, and removing
  it falls back instead of leaving the provider unusable.
- `AgentTraceLog` and `AgentTraceView`. `AgentLoop` reports what it is doing through its event
  stream and what it cost through `AgentTelemetry`, and retains neither, so by the time someone
  wants to look it is gone. The log holds both, merging streamed text deltas back into one entry
  rather than one row per delta.
- Display formatting on `ModelDescriptor` — `contextWindowText`, `maxOutputText`,
  `entryPriceText` — kept here rather than on the descriptor because it is wording, not data.

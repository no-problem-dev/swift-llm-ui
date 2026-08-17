# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-08-17

### Changed

- **BREAKING** — the console is organised by provider. A key and a model list were two screens
  about the same thing, so answering "can I use this?" took two trips; now a provider opens onto
  its key with the models it unlocks directly below. `AgentConsoleID.modelRow` and
  `.credentialsRow` are gone, replaced by `AgentConsoleID.provider(_:)`.
- Reasoning effort moved onto the model it applies to. It is a property of the model — one that
  cannot reason ignores it — so it now lives in `ModelDetailView` for the model in use, and
  `AgentConsole.reasoningEffort` stores it.
- `ModelDetailView` selects. Choosing from a one-line summary meant deciding without the facts;
  the button is now on the screen that has them. Pass a console to enable it.
- Turns and steps are screens, not disclosure rows. A step has a model, a token split and a cost —
  enough to be worth opening — so `UsageTurnView` and `UsageStepView` give each one a place.

### Added

- `UsageLedger.breakdown(of:)` for a single step.

## [0.3.0] - 2026-08-17

### Removed

- **BREAKING** — `TokenBreakdown` and `TokenCategory` moved to `LLMCore` (swift-llm-client 5.2.0).
  They are pure arithmetic over a `TokenUsage` and a `Pricing`, wanted by anything that totals a
  bill — a server as much as a settings screen — and keeping them here left that behind a SwiftUI
  dependency. Import `LLMClient` to get them; the API is unchanged, and `TokenCategory.color` still
  lives here because a colour is a display decision.
- The `TokenUsage` `+` operator and `zero` this package added are gone: `LLMCore` already has
  `adding(_:)` and `zero`, and its version is the more correct one — a total carries no cache tier,
  because each step can be billed at a different lifetime.

### Changed

- Requires swift-llm-client 5.2.0.

## [0.2.0] - 2026-08-17

### Fixed

- **A session that mixed models drew the wrong cost split.** The total was right — it is summed
  per step — but the cost bar re-derived its proportions from a single price sheet, picked as the
  model with the most steps. A cheap model's tokens were then charged at an expensive model's
  rates, so the figure was wrong precisely when the mixture was the interesting part. Worse, the
  "most used" model was chosen with `Dictionary.max`, so a tie could redraw differently with no
  change in data. `TokenBreakdown(combining:)` now adds up per-model breakdowns, and
  `UsageLedger.breakdown` / `breakdown(of:)` hand the view something already priced correctly, so
  no screen picks a price sheet.

### Changed

- `UsageView.init` no longer takes a `catalog`; the ledger it is given already knows the prices.

## [0.1.1] - 2026-08-17

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

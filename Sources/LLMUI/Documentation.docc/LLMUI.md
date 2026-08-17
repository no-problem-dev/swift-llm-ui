# ``LLMUI``

The screens an LLM app ends up needing: pick a model, hold a key, read back a run.

## Overview

Three screens get rebuilt in every app that talks to a model, and each is more finicky than it
looks. A model picker has to keep working when a vendor retires a model that is still named in
someone's settings. A key field has to say *which* key is in effect, because the environment and
the device can both have one. A trace view has to hold on to the prompt and the token counts,
which nothing retains by default.

This package is those three, built on the values that
[swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) and
[swift-agent-runtime](https://github.com/no-problem-dev/swift-agent-runtime) already publish.

### Where the line is

**These views draw; they do not decide.** Judging, computing, and storing live one layer down,
in packages that build and run on Linux. Keeping SwiftUI in a package of its own is what lets
them stay that way — a server can link the model catalog and the agent loop without pulling a UI
framework behind it.

So `ModelCatalog`, `ModelPreset` and `TokenBreakdown` are not defined here. A server needs them as much as a
settings screen does, and they belong to `LLMClient`. What this package adds is wording and
layout: `ModelDescriptor.contextWindowText`, a row, a badge, a filter.

The one thing here that is not a view is ``AgentTraceLog``, and it is here for the same reason —
it is `@MainActor` and `@Observable`, which is view state. The agent loop is deliberately free of
both, so the log that watches it lives on this side of the line.

### Choosing a model

Build a `ModelCatalog` from the presets you want to offer and bind the identifier you store.
Read it back through `ModelCatalog.resolve(_:)`, which answers with the default when the stored
choice names a model the catalog no longer has.

```swift
let catalog = ModelCatalog(
    models: GeminiModel.Preset.descriptors + GPTModel.Preset.descriptors,
    defaultModelID: GeminiModel.Preset.flashLite31.globalID
)

ModelPickerView(
    catalog: catalog,
    selectedModelID: $modelID,
    providerNames: ["gemini": "Gemini", "gpt": "OpenAI"]
)
```

### Holding a key

``CredentialResolver`` answers both "what key" and "from where" so a screen cannot show one and
call with the other. A stored key wins over the environment; removing it falls back rather than
leaving the provider unusable.

### Reading back a run

Give ``AgentTraceLog/record(_:)`` to the loop as its telemetry sink and it collects the assembled
system prompt and each step's token counts alongside the run's own events.

## Topics

### The console

- ``AgentConsole``
- ``AgentConsoleView``
- ``AgentConsoleID``

### Providers and models

- ``ProviderDetailView``
- ``ProviderRow``
- ``ModelDetailView``
- ``ModelPickerView``

### Credentials

- ``CredentialsView``
- ``CredentialFieldView``
- ``CredentialResolver``
- ``CredentialProvider``
- ``CredentialStoring``
- ``UserDefaultsCredentialStore``
- ``CredentialSource``

### Reading back a run

- ``AgentTraceView``
- ``AgentTraceLog``

### What it cost

- ``UsageLedger``
- ``UsageTurn``
- ``UsageStep``
- ``UsageTotals``
- ``UsageView``
- ``UsageTurnView``
- ``UsageStepView``
- ``TokenBreakdownView``
- ``CostDisplaySettings``
- ``CostDisplayCurrency``
- ``ExchangeRateService``

### Inspecting payloads

- ``PayloadInspectorView``
- ``InspectablePayload``

### Building a debug screen

- ``DebugCard``
- ``DebugRow``
- ``DebugMetric``
- ``DebugEmptyHint``
- ``CopyButton``
- ``FilterChips``
- ``WrappingRow``

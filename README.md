English | [日本語](./README.ja.md)

# LLMUI

SwiftUI views for choosing a model, holding an API key, and reading back what a run did

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

Every app that talks to an LLM ends up building the same three screens: pick a model, paste a
key, and look at what just happened. This package is those screens.

## What is here

- **A model picker** driven by `ModelCatalog`, so it never names a provider — offering one more
  means adding its `descriptors` to the catalog, and no view changes
- **An API key field** that says whether the key in use came from the device or the environment,
  which is the first question when a call fails on auth
- **A trace view** over `AgentTraceLog`, which collects an agent run's events and its telemetry —
  the assembled system prompt and per-step token counts — so they are still there to look at

## Where the line is

**This package draws; it does not decide.** Anything that judges, computes, or stores lives one
layer down, in [swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) and
[swift-agent-runtime](https://github.com/no-problem-dev/swift-agent-runtime) — which build and
run on Linux. Keeping the views in a separate package is what lets those stay that way: a server
links the model catalog and the agent loop without ever pulling in SwiftUI.

That is also why `ModelCatalog` and `ModelPreset` are *not* here. They are values a server needs
as much as a settings screen does, so they belong to `LLMClient`. What this package adds on top
is wording and layout.

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-ui.git", .upToNextMinor(from: "0.4.0"))
]
```

## Quick start

### Offering a choice of model

Build a catalog from the presets you want to offer, then bind the identifier you store:

```swift
import LLMClient
import LLMUI
import SwiftUI

let catalog = ModelCatalog(
    models: GeminiModel.Preset.descriptors + GPTModel.Preset.descriptors,
    defaultModelID: GeminiModel.Preset.flashLite31.globalID
)

struct SettingsView: View {
    @AppStorage("modelID") private var modelID = ""

    var body: some View {
        ModelPickerView(
            catalog: catalog,
            selectedModelID: Binding(
                get: { catalog.resolve(modelID) },
                set: { modelID = $0 }
            ),
            providerNames: ["gemini": "Gemini", "gpt": "OpenAI"]
        )
    }
}
```

`catalog.resolve(_:)` is doing real work: a model the app used to offer can be retired by the
vendor while its identifier is still in the user's settings. Reading it back through the catalog
answers with the default instead of a model nothing can serve.

### Holding an API key

```swift
let resolver = CredentialResolver(store: UserDefaultsCredentialStore())

let gemini = CredentialProvider(
    id: GeminiModel.Preset.providerID,
    displayName: "Gemini",
    apiKeyEnvironmentVariable: "GEMINI_API_KEY",
    brandKey: "google"
)

CredentialFieldView(provider: gemini, resolver: resolver)
```

A key typed into the app wins over one in the environment, and removing it falls back rather than
leaving the provider unusable. `UserDefaultsCredentialStore` is meant for a developer-facing
screen — it writes a plain plist inside the app container. Conform `CredentialStoring` against
the keychain if the key is worth protecting.

### Reading back a run

Pass the log as the agent loop's telemetry sink, and it collects the prompt and the token counts:

```swift
let log = AgentTraceLog()

let loop = AgentLoop(
    client: client,
    model: model,
    tools: tools,
    systemPrompt: prompt,
    telemetry: { await log.record($0) }
)

// elsewhere
AgentTraceView(log: log, emptyMessage: "Send a message to fill this in.") { text in
    UIPasteboard.general.string = text
}
```

`onCopy` is a closure because the pasteboard type differs per platform; leaving it off hides the
copy buttons.

## Requirements

- Swift 6.2+
- iOS 17.0+ / macOS 14.0+

## License

MIT

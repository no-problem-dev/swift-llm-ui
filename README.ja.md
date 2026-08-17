[English](./README.md) | 日本語

# LLMUI

モデルを選ぶ・API キーを持つ・実行の中身を見る、そのための SwiftUI 画面

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

LLM を扱うアプリは、結局どれも同じ 3 つの画面を作ることになる。モデルを選び、キーを貼り、
いま何が起きたのかを見る画面。このパッケージはその 3 つ。

## 入っているもの

- **モデル選択** — `ModelCatalog` を描くだけなので、提供元の名前を知らない。
  提供元を増やすのはカタログに `descriptors` を足す作業で、画面は変わらない
- **API キーの入力欄** — 効いているキーが端末のものか環境変数のものかを出す。
  認証で落ちたときに最初に知りたいのがこれ
- **ログ表示** — `AgentTraceLog` の中身を出す。実行のイベントに加えて、
  組み立て後のシステムプロンプトとステップごとのトークン数も残る

## どこで線を引いているか

**このパッケージは描くだけで、判断しない。** 判断・計算・保管は 1 つ下の
[swift-llm-client](https://github.com/no-problem-dev/swift-llm-client) と
[swift-agent-runtime](https://github.com/no-problem-dev/swift-agent-runtime) に置く。
あちらは Linux でビルドも実行もできる。画面を別パッケージに切り出しているのは、
その状態を保つため — サーバーはモデルカタログとエージェントループだけをリンクでき、
SwiftUI を引き込まずに済む。

同じ理由で `ModelCatalog` と `ModelPreset` は**ここには無い**。設定画面と同じくらい
サーバーも必要とする値なので、`LLMClient` のもの。ここが足すのは言葉と配置だけ。

## 導入

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-llm-ui.git", .upToNextMinor(from: "0.2.0"))
]
```

## 使い方

### モデルを選ばせる

出したい preset からカタログを組み、保存している ID を束ねる。

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

`catalog.resolve(_:)` は実際に効く。提供元がモデルの提供をやめても ID は設定に残るので、
カタログを通して読み戻すことで「もう呼べないモデル」ではなく既定が返る。

### API キーを持つ

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

アプリに入れたキーが環境変数より優先される。消したときは何も無い状態ではなく環境変数へ戻る。
`UserDefaultsCredentialStore` は開発者向けの画面を想定していて、書き先はアプリ内の
ただの plist。守る価値のあるキーなら `CredentialStoring` を Keychain に対して適合させる。

### 実行の中身を見る

エージェントループの telemetry の受け口として渡すと、プロンプトとトークン数が溜まる。

```swift
let log = AgentTraceLog()

let loop = AgentLoop(
    client: client,
    model: model,
    tools: tools,
    systemPrompt: prompt,
    telemetry: { await log.record($0) }
)

// 別のところで
AgentTraceView(log: log, emptyMessage: "話しかけるとここに出ます。") { text in
    UIPasteboard.general.string = text
}
```

`onCopy` がクロージャなのは、貼り付け先の型が OS ごとに違うため。渡さなければコピーの
ボタンは出ない。

## 要件

- Swift 6.2+
- iOS 17.0+ / macOS 14.0+

## ライセンス

MIT

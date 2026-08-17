# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

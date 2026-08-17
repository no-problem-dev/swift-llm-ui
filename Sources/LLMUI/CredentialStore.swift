import Foundation

// MARK: - CredentialSource

/// Where the key in use came from, so a settings screen can say which one is winning.
public enum CredentialSource: Sendable, Hashable {
    /// Typed into the app and kept on the device.
    case stored
    /// Read from the process environment.
    case environment
    /// Neither is set. Calls to that provider will fail.
    case missing
}

// MARK: - CredentialStoring

/// Where a typed-in API key is kept.
///
/// Providers are addressed by ``ModelPreset/providerID``, a plain `String`, so adding a provider
/// never reaches this protocol. The default implementation writes to `UserDefaults`; conform your
/// own to put keys in the keychain instead.
public protocol CredentialStoring: Sendable {
    func key(forProviderID providerID: String) -> String?
    func setKey(_ key: String?, forProviderID providerID: String)
}

// MARK: - UserDefaultsCredentialStore

/// Keeps keys in `UserDefaults`.
///
/// Enough for a developer-facing settings screen, which is what this package is for. It is *not*
/// somewhere to put a key you would mind leaking — `UserDefaults` is a plain plist inside the app
/// container. Conform ``CredentialStoring`` against the keychain if the key is worth protecting.
public struct UserDefaultsCredentialStore: CredentialStoring {
    private let defaults: UncheckedSendable<UserDefaults>
    private let keyPrefix: String

    /// - Parameters:
    ///   - defaults: Where to write. Pass a suite to keep test keys out of the app's own domain.
    ///   - keyPrefix: Prepended to `providerID` to form the defaults key. Changing it orphans
    ///     keys already written under the old prefix.
    public init(defaults: UserDefaults = .standard, keyPrefix: String = "LLMUI.apiKey.") {
        self.defaults = UncheckedSendable(defaults)
        self.keyPrefix = keyPrefix
    }

    public func key(forProviderID providerID: String) -> String? {
        let value = defaults.value.string(forKey: keyPrefix + providerID)
        return value?.isEmpty == false ? value : nil
    }

    /// Writes the key, or removes it when `key` is `nil` or blank.
    ///
    /// Whitespace is trimmed first, so a pasted key with a trailing newline does not become a
    /// value that is present but unusable.
    public func setKey(_ key: String?, forProviderID providerID: String) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.value.set(trimmed, forKey: keyPrefix + providerID)
        } else {
            defaults.value.removeObject(forKey: keyPrefix + providerID)
        }
    }
}

/// `UserDefaults` is thread-safe but not `Sendable`; this states that on its behalf.
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

// MARK: - CredentialResolver

/// Answers "what key should this provider be called with, and where did it come from".
///
/// A stored key wins over the environment, so typing one into the app overrides whatever the
/// process was launched with. Reading the environment as a fallback is what lets a key be passed
/// in at launch without being typed at all.
public struct CredentialResolver: Sendable {
    private let store: any CredentialStoring
    private let environment: @Sendable () -> [String: String]

    /// - Parameters:
    ///   - store: Where typed-in keys are kept.
    ///   - environment: The environment to fall back to. Injectable so tests do not depend on the
    ///     variables the test runner happens to have.
    public init(
        store: any CredentialStoring,
        environment: @escaping @Sendable () -> [String: String] = {
            ProcessInfo.processInfo.environment
        }
    ) {
        self.store = store
        self.environment = environment
    }

    /// The key to call `provider` with, or `nil` when neither source has one.
    public func key(for provider: CredentialProvider) -> String? {
        store.key(forProviderID: provider.id) ?? environmentKey(for: provider)
    }

    /// Which source ``key(for:)`` would answer from.
    public func source(for provider: CredentialProvider) -> CredentialSource {
        if store.key(forProviderID: provider.id) != nil {
            return .stored
        }
        return environmentKey(for: provider) != nil ? .environment : .missing
    }

    /// Stores a key, or removes the stored one when `key` is `nil`.
    ///
    /// Removing falls back to the environment rather than to nothing, so a screen that clears the
    /// stored key shows `.environment` again when the process has one.
    public func setKey(_ key: String?, for provider: CredentialProvider) {
        store.setKey(key, forProviderID: provider.id)
    }

    private func environmentKey(for provider: CredentialProvider) -> String? {
        guard let name = provider.apiKeyEnvironmentVariable else {
            return nil
        }
        let raw = environment()[name]
        return raw?.isEmpty == false ? raw : nil
    }
}

// MARK: - CredentialProvider

/// A provider as a credentials screen sees it: a name to show and somewhere to read a key from.
public struct CredentialProvider: Sendable, Identifiable, Hashable {
    /// Matches ``ModelPreset/providerID``, so the key found here is the key that provider's models
    /// are called with.
    public let id: String

    public let displayName: String

    /// The environment variable to fall back to. `nil` means this provider is stored-key only.
    public let apiKeyEnvironmentVariable: String?

    /// Names the logo to show. Resolved against `CloudProviderBrand`; `nil` draws no logo.
    public let brandKey: String?

    public init(
        id: String,
        displayName: String,
        apiKeyEnvironmentVariable: String? = nil,
        brandKey: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.apiKeyEnvironmentVariable = apiKeyEnvironmentVariable
        self.brandKey = brandKey
    }
}

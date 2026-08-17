import Foundation
import Testing

@testable import LLMUI

/// Which key wins, and what the screen is told about where it came from.
///
/// The badge in `CredentialFieldView` is only useful if the source it reports is the source the
/// call actually uses, so the two are answered by one type and checked together here.
@Suite("Credential resolution")
struct CredentialResolverTests {

    private let provider = CredentialProvider(
        id: "gemini",
        displayName: "Gemini",
        apiKeyEnvironmentVariable: "GEMINI_API_KEY",
        brandKey: "google"
    )

    private func makeStore(_ name: String) -> UserDefaultsCredentialStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return UserDefaultsCredentialStore(defaults: defaults, keyPrefix: "test.")
    }

    @Test("A stored key wins over the environment")
    func storedKeyWinsOverEnvironment() {
        let resolver = CredentialResolver(
            store: makeStore(#function),
            environment: { ["GEMINI_API_KEY": "from-environment"] }
        )

        #expect(resolver.key(for: provider) == "from-environment")
        #expect(resolver.source(for: provider) == .environment)

        resolver.setKey("from-device", for: provider)

        #expect(resolver.key(for: provider) == "from-device")
        #expect(resolver.source(for: provider) == .stored)
    }

    /// Clearing the stored key has to fall back rather than leave the provider unusable when the
    /// process was launched with one.
    @Test("Removing the stored key falls back to the environment")
    func removingStoredKeyFallsBack() {
        let resolver = CredentialResolver(
            store: makeStore(#function),
            environment: { ["GEMINI_API_KEY": "from-environment"] }
        )

        resolver.setKey("from-device", for: provider)
        resolver.setKey(nil, for: provider)

        #expect(resolver.key(for: provider) == "from-environment")
        #expect(resolver.source(for: provider) == .environment)
    }

    @Test("With neither source set, the key is missing")
    func missingWhenNothingIsSet() {
        let resolver = CredentialResolver(store: makeStore(#function), environment: { [:] })

        #expect(resolver.key(for: provider) == nil)
        #expect(resolver.source(for: provider) == .missing)
    }

    /// A key pasted with a trailing newline used to be stored as-is and then sent, which fails
    /// authentication in a way that looks like a wrong key rather than a stray character.
    @Test("A key is trimmed before it is stored")
    func keyIsTrimmed() {
        let resolver = CredentialResolver(store: makeStore(#function), environment: { [:] })

        resolver.setKey("  sk-test\n", for: provider)

        #expect(resolver.key(for: provider) == "sk-test")
    }

    /// Blank is the same as absent — otherwise the badge says a key is present and the call fails.
    @Test("A blank key is treated as no key")
    func blankKeyIsTreatedAsAbsent() {
        let resolver = CredentialResolver(store: makeStore(#function), environment: { [:] })

        resolver.setKey("   ", for: provider)

        #expect(resolver.key(for: provider) == nil)
        #expect(resolver.source(for: provider) == .missing)
    }

    @Test("A blank environment variable is ignored")
    func blankEnvironmentValueIsIgnored() {
        let resolver = CredentialResolver(
            store: makeStore(#function),
            environment: { ["GEMINI_API_KEY": ""] }
        )

        #expect(resolver.source(for: provider) == .missing)
    }

    /// A provider with no environment variable reads only from the store, and must not pick up
    /// some unrelated variable.
    @Test("A provider with no environment variable is stored-key only")
    func providerWithoutEnvironmentVariable() {
        let local = CredentialProvider(id: "local", displayName: "On device")
        let resolver = CredentialResolver(
            store: makeStore(#function),
            environment: { ["GEMINI_API_KEY": "from-environment"] }
        )

        #expect(resolver.source(for: local) == .missing)

        resolver.setKey("from-device", for: local)

        #expect(resolver.key(for: local) == "from-device")
    }

    /// Keys are addressed by provider id; one provider's key must not answer for another's.
    @Test("Keys are kept per provider")
    func keysAreKeptPerProvider() {
        let resolver = CredentialResolver(store: makeStore(#function), environment: { [:] })
        let other = CredentialProvider(id: "gpt", displayName: "OpenAI")

        resolver.setKey("gemini-key", for: provider)

        #expect(resolver.key(for: provider) == "gemini-key")
        #expect(resolver.key(for: other) == nil)
    }
}

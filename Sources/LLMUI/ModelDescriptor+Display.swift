import Foundation
import LLMClient

// MARK: - Display strings

/// Formatting for the facts a picker shows at a glance.
///
/// These live here rather than on the descriptor because they are wording, not data: a row has
/// room for a few characters and picks the shortest true form. Anything reading the numbers for
/// its own purpose should read `profile` instead.
public extension ModelDescriptor {
    /// The context window, abbreviated (`"1M context"`). `nil` when the model does not state one.
    var contextWindowText: String? {
        guard let window = profile.contextWindow else {
            return nil
        }
        return "\(Self.abbreviated(window)) context"
    }

    /// The maximum output length, abbreviated. `nil` when the model does not state one.
    var maxOutputText: String? {
        guard let output = profile.maxOutputTokens else {
            return nil
        }
        return "\(Self.abbreviated(output)) out"
    }

    /// The first pricing tier, per million tokens (`"$1.50 / $7.50 per 1M"`).
    ///
    /// Only the first tier: a row cannot hold a table, and the first is what a short prompt is
    /// billed at. `ModelDescriptor.profile` has the rest for a screen with room for it.
    var entryPriceText: String? {
        guard let tier = profile.pricing?.tiers.first else {
            return nil
        }
        return String(
            format: "$%.2f / $%.2f per 1M",
            tier.inputPerMTok,
            tier.outputPerMTok
        )
    }

    /// Rounds down to `K` or `M`. Counts are approximate here by intent — the exact number is
    /// noise in a row that is trying to say "big" or "small".
    private static func abbreviated(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M"
        }
        if tokens >= 1000 {
            return "\(tokens / 1000)K"
        }
        return "\(tokens)"
    }
}

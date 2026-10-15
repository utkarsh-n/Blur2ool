import Foundation
import Observation
import BlurCore

// OWNER: ENGINE (frozen public API, ARCHITECTURE §5.9 / AppContract/Engine/EngineAPI.swift). Settings › (SPEC §4.7),
// persisted in UserDefaults by `load`/`save`; UI-FIELDGUIDE builds the form. Every field decodes independently
// (`decodeIfPresent`), so a setting added in a later build never wipes the ones already saved, and a corrupt blob is
// ignored rather than crashing. Settings › Preview is `silentDefaults.preview` (SPEC §9.3: "Always full" forces full
// resolution while moving); the other silent defaults seed every new blur's EVERY BLUR group.

public enum DisplayMode: String, Sendable, Codable, CaseIterable { case sdr, edr }
public enum BadgeStyle: String, Sendable, Codable, CaseIterable { case words, compactGlyphsOnChips }

/// Settings › (SPEC §4.7). Persisted in UserDefaults by `load`/`save`. Owner: ENGINE (UI-FIELDGUIDE builds the form).
@MainActor @Observable
public final class AppSettings {
    /// Settings › Home tool (SLIDE chip, floor 1): a ToolConventionProviding id; SwiftUI points by default (SPEC §4.1.4).
    public var homeToolID: String = "swiftui"
    /// σ-hold on switch (SPEC §8.1); also in Compare's B menu.
    public var matchSigmaOnSwitch: Bool = true
    public var hapticsEnabled: Bool = true
    public var displayMode: DisplayMode = .sdr
    public var badgeStyle: BadgeStyle = .compactGlyphsOnChips
    /// The EVERY BLUR defaults (colour space, edges, alpha, precision, preview).
    public var silentDefaults: SilentSettings = .standard
    /// The first-launch coaching line (SPEC §2). Disarmed after the first accepted interaction; Settings can re-arm it.
    public var coachingLineArmed: Bool = true
    public init() {}

    /// The UserDefaults key (one JSON blob, versioned).
    public static let defaultsKey = "B2Settings.v1"

    private struct Stored: Codable {
        var homeToolID: String?
        var matchSigmaOnSwitch: Bool?
        var hapticsEnabled: Bool?
        var displayMode: DisplayMode?
        var badgeStyle: BadgeStyle?
        var silentDefaults: SilentSettings?
        var coachingLineArmed: Bool?
    }

    public func load(from defaults: UserDefaults = .standard) {
        guard let data = defaults.data(forKey: Self.defaultsKey), let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        if let v = s.homeToolID, !v.isEmpty { homeToolID = v }
        if let v = s.matchSigmaOnSwitch { matchSigmaOnSwitch = v }
        if let v = s.hapticsEnabled { hapticsEnabled = v }
        if let v = s.displayMode { displayMode = v }
        if let v = s.badgeStyle { badgeStyle = v }
        if let v = s.silentDefaults { silentDefaults = v }
        if let v = s.coachingLineArmed { coachingLineArmed = v }
    }

    public func save(to defaults: UserDefaults = .standard) {
        let s = Stored(homeToolID: homeToolID, matchSigmaOnSwitch: matchSigmaOnSwitch, hapticsEnabled: hapticsEnabled,
                       displayMode: displayMode, badgeStyle: badgeStyle, silentDefaults: silentDefaults, coachingLineArmed: coachingLineArmed)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    /// Settings › Reset: every value back to its default (persisted by the caller's `save`).
    public func resetToDefaults() {
        homeToolID = "swiftui"; matchSigmaOnSwitch = true; hapticsEnabled = true; displayMode = .sdr
        badgeStyle = .compactGlyphsOnChips; silentDefaults = .standard; coachingLineArmed = true
    }

    /// Settings › Preview (SPEC §4.1.6): false forces full resolution while a control moves.
    public var previewsWhileMoving: Bool {
        get { silentDefaults.preview == .halfWhileMoving }
        set { silentDefaults.preview = newValue ? .halfWhileMoving : .alwaysFull }
    }
}

//
//  PadSettings.swift
//  TrackpadRemote (iOS)
//
//  Tunables the pad's feel depends on. They were constants compiled into
//  TrackpadUIView, which meant every "a bit too fast" needed a rebuild — and
//  the right value is a matter of hand size and taste, not something that can
//  be picked correctly once for everyone.
//

import Foundation
import SwiftUI

/// The subset of the pad's constants the user can move, resolved to the units
/// TrackpadUIView actually works in. Plain value type so the UIKit side never
/// has to know about Combine or UserDefaults.
struct PadTuning {
    var minGain: CGFloat = 0.55
    var maxGain: CGFloat = 2.6
    var scrollMultiplier: CGFloat = 2.0
    var naturalScrolling: Bool = true
    var pinchEnabled: Bool = true
    var pinchStepDistance: CGFloat = 55
    var swipeEnabled: Bool = true
    var swipeThreshold: CGFloat = 55
}

@MainActor
final class PadSettings: ObservableObject {

    /// Baselines the sliders scale. These are the values that shipped as
    /// constants, so leaving every control centred reproduces the old feel.
    enum Baseline {
        static let minGain: CGFloat = 0.55
        static let maxGain: CGFloat = 2.6
        static let pinchStepDistance: CGFloat = 55
        static let swipeThreshold: CGFloat = 55
    }

    enum Defaults {
        static let pointerSpeed = 1.0
        static let accelerationEnabled = true
        static let scrollSpeed = 2.0
        static let naturalScrolling = true
        static let pinchEnabled = true
        static let pinchSensitivity = 1.0
        static let swipeEnabled = true
        static let swipeSensitivity = 1.0
    }

    static let pointerSpeedRange = 0.4...2.5
    static let scrollSpeedRange = 0.5...5.0
    static let sensitivityRange = 0.5...2.0

    @Published var pointerSpeed: Double { didSet { persist(pointerSpeed, Key.pointerSpeed) } }
    @Published var accelerationEnabled: Bool { didSet { persist(accelerationEnabled, Key.accelerationEnabled) } }
    @Published var scrollSpeed: Double { didSet { persist(scrollSpeed, Key.scrollSpeed) } }
    @Published var naturalScrolling: Bool { didSet { persist(naturalScrolling, Key.naturalScrolling) } }
    @Published var pinchEnabled: Bool { didSet { persist(pinchEnabled, Key.pinchEnabled) } }
    @Published var pinchSensitivity: Double { didSet { persist(pinchSensitivity, Key.pinchSensitivity) } }
    @Published var swipeEnabled: Bool { didSet { persist(swipeEnabled, Key.swipeEnabled) } }
    @Published var swipeSensitivity: Double { didSet { persist(swipeSensitivity, Key.swipeSensitivity) } }

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
        // `didSet` doesn't run during init, so nothing is written back here.
        pointerSpeed = store.value(Key.pointerSpeed) ?? Defaults.pointerSpeed
        accelerationEnabled = store.value(Key.accelerationEnabled) ?? Defaults.accelerationEnabled
        scrollSpeed = store.value(Key.scrollSpeed) ?? Defaults.scrollSpeed
        naturalScrolling = store.value(Key.naturalScrolling) ?? Defaults.naturalScrolling
        pinchEnabled = store.value(Key.pinchEnabled) ?? Defaults.pinchEnabled
        pinchSensitivity = store.value(Key.pinchSensitivity) ?? Defaults.pinchSensitivity
        swipeEnabled = store.value(Key.swipeEnabled) ?? Defaults.swipeEnabled
        swipeSensitivity = store.value(Key.swipeSensitivity) ?? Defaults.swipeSensitivity
    }

    var isDefault: Bool {
        pointerSpeed == Defaults.pointerSpeed
            && accelerationEnabled == Defaults.accelerationEnabled
            && scrollSpeed == Defaults.scrollSpeed
            && naturalScrolling == Defaults.naturalScrolling
            && pinchEnabled == Defaults.pinchEnabled
            && pinchSensitivity == Defaults.pinchSensitivity
            && swipeEnabled == Defaults.swipeEnabled
            && swipeSensitivity == Defaults.swipeSensitivity
    }

    func resetToDefaults() {
        pointerSpeed = Defaults.pointerSpeed
        accelerationEnabled = Defaults.accelerationEnabled
        scrollSpeed = Defaults.scrollSpeed
        naturalScrolling = Defaults.naturalScrolling
        pinchEnabled = Defaults.pinchEnabled
        pinchSensitivity = Defaults.pinchSensitivity
        swipeEnabled = Defaults.swipeEnabled
        swipeSensitivity = Defaults.swipeSensitivity
    }

    var tuning: PadTuning {
        PadTuning(
            // With acceleration off the gain is flat, so both ends collapse onto
            // the same value and a slow finger moves as far as a fast one.
            minGain: Baseline.minGain * pointerSpeed,
            maxGain: (accelerationEnabled ? Baseline.maxGain : Baseline.minGain) * pointerSpeed,
            scrollMultiplier: scrollSpeed,
            naturalScrolling: naturalScrolling,
            pinchEnabled: pinchEnabled,
            // Higher sensitivity means a shorter pinch per zoom step.
            pinchStepDistance: Baseline.pinchStepDistance / pinchSensitivity,
            swipeEnabled: swipeEnabled,
            swipeThreshold: Baseline.swipeThreshold / swipeSensitivity
        )
    }

    private func persist(_ value: Any, _ key: String) {
        store.set(value, forKey: key)
    }

    private enum Key {
        static let pointerSpeed = "pad.pointerSpeed"
        static let accelerationEnabled = "pad.accelerationEnabled"
        static let scrollSpeed = "pad.scrollSpeed"
        static let naturalScrolling = "pad.naturalScrolling"
        static let pinchEnabled = "pad.pinchEnabled"
        static let pinchSensitivity = "pad.pinchSensitivity"
        static let swipeEnabled = "pad.swipeEnabled"
        static let swipeSensitivity = "pad.swipeSensitivity"
    }
}

private extension UserDefaults {
    /// `object(forKey:)` rather than the typed accessors: those return 0/false
    /// for a missing key, which would silently override the default.
    func value<T>(_ key: String) -> T? { object(forKey: key) as? T }
}

import UIKit

/// Small, consistent haptic vocabulary. Restraint matters — a journal that
/// buzzes constantly stops feeling calm.
///
/// Generators are held and pre-warmed rather than created per call: a cold
/// `UIFeedbackGenerator` can take a beat to spin up the Taptic Engine, which
/// is exactly the lag that makes a tap feel cheap.
///
/// Not actor-isolated: every call site is a SwiftUI event handler or a
/// `@MainActor` task, so these already run on the main thread.
///
/// Haptics are always on. They're part of how the app feels rather than a
/// preference, so there is no switch for them.
enum Haptics {
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notice = UINotificationFeedbackGenerator()
    private static let picker = UISelectionFeedbackGenerator()

    /// Call before a run of haptics (entering the quiz, starting a hold).
    static func prepare() {
        soft.prepare()
        light.prepare()
        picker.prepare()
    }

    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        generator(for: style).impactOccurred()
    }

    /// Lighter than `tap`, for values changing under a finger.
    static func selection() {
        picker.selectionChanged()
    }

    static func success() {
        notice.notificationOccurred(.success)
    }

    static func warning() {
        notice.notificationOccurred(.warning)
    }

    private static func generator(
        for style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: light
        case .medium: medium
        case .rigid: rigid
        default: soft
        }
    }
}

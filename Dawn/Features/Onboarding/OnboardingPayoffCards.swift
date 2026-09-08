import SwiftUI

// MARK: - Analysing

/// The pause between answering and being told what it means.
///
/// The plan itself is computed synchronously and instantly, so the pacing here
/// is staged, not measured. Two rules keep it from being a straight lie:
/// every label names something the plan really does with their answers, and
/// every label quotes the answer it's working on back at them. The uneven
/// durations are the theatre — a bar that crawls on one step and snaps on the
/// next reads as work; a metronome reads as a countdown.
struct AnalysingCard: View {
    let answers: QuizAnswers
    var onDone: () -> Void

    @State private var completed = 0
    /// 0...1 fill of the step currently running. Drives the hairline under the
    /// active label, which is where the variable speed is actually legible.
    @State private var activeFill: Double = 0
    @State private var pulsing = false

    private struct Stage {
        let label: String
        /// Seconds. Deliberately irregular — see the type comment.
        let duration: Double
    }

    /// Built from the answers so the text is specific to this person. The
    /// durations are hand-set: quick acknowledgement, a long think on the two
    /// steps that carry the most personalisation, a short flourish to close.
    private var stages: [Stage] {
        let thieves = answers.selected(.thieves).compactMap { id in
            QuizQuestion.thieves.options.first { $0.id == id }?.label.lowercased()
        }
        let gate = thieves.first.map { thieves.count > 1 ? "\($0) and \(thieves.count - 1) more" : $0 }

        return [
            Stage(label: "Reading your answers", duration: 0.45),
            // Not "sizing the page to N minutes" any more. The page is the
            // same five questions for everyone, and a progress line claiming
            // work the app isn't doing is the kind of thing users notice the
            // second time they see this screen.
            Stage(label: "Setting up your two sittings", duration: 1.30),
            Stage(label: gate.map { "Setting the gate on \($0)" } ?? "Setting the gate on your phone",
                  duration: 0.70),
            Stage(label: "Timing the alarm for \(answers.wakeTimeLabel)", duration: 1.55),
            Stage(label: "Writing your plan", duration: 0.80),
        ]
    }

    var body: some View {
        let stages = stages

        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Building your plan")
                    .font(Theme.Typography.serif(32))
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(stages.enumerated()), id: \.offset) { offset, stage in
                    row(stage, at: offset)
                }
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .pageGutter()
        .task { await run(stages) }
    }

    @ViewBuilder
    private func row(_ stage: Stage, at offset: Int) -> some View {
        let isDone = offset < completed
        let isActive = offset == completed

        HStack(spacing: Theme.Space.sm) {
            ZStack {
                Circle()
                    .stroke(Theme.Palette.rule, lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Palette.emberDeep)
                        .transition(.opacity)
                } else if isActive {
                    Circle()
                        .fill(Theme.Palette.ember.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulsing ? 1.25 : 0.85)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(stage.label)
                    .font(Theme.Typography.sans(16))
                    .foregroundStyle(offset <= completed ? Theme.Palette.ink : Theme.Palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                // Only the running step gets a bar. Completed steps have their
                // checkmark and upcoming ones haven't earned one yet, so the
                // eye has exactly one thing to watch move.
                if isActive {
                    Capsule()
                        .fill(Theme.Palette.rule)
                        .frame(height: 2)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Theme.Palette.ember)
                                    .frame(width: geo.size.width * activeFill)
                            }
                        }
                        .frame(maxWidth: 180)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 0)
        }
        .animation(Theme.Motion.settle, value: completed)
        .accessibilityElement(children: .combine)
    }

    private func run(_ stages: [Stage]) async {
        if let breathe = Theme.Motion.breathe {
            withAnimation(breathe.repeatForever(autoreverses: true)) { pulsing = true }
        }

        for stage in stages {
            // A little jitter so a second run through onboarding doesn't play
            // back identically — real work isn't reproducible to the frame.
            let duration = stage.duration * Double.random(in: 0.9...1.12)

            activeFill = 0
            withAnimation(.linear(duration: duration)) { activeFill = 1 }

            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return // Cancelled — the card is gone; don't advance behind it.
            }

            withAnimation(Theme.Motion.settle) { completed += 1 }
            Haptics.tap(.light)
        }

        // Let the last checkmark actually land before the screen changes. The
        // old timing advanced into the transition and ate its own ending.
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        Haptics.success()
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        onDone()
    }
}

// MARK: - Plan

struct PlanCard: View {
    let plan: MorningPlan
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(plan.headline)
                        .font(Theme.Typography.serif(32))
                        .foregroundStyle(Theme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.diagnosis)
                        .font(Theme.Typography.sans(15))
                        .foregroundStyle(Theme.Palette.inkSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: Theme.Space.sm) {
                    ForEach(Array(plan.rows.enumerated()), id: \.element.id) { offset, row in
                        GlassCard(padding: Theme.Space.md) {
                            HStack(alignment: .top, spacing: Theme.Space.sm) {
                                Image(systemName: row.symbol)
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundStyle(Theme.Palette.ember)
                                    .frame(width: 26)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.title)
                                        .font(Theme.Typography.serif(18))
                                        .foregroundStyle(Theme.Palette.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(row.detail)
                                        .font(Theme.Typography.sans(13))
                                        .foregroundStyle(Theme.Palette.inkTertiary)
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 18 * Theme.Motion.rise)
                        .animation(Theme.Motion.settle.delay(Double(offset) * 0.08), value: revealed)
                        .accessibilityElement(children: .combine)
                    }
                }

                Color.clear.frame(height: Theme.Space.md)
            }
            .pageGutter()
        }
        .scrollIndicators(.hidden)
        .onAppear { revealed = true }
    }
}

// MARK: - Commitment

/// A fingerprint you hold, not a button you tap.
///
/// The gesture is borrowed from Touch ID on purpose: people already know what
/// holding a fingerprint means, so the commitment reads as something you
/// *authorise* rather than something you click past. The print fills as you
/// hold, a scan line tracks the fill, and the ring closes around it.
struct CommitCard: View {
    let name: String
    var onCommit: () -> Void

    @State private var progress: Double = 0
    @State private var isPressing = false
    @State private var done = false
    @State private var pulse = false
    @State private var timer: Timer?
    @State private var lastHapticStep = 0

    private let holdDuration = 1.8
    private let printSize: CGFloat = 96

    private var printWidth: CGFloat { printSize * 0.86 }
    private var printHeight: CGFloat { printSize * 0.86 }

    private func printMark(tinted style: some ShapeStyle) -> some View {
        Image("FingerprintMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: printWidth, height: printHeight)
            .foregroundStyle(style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(name.trimmed.isEmpty
                     ? "Commit to your mornings."
                     : "\(name.trimmed), commit to your mornings.")
                    .font(Theme.Typography.serif(32))
                    .foregroundStyle(Theme.Palette.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tomorrow, the page comes before the phone.")
                    .font(Theme.Typography.sans(15))
                    .foregroundStyle(Theme.Palette.inkSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            VStack(spacing: Theme.Space.md) {
                fingerprint
                Text(caption)
                    .font(Theme.Typography.sans(14, weight: done ? .semibold : .regular))
                    .foregroundStyle(done ? Theme.Palette.emberDeep : Theme.Palette.inkTertiary)
                    .contentTransition(.opacity)
                    .animation(Theme.Motion.quick, value: caption)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .pageGutter()
        .padding(.bottom, Theme.Space.xxl)
    }

    private var caption: String {
        if done { return "Committed" }
        return isPressing ? "Keep holding…" : "Hold to commit"
    }

    // MARK: - The print

    private var fingerprint: some View {
        ZStack {
            // The arc that closes as the hold completes. It used to run over a
            // static track ring, which at rest was just a hoop drawn around the
            // print — so the arc now sweeps in from nothing.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Theme.Palette.ember, Theme.Palette.gold],
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: printSize + 44, height: printSize + 44)
                .rotationEffect(.degrees(-90))

            // Soft glass plate under the print.
            Circle()
                .fill(.clear)
                .frame(width: printSize + 24, height: printSize + 24)
                .glassEffect(
                    .regular.tint(Theme.Palette.emberSoft.opacity(isPressing ? 0.28 : 0.14)),
                    in: .circle
                )

            // The unfilled print. Material Symbols' `fingerprint` at weight
            // 100 — the hairline cut is the only one light enough to sit
            // beside the rest of the screen. Not SF Symbols' `touchid`, which
            // is licensed only for referring to Touch ID itself.
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: printSize * 0.5, weight: .ultraLight))
                    .foregroundStyle(Theme.Palette.emberDeep)
            } else {
                printMark(tinted: Theme.Palette.inkTertiary)

                printMark(
                    tinted: LinearGradient(
                        colors: [Theme.Palette.ember, Theme.Palette.gold],
                        startPoint: .bottom, endPoint: .top
                    )
                )
                .mask(alignment: .bottom) {
                    Rectangle()
                        .frame(height: printHeight * progress)
                }

                // Scan line riding the top edge of the fill.
                if progress > 0.02 && progress < 0.99 {
                    Capsule()
                        .fill(Theme.Palette.gold)
                        .frame(width: printWidth, height: 1.5)
                        .shadow(color: Theme.Palette.gold.opacity(0.8), radius: 5)
                        .offset(y: (printHeight / 2) - (printHeight * progress))
                }
            }
        }
        .frame(width: printSize + 44, height: printSize + 44)
        .scaleEffect(done ? 1 + 0.04 * Theme.Motion.rise
                          : (isPressing ? 1 - 0.03 * Theme.Motion.rise : 1))
        .animation(Theme.Motion.settle, value: done)
        .animation(Theme.Motion.quick, value: isPressing)
        .overlay {
            // One outward pulse on success — and only then. This ring used to
            // be rendered always, at half opacity, fading to nothing as it
            // expanded: which meant the "pulse" was really a hoop drawn around
            // the print at all times, and the burst was it leaving.
            if done {
                Circle()
                    .stroke(Theme.Palette.ember.opacity(pulse ? 0 : 0.5), lineWidth: 2)
                    .scaleEffect(pulse ? 1.5 : 1)
                    .frame(width: printSize + 44, height: printSize + 44)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in endHold() }
        )
        .accessibilityElement()
        .accessibilityLabel("Commit to your mornings")
        .accessibilityHint("Double tap and hold to commit")
        .accessibilityAddTraits(.isButton)
        // VoiceOver can't express a press-and-hold, so give it a plain action.
        .accessibilityAction { complete() }
    }

    // MARK: - Hold

    private func beginHold() {
        guard !isPressing, !done else { return }
        isPressing = true
        lastHapticStep = 0
        Haptics.tap(.soft)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { current in
            Task { @MainActor in
                progress = min(1, progress + 0.02 / holdDuration)

                // A tick every 20% reads like a scanner reading ridges.
                let step = Int(progress * 5)
                if step > lastHapticStep {
                    lastHapticStep = step
                    Haptics.tap(.light)
                }

                if progress >= 1 {
                    current.invalidate()
                    complete()
                }
            }
        }
    }

    private func endHold() {
        guard !done else { return }
        isPressing = false
        timer?.invalidate()
        // Rewind rather than snap — a hard reset to zero feels punitive.
        withAnimation(.easeOut(duration: 0.4)) { progress = 0 }
        lastHapticStep = 0
    }

    private func complete() {
        guard !done else { return }
        timer?.invalidate()
        progress = 1
        done = true
        isPressing = false
        Haptics.success()
        // A frame later, so the ring above is on screen unexpanded before it
        // starts expanding. Set in the same pass, SwiftUI has no "from" state
        // to animate out of and the pulse never shows.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.7)) { pulse = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onCommit() }
    }
}

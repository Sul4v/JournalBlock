import SwiftUI

/// The hard paywall. There is no free tier and no dismiss — by design, and at
/// some App Review risk (see README → "The hard paywall decision").
///
/// The structure follows the flow that precedes it: the headline repeats the
/// user's own stated goals, the feature list mirrors the plan they just
/// approved, and the price is framed per-day against the annual option.
struct PaywallView: View {
    @Environment(SubscriptionController.self) private var subs
    @Environment(Preferences.self) private var prefs
    @Environment(AuthController.self) private var auth

    /// Set on the paywall shown from Settings, which *is* dismissible.
    var isDismissible = false
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlanID: String?
    @State private var errorMessage: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var plan: MorningPlan { MorningPlan.make(from: prefs.quizAnswers) }

    private var selected: SubscriptionPlan? {
        subs.plans.first { $0.id == selectedPlanID } ?? subs.recommendedPlan
    }

    var body: some View {
        ZStack {
            SkyBackground(phase: .sunrise)

            VStack(spacing: 0) {
                if isDismissible { closeRow }

                // Losing the subtitle left the content shorter than the
                // screen, which bunched it at the top and opened a dead gap
                // above the buy button. Flexible gaps absorb the slack and
                // collapse to their minimum once the content does fill.
                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            headline
                            Spacer(minLength: 24).frame(maxHeight: 56)
                            benefits
                            Spacer(minLength: 24).frame(maxHeight: 68)
                            plans
                            proofStrip
                            if let errorMessage {
                                AuthErrorNote(message: errorMessage)
                                    .padding(.top, Theme.Space.md)
                            }
                            // At accessibility sizes the buy button, the
                            // renewal terms and the legal row need more than
                            // half the screen. Pinned to the bottom they get
                            // squeezed and spill over each other, so past that
                            // point they scroll with everything else.
                            if typeSize.isAccessibilitySize {
                                footer.padding(.top, Theme.Space.md)
                            }
                            Color.clear.frame(height: Theme.Space.sm)
                        }
                        .pageGutter()
                        .padding(.top, isDismissible ? Theme.Space.sm : Theme.Space.xl)
                        .containerRelativeFrame(.horizontal, alignment: .leading)
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                    .scrollIndicators(.visible)
                }

                if !typeSize.isAccessibilitySize { footer }
            }
        }
        .animation(Theme.Motion.quick, value: errorMessage)
        .animation(Theme.Motion.settle, value: subs.plans)
        .task {
            await subs.loadPlans()
            selectedPlanID = subs.recommendedPlan?.id
        }
    }

    // MARK: - Sections

    private var closeRow: some View {
        HStack {
            Spacer()
            IconButton(
                systemName: "xmark",
                accessibilityTitle: "Close",
                size: 13
            ) {
                dismiss()
            }
        }
        .pageGutter()
        .padding(.top, Theme.Space.sm)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(plan.paywallHeadline)
                .font(Theme.Typography.serif(30))
                .foregroundStyle(Theme.Palette.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefits: some View {
        // Three, not five. A row of identical ticks reads as a feature list;
        // a short set with a brand mark reads as an argument. Everything cut
        // here (custom prompts, searchable history) is table stakes for a
        // journal — these three are the reasons to pick this one.
        VStack(alignment: .leading, spacing: 18) {
            BenefitRow(
                lead: "The gate",
                detail: "Your phone stays shut until the page is written."
            )
            BenefitRow(
                lead: "A real alarm",
                detail: "Rings through silent mode and Focus, then hands you the page."
            )
            BenefitRow(
                lead: "Streaks that hold",
                detail: "One line counts. Showing up is the whole thing."
            )
        }
    }

    @ViewBuilder
    private var proofStrip: some View {
        if AppConfig.showsSocialProof, let quote = AppConfig.SocialProof.quotes.first {
            Spacer(minLength: Theme.Space.md).frame(maxHeight: Theme.Space.md)
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(quote.text)
                        .font(Theme.Typography.serif(16))
                        .foregroundStyle(Theme.Palette.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(quote.name)
                        .font(Theme.Typography.sans(11, weight: .medium))
                        .foregroundStyle(Theme.Palette.inkTertiary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var plans: some View {
        if subs.isLoadingPlans && subs.plans.isEmpty {
            // Skeletons rather than a spinner: they hold the exact layout the
            // real cards will occupy, so nothing jumps when prices land, and
            // they read as "this is nearly ready" instead of "something is
            // happening somewhere".
            VStack(spacing: 10) {
                Text("Select a plan that fits you")
                    .font(Theme.Typography.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 10) {
                    PricingCardSkeleton()
                    PricingCardSkeleton()
                }
                .padding(.top, 9)

                Text("Change plans or cancel anytime.")
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading plans")
        } else if let failure = subs.loadFailure, subs.plans.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                AuthErrorNote(message: failure)
                GhostButton(title: "Try again", systemImage: "arrow.clockwise") {
                    Task { await subs.loadPlans() }
                }
            }
        } else {
            VStack(spacing: 10) {
                Text("Select a plan that fits you")
                    .font(Theme.Typography.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(maxWidth: .infinity)

                // Both options on screen at once. Hiding the monthly price
                // behind a tap removes the very comparison that makes the
                // annual one look like a bargain.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(subs.plans) { option in
                        PricingCard(
                            plan: option,
                            isSelected: selected?.id == option.id
                        ) {
                            Haptics.tap()
                            withAnimation(Theme.Motion.quick) { selectedPlanID = option.id }
                        }
                    }
                }
                .padding(.top, 9) // room for the badge overhanging the cards

                Text("Change plans or cancel anytime.")
                    .font(Theme.Typography.sans(12))
                    .foregroundStyle(Theme.Palette.inkTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Space.sm) {
            EmberButton(
                title: subs.isPurchasing ? "Just a moment…" : callToAction,
                systemImage: subs.isPurchasing ? nil : "arrow.right",
                isEnabled: selected != nil && !subs.isPurchasing,
                action: buy
            )

            // Price, period, Restore, and functional Terms/Privacy links are
            // required on a subscription paywall (App Review 3.1.1 / 3.1.2).
            // Price and period live on the cards above, so this row stays —
            // but at a weight that lets the CTA do the talking.
            HStack(spacing: 14) {
                Button("Restore", action: restore)
                Link("Terms", destination: AppConfig.termsURL)
                Link("Privacy", destination: AppConfig.privacyURL)
                if !isDismissible {
                    // The only way off a hard paywall if you signed in with
                    // the wrong account.
                    Button("Sign out") { Task { await auth.signOut() } }
                }
            }
            .font(Theme.Typography.sans(11))
            .foregroundStyle(Theme.Palette.inkTertiary.opacity(0.85))
            .buttonStyle(.plain)
        }
        .pageGutter()
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, Theme.Space.md)
        .background(alignment: .top) {
            LinearGradient(
                colors: [Theme.Palette.canvas.opacity(0), Theme.Palette.canvas],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 28)
            .offset(y: -28)
        }
    }

    private var callToAction: String {
        guard let selected else { return "Continue" }
        guard let days = selected.trialDays else { return "Continue" }
        // Naming the length converts better than "Start free trial" — the
        // reader doesn't have to go hunting for what they're agreeing to.
        return days % 30 == 0
            ? "Start \(days / 30)-Month Free Trial"
            : "Start \(days)-Day Free Trial"
    }

    // MARK: - Actions

    private func buy() {
        guard let selected else { return }
        Task {
            do {
                errorMessage = nil
                try await subs.purchase(selected)
                Haptics.success()
            } catch let failure as PurchaseFailure {
                // Cancelling is a choice, not a failure worth a red banner.
                if failure != .cancelled { errorMessage = failure.errorDescription }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        Task {
            do {
                errorMessage = nil
                try await subs.restore()
                Haptics.success()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Rows

private struct BenefitRow: View {
    let lead: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 17))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Palette.gold, Theme.Palette.ember],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 24, alignment: .leading)
                .padding(.top, 1)

            (
                Text("\(lead): ")
                    .font(Theme.Typography.sans(15, weight: .semibold))
                    .foregroundColor(Theme.Palette.ink)
                + Text(detail)
                    .font(Theme.Typography.sans(15))
                    .foregroundColor(Theme.Palette.inkSecondary)
            )
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

/// One purchase option, as a card sitting beside its alternative.
/// Named to avoid colliding with the quiz's `PlanCard` payoff screen.
private struct PricingCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Square cells: a flexible shape carries the aspect ratio and the
            // content rides on top. Putting `.aspectRatio` after
            // `maxWidth: .infinity` instead collapses the pair into slivers.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(plan.title)
                                .font(Theme.Typography.sans(14, weight: .semibold))
                                .foregroundStyle(Theme.Palette.ink)
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 4)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .foregroundStyle(isSelected ? Theme.Palette.ember : Theme.Palette.ruleStrong)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
                        }

                        Spacer(minLength: 4)

                        Text(plan.price)
                            .font(Theme.Typography.sans(25, weight: .medium))
                            .foregroundStyle(Theme.Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        // The struck-through anchor is the whole argument for
                        // annual. Reserved even when absent so both align.
                        Text(plan.anchorPrice ?? " ")
                            .font(Theme.Typography.sans(13))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                            .strikethrough(plan.anchorPrice != nil, color: Theme.Palette.inkTertiary)
                            .lineLimit(1)
                            .padding(.top, 2)

                        Spacer(minLength: 4)

                        Text(footnote)
                            .font(Theme.Typography.sans(11))
                            .foregroundStyle(Theme.Palette.inkTertiary)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(15)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(isSelected
                          ? Theme.Palette.ember.opacity(0.18)
                          : Theme.Palette.emberSoft.opacity(0.10)),
            in: .rect(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isSelected ? Theme.Palette.ember.opacity(0.55) : Theme.Palette.rule,
                    lineWidth: isSelected ? 1.8 : 1
                )
        }
        // Overhangs the top edge so it reads as a sticker on the card.
        .overlay(alignment: .top) {
            if let savings = plan.savings {
                Text(savings)
                    .font(Theme.Typography.sans(10, weight: .bold))
                    .foregroundStyle(Theme.Palette.canvas)
                    .tracking(0.3)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Palette.ember))
                    .offset(y: -9)
            }
        }
        .animation(Theme.Motion.quick, value: isSelected)
    }

    private var footnote: String {
        plan.trialLabel == nil
            ? "Billed \(cadence)."
            : "Billed \(cadence) after free trial."
    }

    /// "per year" is right next to a price; in a sentence it wants the
    /// adjective form.
    private var cadence: String {
        switch plan.period {
        case "per year": "yearly"
        case "per month": "monthly"
        case "per week": "weekly"
        default: plan.period
        }
    }
}


/// Mirrors `PricingCard`'s geometry exactly — same square, same padding, same
/// bar positions — so the swap to real content is a fade, not a reflow.
private struct PricingCardSkeleton: View {
    private let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        SkeletonBar(width: 58, height: 12)
                        Spacer(minLength: 4)
                        Circle()
                            .fill(Theme.Palette.ink.opacity(0.09))
                            .frame(width: 17, height: 17)
                    }

                    Spacer(minLength: 4)

                    SkeletonBar(width: 104, height: 24, radius: 6)
                    SkeletonBar(width: 62, height: 12)
                        .padding(.top, 8)

                    Spacer(minLength: 4)

                    SkeletonBar(width: 92, height: 9)
                    SkeletonBar(width: 58, height: 9)
                        .padding(.top, 5)
                }
                .padding(15)
            }
            .glassEffect(
                .regular.tint(Theme.Palette.emberSoft.opacity(0.10)),
                in: .rect(cornerRadius: 22)
            )
            .overlay {
                shape.strokeBorder(Theme.Palette.rule, lineWidth: 1)
            }
            .shimmering(in: shape)
    }
}

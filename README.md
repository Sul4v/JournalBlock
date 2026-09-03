# Dawn

A morning journal that holds the phone hostage until the page is written.

SwiftUI, Liquid Glass, iOS 26. Supabase for accounts, RevenueCat for billing.
Minimal, light, warm, calm.

---

## Run it

```bash
open Dawn.xcodeproj
```

Pick a simulator and run. **It works right now with no keys configured** — auth
and purchases fall back to on-device stand-ins so the entire funnel is
walkable. See "Going live" below to point it at real backends.

The project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen).
**After adding or deleting a source file, run `xcodegen generate`.** The
`.xcodeproj` is disposable; `project.yml` is the truth.

---

## The funnel

Each stage must clear before the next is rendered. `RootView` owns this chain.

```
quiz  →  account  →  paywall  →  today's page  →  the app
```

**1. Quiz (12 screens).** Hook → name → seven questions → wake time →
"building your plan" → a personalised plan → social proof → press-and-hold
commitment. Single-choice questions auto-advance; nothing takes more than a tap.

**0. Welcome.** Two doors. New users get the quiz; anyone who already has an
account skips straight to sign-in. Making a returning user answer fourteen
questions to reach a login button is how you turn a lapsed user into a churned
one — so signing in with `hasCompletedQuiz` false marks the quiz done rather
than forcing it.

**2. Account.** Two stages. The first screen offers Apple, Google, and email —
and nothing else. Picking email pushes to a second screen with the fields,
strength meter, and password reset. Three fields, a meter and a legal paragraph
all competing on arrival is what makes a sign-up screen feel like paperwork;
most people never see the form at all.

Asked *after* the quiz, so it reads as "save my plan" rather than "give us your
email".

**3. Paywall.** Hard. Headline is generated from their own quiz answers, the
plan list leads with a single recommended option, and price is framed per-month
against the annual term.

**4. The morning gate.** Unchanged from v1 — no dismiss, no tab bar, no escape.

Why this order: the quiz makes the user articulate their own problem before
being asked for anything; the account exists before the paywall so a purchase
has somewhere to attach; the journal gate is last because it's the only one
that repeats daily.

---

## Two decisions you should overrule if you disagree

### The hard paywall

You asked for it, and it's implemented literally: no free tier, no dismiss, no
trial-of-the-app. This converts better and it is also **the single biggest App
Review risk in the project.** Guideline 3.1.2 permits subscription-gated apps,
but reviewers reject hard paywalls regularly, usually citing an inability to see
any of the app before paying.

Mitigations already in: Restore Purchases, Terms and Privacy links, exact price
and renewal terms next to the button, and a Sign Out escape.

If you get rejected, the cheapest fix is a limited free tier — say, three
mornings before the wall. That's a change in `RootView.stage`, not a rewrite.
I'd suggest submitting hard, and keeping the softer variant ready.

### Sign in with Apple

`Dawn/Dawn.entitlements` requests `com.apple.developer.applesignin`. Xcode's
automatic signing provisions this for any paid team, so it should just work —
but if signing fails on your account, delete that key and the SIWA button.

Keep it either way: now that Google sign-in is in, Apple **requires** Sign in
with Apple alongside it (Guideline 4.8). Shipping Google without Apple is an
automatic rejection.

---

## Going live

Everything is behind `Dawn/App/AppConfig.swift`. Fill in three values.

### Supabase

1. Create a project. Copy the URL and the `anon` key into `AppConfig`.
2. Run `supabase/schema.sql` in the SQL editor. It creates the `profiles` table,
   locks it with RLS, auto-creates a profile on sign-up, and defines the
   `delete_account` function.
3. For Sign in with Apple: Authentication → Providers → Apple, add your Services
   ID and key.
4. Decide on email confirmation (Authentication → Providers → Email). If it's on,
   sign-up returns no session and the app shows "check your inbox" — which is
   correct, but it's a real drop-off point. Consider leaving it off at launch.

**Account deletion needs that SQL function.** The client SDK cannot delete an
auth user — that requires the service role key, which must never ship in an app.
`delete_account()` runs as its owner and deletes only `auth.uid()`. Apple
requires in-app deletion for any app with accounts (Guideline 5.1.1(v)), so this
isn't optional.

### Email delivery — required before launch

Supabase's built-in SMTP is capped at a couple of messages an hour and is
explicitly not for production. Every sign-up sends a confirmation email, so the
cap is hit almost immediately during testing (`over_email_send_rate_limit`).

Two things:

- **While testing:** Authentication → Sign In / Providers → Email → turn
  **Confirm email** off. Sign-up then returns a session directly and sends
  nothing.
- **Before launch:** Project Settings → Authentication → SMTP Settings, and
  point it at a real sender (Resend, Postmark, SendGrid, SES). Without this,
  confirmation and password-reset emails will not reach real users.

### Google

1. Google Cloud console → APIs & Services → Credentials → create an **iOS**
   OAuth client for bundle id `com.sulav.journalblock`.
2. Paste the client ID into `AppConfig.googleClientID`.
3. Take the **REVERSED_CLIENT_ID** (the client ID with its dot-segments
   reversed, starting `com.googleusercontent.apps.`) and replace the
   placeholder in `project.yml` under `CFBundleURLSchemes`, then run
   `xcodegen generate`. **Google's callback cannot reach the app without this**
   — sign-in will open and then hang.
4. Supabase → Authentication → Providers → Google. Add the client ID. If you
   configure it against a *web* client ID instead, put that in
   `AppConfig.googleServerClientID` too.

Until step 2 is done the Google button falls back to the local stand-in, same
as everything else.

### RevenueCat

1. Create an app, connect it to App Store Connect.
2. Paste the **public** Apple SDK key (`appl_…`) into `AppConfig`.
3. Create an entitlement called `premium` (or change `AppConfig.entitlementID`).
4. Build an offering with an annual and a monthly package. Add a 7-day
   introductory free trial to the annual one — the paywall copy reads the trial
   off the product, so it adjusts itself.

Prices, savings percentages, and the "$2.50 / month" framing are all derived
from the store's own localised prices. Nothing is hard-coded, so it stays correct
in every currency.

### Legal

`AppConfig.termsURL` and `privacyURL` currently point at `dawn.app` placeholders.
**These must resolve before you submit** — a dead Terms link on a paywall is a
guaranteed rejection.

---

## Account, sign out, delete

- **Settings → Account** shows email, member-since, subscription status, and
  renewal date.
- **Manage** opens the App Store subscription page (the only place billing can
  actually be changed). **Restore** re-syncs entitlements.
- **Sign out** confirms first and leaves the journal on the device.
- **Delete account** is a separate screen: it lists exactly what's destroyed,
  warns that deletion does *not* cancel billing (with a link to do that), and
  requires typing `DELETE`. It calls the server first — if that fails, nothing
  local is destroyed — then wipes SwiftData and every preference.

---

## The rest of the app

| Screen | State |
|---|---|
| Morning gate | Greeting → journal. No dismiss, no tab bar, no escape |
| Journal session | Mood check-in, one prompt per card, completion card |
| Today | Streak, totals, mood, this morning's writing, evening reflection |
| Entries | All past days, tap through to a full read |
| Settings | Account, wake time, alarm, strict mode, app blocking, prompts |
| Prompts | Reword, disable, add your own, delete custom ones |

**Alarm (AlarmKit).** Real iOS 26 API — rings through silent mode and Focus.
Missing the Lock Screen countdown, which needs a widget extension target.

**Blocking other apps (Screen Time).** `ShieldService` is complete but the
`com.apple.developer.family-controls` entitlement **requires Apple to approve
your team**, and adding it before approval breaks signing. It's deliberately not
in the build. `FamilyControls.entitlements` has the one-line change.
Request access: https://developer.apple.com/contact/request/family-controls-distribution

---

## QA harness

`DEBUG` builds take launch arguments. Edit the scheme → Run → Arguments:

```
-dawnScreen paywall -dawnDemoAccount -dawnSeedSampleData
```

- `-dawnScreen` — `onboarding` `auth` `paywall` `account` `gate` `journal`
  `writing` `complete` `home` `history` `settings` `prompts`
- Forced screens show an **Exit debug** badge (bottom right) that drops back
  into the normal flow. Several debug screens are pushed views with no parent,
  so without it a launch strands the app until you force-quit — and a debug
  dead end looks exactly like a broken screen. **Always relaunch with no args
  after a sweep**, or you'll leave the app parked somewhere with no way out.
- `-dawnSlowStore` — holds the paywall in its loading state so the plan
  skeletons can be inspected. RevenueCat caches offerings, so the real
  window is far too short to screenshot after the first fetch.
- `-dawnOnboardingStep <0–12>` — jump into the quiz at any step
  (0 name, 1–7 questions, 8 wake time, 9 analysing, 10 plan, 11 proof,
  12 commit). The old step 0 hook is now the separate welcome screen.
- `-dawnDemoAccount` — sign into a local demo account and grant entitlement
- `-dawnSeedSampleData` — two weeks of entries, with gaps, so streaks are real

Screenshots from this pass are in `shots/`.

---

## What I'd do next, in order

1. **Fill in the three keys and run the schema.** Nothing else can be verified
   against reality until then.
2. **Get the legal pages up.** Blocking for submission.
3. **Request the Family Controls entitlement.** Long lead time, and the app's
   premise depends on it.
4. **Wire a paywall A/B test.** RevenueCat can serve different offerings by
   cohort; the paywall already renders whatever it's given, so this is mostly
   configuration. Test annual-only vs annual+monthly first — it's usually the
   biggest single lever.
5. **Add analytics on funnel drop-off.** You cannot tune a 12-step flow you
   can't see. Instrument each quiz step, the account screen, and the paywall.
6. Sync journal entries to Supabase (they're local-only today).
7. Live Activity widget for the alarm countdown.

## Known rough edges

- Journal entries never leave the device. The Entries tab reads straight from
  SwiftData, so history already works with no backend configured. The sign-up copy now only promises
  that the *subscription* follows you, which is true — but build sync before you
  promise more than that.
- Testimonials and the 4.8 rating on the paywall and proof screen are
  **placeholders**. Replace them with real reviews before you ship — invented
  social proof is both a legal problem and an App Review problem.
- No email-confirmation waiting screen; the app surfaces it as an inline error.
- The background carries a dust glimmer: 70 small specks, each flashing on its
  own 3–9s clock and floating a Lissajous path (separate x/y periods, so it
  never traces a loop the eye can follow). Size and brightness are inversely
  paired, which is what gives the field depth. Drawn as one `Canvas` in a
  `TimelineView` at 24fps rather than 70 animated views, and it respects
  `prefers-reduced-motion` by switching off entirely.
- Note the timeline redraws on every screen. In the simulator the dust costs
  ~2–3% CPU over a ~6% baseline that is mostly software rendering; if battery
  ever shows up on device, gating this to the onboarding flow is the first
  lever.
- The commitment gesture is a press-and-hold on a fingerprint. VoiceOver can't
  express a hold, so it gets a plain activate action instead — worth checking if
  you care about the accessibility audit.
- Prompt order is creation order; no drag handle.
- Past entries can't be edited or deleted from the UI.
- No iPad layout (iPhone-only, portrait).

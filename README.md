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
quiz  →  account  →  paywall  →  permissions  →  the app, with prompts ready for tomorrow
```

**1. Quiz (14 screens).** Hook → name → seven questions → wake time → bedtime →
"building your plan" → a personalised plan → the morning sitting → the evening
sitting → press-and-hold commitment. Every question carries a Continue button: tapping
an option only selects it, so a mis-tap costs a correction rather than a screen.

The answers no longer pick the prompts. Everyone starts on the same five
questions — three in the morning, two at night — and the two sitting screens
are where the user sets each time and sees the actual questions before paying.
A page chosen from a quiz was a guess wearing personalisation's clothes, and
every word of this one is editable in Settings the moment they disagree with
it. The quiz still earns its length: it makes the user articulate their own
problem, and it writes the plan screen and the paywall headline.

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

**4. Permissions.** Three, in the order the feature needs them, each explained
before iOS puts up its own dialog: notifications, Screen Time, then the alarm.
Notifications come first because they are load-bearing — the shield's "Write it
now" button cannot open this app directly, so it posts a notification and the
user taps that (see below). Granting Screen Time opens the app picker inline,
because authorisation without a selection shields nothing at all.

Asked *after* the paywall: before it, the app is asking someone who hasn't
decided to keep it to hand over Screen Time. Every step is skippable, and
declining any of them leaves a working app with the in-app gate — a wall of
permissions the user can't get past is both a bad first minute and a reliable
App Review rejection. `Preferences.hasPrimedPermissions` records that the screen
was *seen*, not that anything was granted, so a decline isn't re-asked on every
launch. Settings is where they change their mind.

**5. Ready for tomorrow.** New signups land on Today with both sittings laid
out — the questions they'll answer tomorrow — and an Edit prompts link. The first session starts the next
calendar day after they clear the paywall. This date survives relaunches and
sign-outs; previewing prompts does not create an entry or count toward a streak.
From the next day onward, the morning gate requires that day's session before
opening the main tabs (unless strict mode is off).

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

Third-party assets, both of which need their notice carried wherever you list
acknowledgements:

- `FingerprintMark` (the commit-screen print) is Material Symbols
  `fingerprint`, weight 100 — Google, Apache License 2.0.
- `GoogleMark` is Google's own sign-in mark, used under their branding
  guidelines.

Note the print is deliberately *not* SF Symbols' `touchid`. Symbols depicting
Apple technologies are licensed only for referring to those technologies, and
this screen is a commitment gesture, not a biometric prompt.

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
| Journal session | One prompt per card, completion card |
| Today | Streak, then one section per block — what was written, or Begin |
| Entries | All past days, tap through to a full read |
| Settings | Account, backup, wake alarm, strict mode, app blocking, prompts |
| Your Prompts | Blocks: a time, a name, its prompts. Add, retime, rename, delete |

**Blocks.** The day is however many sittings the user wants, each with its own
time and prompts. A new account starts with two — Morning and Evening, at the
times set during signup — and can add, retime, rename or delete any of them.
Any number of blocks may hold the lock ("locks your phone until written"); the
first of the day is owed from midnight, the rest as their hour arrives, and
deleting the last one holding it hands the lock on rather than dropping it. Any block written counts
for the streak. Optional per-block reminder notifications; the AlarmKit wake
alarm stays with the gating block. Existing installs migrate on first launch:
the old wake time becomes a "Morning" block holding the lock, evening prompts
become an "Evening" block at 9pm, and an evening that was switched off arrives
with its prompts off rather than missing.

**Alarm (AlarmKit).** Real iOS 26 API — rings through silent mode and Focus.
Missing the Lock Screen countdown, which needs a widget extension target.

**Blocking other apps (Screen Time).** Live. `com.apple.developer.family-controls`
is on the app target and all three extensions; it **requires Apple to approve
your team** and adding it before approval breaks signing, so a fresh clone on an
unapproved team will not sign.
Request access: https://developer.apple.com/contact/request/family-controls-distribution

Four pieces:

| Piece | Where | Job |
| --- | --- | --- |
| `ShieldService` | app | Authorisation, the app selection, applying and clearing the shield while the app runs |
| `ShieldConfiguration` | extension | Draws the shield the user hits, naming the owed block |
| `ShieldAction` | extension | The two buttons on it |
| `DeviceActivityMonitor` | extension | Re-applies the shield on schedule when the app isn't running |

The extensions are separate processes and **cannot read SwiftData**, so
`Shared/GateBridge.swift` mirrors the owed block and the app selection into the
`group.com.sulav.journalblock` app group. That app group and `GateBridge.appGroup`
must stay in step, as must `GateBridge.storeName` and the `ManagedSettingsStore`
name in `ShieldService` — two differently-named stores means a shield the app
believes it cleared is still standing.

**The shield cannot open this app.** `ShieldActionDelegate` may only return
`.none`, `.close` or `.defer`. There is no `open(url:)`, `UIApplication` is
unavailable to that extension type, and `NSExtensionContext` isn't offered
either. Reaching `UIApplication` via `NSClassFromString` does work and is what
several shipping blockers do, but it is private API on an entitlement Apple
reviews by hand. So "Write it now" posts an immediate local notification
carrying `journalblock://block/<uuid>` and closes the shielded app: the user
lands on the home screen with the banner already there, and one tap opens the
gate. That is one more tap than we'd like and it is why the permission primer
asks for notifications first — without them the button can only bounce the user
to the home screen.

`GateScheduler` registers one `DeviceActivitySchedule` per gating block. The
first starts at midnight rather than its own hour, matching
`JournalStore.pendingGateBlock`; every window ends at 23:59 so a shield can
never outlive the day it belongs to.

**Extension Info.plists are generated.** XcodeGen writes them from
`project.yml`, so `NSExtension` is declared there — anything hand-written into
`ShieldAction/Info.plist` and friends is overwritten by the next
`xcodegen generate`, and an extension with no `NSExtension` dict is one the
system silently never launches.

---

## QA harness

`DEBUG` builds take launch arguments. Edit the scheme → Run → Arguments:

```
-dawnScreen paywall -dawnDemoAccount -dawnSeedSampleData
```

- `-dawnScreen` — `onboarding` `auth` `paywall` `permissions` `account` `gate`
  `journal` `writing` `complete` `home` `tomorrow` `history` `settings` `prompts`
- Forced screens show an **Exit debug** badge (bottom right) that drops back
  into the normal flow. Several debug screens are pushed views with no parent,
  so without it a launch strands the app until you force-quit — and a debug
  dead end looks exactly like a broken screen. **Always relaunch with no args
  after a sweep**, or you'll leave the app parked somewhere with no way out.
- `-dawnSlowStore` — holds the paywall in its loading state so the plan
  skeletons can be inspected. RevenueCat caches offerings, so the real
  window is far too short to screenshot after the first fetch.
- `-dawnOnboardingStep <0–14>` — jump into the quiz at any step
  (0 name, 1–7 questions, 8 wake time, 9 bedtime, 10 analysing, 11 plan,
  12 morning sitting, 13 evening sitting, 14 commit). The old step 0 hook is
  now the separate welcome screen.
- `-dawnDemoAccount` — sign into a local demo account and grant entitlement
- `-dawnSeedSampleData` — two weeks of entries, with gaps, so streaks are real

Screenshots from this pass are in `shots/`.

---

## What I'd do next, in order

1. **Fill in the three keys and run the schema.** Nothing else can be verified
   against reality until then.
2. **Get the legal pages up.** Blocking for submission.
3. **Family Controls entitlement — already on the build.** Approval has a long
   lead time and the app will not sign without it; the app's
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
- The background is neutral ivory with a single, static daylight wash that
  fades into the page. Its tint follows the time of day and adapts to dark mode;
  Increase Contrast softens the wash further. Fine gold flecks drift upward and
  occasionally glint, drawn together in one Canvas at up to 30fps. The timeline
  pauses while the app is inactive; Reduce Motion shows a subdued, still field.
  The gradient itself stays still, with no grain or large glowing patches.
- The commitment gesture is a press-and-hold on a fingerprint. VoiceOver can't
  express a hold, so it gets a plain activate action instead — worth checking if
  you care about the accessibility audit.
- Prompt order is creation order; no drag handle.
- Past entries can't be edited or deleted from the UI.
- No iPad layout (iPhone-only, portrait).

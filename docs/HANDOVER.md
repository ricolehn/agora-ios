# Handover: iOS 1.0.0 *APPA*

State of the iOS app at the handover (October 2026), what has to be checked on a device before the App Store release,
how to release, and what is still open compared with Android. Conventions for working on the code are in
[AGENTS.md](../AGENTS.md).

## Where the app stands

- **Feature level:** the web app 3.2 *AIR TEMPLE* and the Android app 1.2.0 *AZULA* (released 20 October 2026). The
  [changelog](../CHANGELOG.md) lists everything that changed since the last tested build (beta3) and the
  intermediate *ORION* commit.
- **Verified:** the app compiles for iOS with Xcode 26.6 (iOS 26 SDK) on GitHub Actions, without Swift warnings, the
  privacy manifest ends up in the app bundle, and the 31 logic tests pass on macOS and Linux. Their expected values
  come from the web app's and Android's tests (amounts, request bookings, status history, standing orders, share
  links, guests, Termine filter, songbook, logo).
- **Not verified on a device:** as far as known, nothing since beta3 (the *ORION* commit and *APPA*) has run on a
  simulator or device – the previous maintainer has no Apple device any more. Treat this version as a release
  candidate: go through the checklist below on an iPhone and an iPad first.

## Device checklist before the release

Use a test server with version 3.2 or newer (sharing needs it) and these accounts: a member, a treasurer
(`manage_finances`), an event manager (`manage_events`), an approved mentor, a mentoring manager and an admin. Test on
an iPhone (also a small one, e.g. SE or mini) and an iPad, in light and dark mode. Compare with the web app in a
browser where something looks unclear: it decides.

**Update and start**
- [ ] Install over a build of beta3 or *ORION* with a signed-in account: the session stays (the account moves from
      UserDefaults to the Keychain on the first start), data and logo show at once.
- [ ] Second start, also in flight mode: the church logo shows immediately, without the Agora knot first.
- [ ] A server with its default logo shows the bundled knot (light green in dark mode); a logo changed in the web
      app's system settings shows up when the app comes back to the foreground (the server is asked at most once a
      minute).
- [ ] Right after login (no trip to the background): change something in the web app, the app updates by itself.

**Finances**
- [ ] Member: request tiles show also for an account without a member record; a payment request with "1.500" turns
      the field red with the hint, "1.500,00" and "1500" work; an expense with photo receipts, and one without.
- [ ] Treasurer, two devices: approve the same request on both – the second says "Diese Anfrage wurde bereits
      entschieden.", the payment is booked once (check the member's history in the web app too).
- [ ] Approve and reject at the same moment on two devices: the approval that lost takes its booking back.
- [ ] Book payment, standing order and status change; end a standing order retroactively; record a donation and an
      expense; open a member in the fee list, pull to refresh: the history stays.
- [ ] Settings → Monatliche Beiträge: an empty field keeps its rate, "1.500" blocks saving.
- [ ] Financial report PDF: the church logo is drawn (light version on the white page).

**Events and sharing**
- [ ] The share icon sits right of title and organiser and ends where the cards end; on iPad as well.
- [ ] The link in the sheet is the same as the web app's share link for the same event (also for repeated titles:
      `_<date>` or `~<id>`); *Link kopieren* and *Teilen …* (Messages, Mail, WhatsApp) work.
- [ ] As editor: *Ohne Konto sichtbar* on → the link gets `?share=…`; opened in a private browser window it shows the
      guest page; off → members' link. As member without edit rights: no switch. Against a server before 3.2: no
      switch, no error.
- [ ] Sign up as a guest in the browser: the attendee list marks "Gast"; the editor sees e-mail (tap opens Mail) and
      age and can remove the guest; a member sees neither.
- [ ] Long place and date on a small iPhone stay on one line and end with "…".
- [ ] New event: times shown are times saved, *Endzeit hinzufügen* / remove works, no empty default tasks appear in
      the plan; a member without the event permission gets the editor straight from "+".
- [ ] Plan card: answer a request, add a task and a song, ask a person and a group.

**Everything else**
- [ ] Mentoring chat: messages arrive while open; in the background the app stops polling; the "…" menu appears once
      the conversation is loaded; report, block, end, reopen.
- [ ] Extras: AI chat (with permission), songbook (transpose, editor with the "Tonart" field), prayer requests.
- [ ] Settings: profile picture from a transparent PNG gets a white background; notifications; colour scheme;
      password change; calendar subscription; account deletion (text lists what the server deletes).
- [ ] VoiceOver on the share icon, the share sheet and the attendee rows; large Dynamic Type sizes.
- [ ] iOS 26 look: tab bar, navigation bars and sheets take on Liquid Glass by themselves – check that the app's own
      header, cards and the floating "+" still look right with it.

## Releasing on the App Store

1. **Apple Developer Program** membership for the publisher (non-profits can ask Apple for a fee waiver).
2. **Bundle id.** `Package.swift` uses `org.agora.app` (the same id as the Android package). Register it in the
   developer account; if it is taken, choose the publisher's reverse domain and keep it from then on.
3. **Team id** into `teamIdentifier` in `Agora.swiftpm/Package.swift`.
4. **Version and build:** `displayVersion` `1.0.0`, `bundleVersion` higher than every upload before (currently `3`,
   so `4` for the first upload of 1.0.0).
5. **Archive** with Xcode 26 or later (*Product → Archive*, then *Distribute App*), TestFlight first.
6. **Privacy:** the privacy manifest (`PrivacyInfo.xcprivacy`, UserDefaults with reason CA92.1, no tracking) is part
   of the app – CI checks that it ends up at the root of the app bundle. In App Store Connect's privacy questionnaire
   describe what the app sends: everything goes to the community's own server, the publisher receives no data; decide
   with that in mind and keep the manifest in line with the answers. Privacy policy URL: the publisher's policy, or the
   Agora policy ([PRIVACY.md](https://github.com/ricolehn/agora/blob/develop/PRIVACY.md)).
7. **Export compliance:** the app uses only HTTPS (exempt encryption); answer the question in App Store Connect.
8. **App Review notes:** a demo server with demo accounts (member and treasurer), and a sentence on the model: every
   community runs its own server, the app asks for its address. User-generated content: mentoring chats can be
   reported and blocked; prayer requests are removed by moderators but have no report button yet – be ready to explain
   that or add reporting (Guideline 1.2). Account deletion is in the app (Settings → Datenschutz & Konto).
9. **Screenshots** for iPhone (6.9") and iPad (13"), age rating questionnaire (chat and user content).
10. Afterwards: tag `v1.0.0` on GitHub, move the changelog entry from *unreleased* to the date, and ask for the iOS
    app to be mentioned on the server's account deletion page (`ACCOUNT_DELETION.md` / `account-deletion.html` in
    agora name only the Android app).

## Open compared with Android

**Larger features**
- **Push notifications.** Android gets every notification by Firebase Cloud Messaging: it fetches the server's
  Firebase client config (`GET /api/push/fcm`), registers its token (`POST /api/push/fcm/subscribe` with
  `platform`), unsubscribes on logout, shows channels for duties, events, messages and finances and opens the matching
  event or tab when tapped; settings show the device's push state with a test button (`POST /api/push/test`). For iOS
  the backend needs APNs delivery or FCM for iOS (APNs key in the server's Firebase project, Firebase SDK in the
  app); until then e-mail notifications and live updates while open. Android also checks for news every 15 minutes
  without push – on iOS a `BGAppRefreshTask` with local notifications could do the same without server changes.
- **English translation** and the language choice (Android: System / Deutsch / English). iOS is German only; on
  English devices dates and money switch to en_GB while texts stay German.
- **Interactive cropping** for cover images (16:9) and profile pictures (Android: pan, pinch, round mask, always
  256×256); iOS crops the centre.
- **Tables in AI answers** (Android renders GitHub-flavoured Markdown).
- Songs, prayers and polls send their own live update areas; like Android the app reloads the member data but not an
  open song or prayer page.

**Small differences** (cosmetic, take them along when touching the screen)
- Login: the keyboard's "Weiter" does not move to the next field (`IconField` keeps its own focus).
- Notification settings save after a short pause and are not read back from the server afterwards.
- Mentor capacity 1–20 (Android 1–99); load errors of songbook and prayers show the generic text.
- Duty request card shows the time range (Android only the start); the event page shows a "Termin"/"Event" tag;
  only the small button opens Maps (Android: the whole place row).
- Texts that differ slightly from Android: the request tiles' heading, request type names ("Statusänderung" /
  "Auslage"), the empty states of requests and the plan, the calendar legend ("Highlight").
- Debug builds on Android show the last crash at the next start; on iOS use Xcode's and TestFlight's crash reports.

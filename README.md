<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/assets/logo-dark.svg" />
    <img src=".github/assets/logo.svg" width="110" alt="Agora Logo" />
  </picture>
  <h1>Agora for iOS</h1>
</div>

Native iOS and iPadOS client for [Agora](https://github.com/ricolehn/agora), built with SwiftUI.
It talks to the same backend as the web app (PWA) and the [Android app](https://github.com/ricolehn/agora-android),
follows the web app's design and uses native iOS controls where people expect them – tab bar, navigation,
forms in sheets, menus, confirmation dialogs, the photo picker and the share sheet.

**Status:** `v1.0.0` (codename **APPA**) – on the level of the web app 3.2 *AIR TEMPLE* and the Android app 1.2.0
*AZULA*: sharing events with guests who have no account, requests that are booked only once, strict amounts, the church
logo kept on the device. Feature complete for members, treasurers, event managers and mentoring. The code builds on CI
with Xcode 26 and passes the logic tests; **it has not been tested on a device yet** – before the App Store release
follow the checklist in [docs/HANDOVER.md](docs/HANDOVER.md). Push notifications are not available on iOS yet (see
[Roadmap](#roadmap)).

## Features

| Area | What the app does |
|---|---|
| **Start** | Greeting with date, overdue or soon-due membership fee (nothing while all is paid), open duty requests with *Accept* / *Decline*, open finance requests for treasurers, *Als Nächstes* (the next five appointments and events as a swipeable row), your upcoming duties, unread mentoring messages |
| **Finances (members)** | Fee status with monthly rate, requests (payment, standing order, status change, expense with receipts), own requests with details, status and rejection reasons, standing orders, payment history |
| **Finances (treasurers)** | Cash balance, open requests (detail sheet, approve / reject with reason; a request is booked only once, also against the web app and Android), searchable and paged booking history with receipts and member avatars, **financial report as PDF** (annual, period, member or hand-picked bookings; compact / standard / detailed; preview, share, save to Files), fee list (overdue / current), member details with payment booking, standing orders (end, also retroactively, or delete) and status changes, record donations and expenses. Amounts are read like the web app: "1.500" is not guessed, the field says how to write it |
| **Events** | *Termine* (slim cards with the own status in the time line, multi-day events on every day; on iPad with a month calendar that jumps to the chosen day) and *Events* (cover cards, highlights, past events), search, detail page with map link, Markdown description, registration / waiting list, attendees (guests without an account marked; their e-mail and age for the event's editors), **plan**: duty roster and order of service in one card (timeline with start times from the durations, songs with key, tasks without a time, answer requests; editors add tasks or songs, ask people or groups, set position, duration, key and note), create / edit / delete incl. 16:9 cover, target groups and recurring appointments |
| **Sharing** | Share icon right of every event's title and organiser: a sheet with the event's link (the same address the web app builds) to copy or to hand to the share sheet, and, for those who may edit the event, the switch *Ohne Konto sichtbar* (server 3.2 or newer) that lets people without an account open the link and sign up as guests in the browser |
| **Mentoring** | Conversations with unread badges (mentees stay anonymous), chat with live polling while open, report / block / end / reopen, find and contact mentors anonymously, mentor application and profile, application review for mentoring managers |
| **Extras** | One tab for the further apps of the community: **AI support** (start with suggested questions, streaming answers as Markdown beside a sparkle, collapsible reasoning, "Neuer Chat", report an answer; only with permission and when AI is enabled on the server), **songbook** (searchable alphabetical list, song page with chords above the syllables, transposing incl. German H/B notation, chords on/off and text size, CCLI notes; editor with live preview for members with the songbook permission) and **prayer requests** (share with name or anonymously for a week, a month or three months, All / Mine, extend or remove own requests, moderators remove any) |
| **Settings** | Sub-pages like the web: profile picture (cropped to 256×256 JPEG), registration code, notifications per channel (push / e-mail) and kind, colour scheme (system / light / dark), monthly fees (admins), password change, calendar subscription (Apple / Google Calendar), privacy policy, sign out, **account deletion** |

While the app is open it listens to the server's live updates (`/api/stream`, server-sent events) and refreshes the
affected data. It opens instantly with the last loaded data (kept on the device, excluded from backups, deleted on
sign-out) and the community's logo, and refreshes in the background. It reports the device's time zone, so duty
reminders arrive at the right local time. Dark mode and VoiceOver labels are included.

## Requirements

- iOS / iPadOS **17** or later on the device
- **Xcode 26** or later on a Mac – App Store Connect only accepts apps built with the iOS 26 SDK
  ([since 28 April 2026](https://developer.apple.com/news/upcoming-requirements/)); CI builds with Xcode 26.6
- or **Swift Playgrounds** (iPad or Mac) to run the app and make quick changes
- An Agora server reachable over **HTTPS** (the same address members open in the browser); sharing events with guests
  needs server 3.2 or newer

## Getting started

The app is a Swift Playgrounds app package (`Agora.swiftpm`).

**Xcode (Mac)**
1. `git clone https://github.com/ricolehn/agora-ios.git`
2. Double-click `Agora.swiftpm` (or *File → Open…*), choose a simulator or device and run.

**Swift Playgrounds (iPad or Mac)**
1. Download the repository (*Code → Download ZIP*) or clone it, and put `Agora.swiftpm` into iCloud Drive / Files.
2. Open `Agora.swiftpm` in Swift Playgrounds and press *Run*.

On first launch the app asks for the server address, then for login or registration with the community's
six-digit registration code. In debug builds the simulator can also use a local test server on
`http://localhost:<port>`.

## Tests and CI

```bash
./scripts/test-logic.sh
```

compiles the UI-free logic (`Core/Domain`, `Core/Models`, `Core/Support`, the songbook logic) together with the tests
in `Tests/LogicTests` and runs them – on a Mac with Xcode, or on Linux with a [Swift toolchain](https://www.swift.org/install/linux/).
The tests compare the app's rules with the web app and Android: typed amounts, request bookings, status history,
standing orders, share links, guests, the Termine filter, the songbook and more. The app package itself has no test
target, because Swift Playgrounds cannot run one.

[GitHub Actions](.github/workflows/ios.yml) runs the logic tests on Linux and macOS and builds the app for iOS with the
newest stable Xcode on every push and pull request; it also checks that the privacy manifest ends up in the app.

## Architecture

```
Agora.swiftpm
├── Package.swift            Swift Playgrounds app product (bundle id org.agora.app, iOS 17, version 1.0.0)
├── PrivacyInfo.xcprivacy    privacy manifest (UserDefaults, no tracking)
├── App/                     entry point, router (one navigation stack per tab), tab shell with header
├── Core/                    everything without UI
│   ├── Models/              API models with lenient decoding (numeric ids, German amounts "12,50", nulls)
│   ├── Networking/          APIClient (URLSession, Bearer token only to the own server, uploads, SSE and
│   │                        AI streams), Repository and ExtrasRepository (every endpoint the app uses)
│   ├── Store/               AppStore (@Observable: session, member data, live updates), Keychain session,
│   │                        on-device data cache
│   ├── Domain/              rules shared with web and Android: request bookings, standing orders, status
│   │                        history, event links, Termine filter, event badges, Markdown blocks, AI reasoning,
│   │                        server logo
│   └── Support/             JSONValue for untyped records, lenient decoder, strict amounts, date and money
│                            formats, APIError
├── DesignSystem/            colour tokens of the web app (light / dark), cards, buttons, pill tabs, avatars with
│                            role rings, authenticated image loading, server logo store, toasts, Markdown view
└── Features/                Auth, Home, Finance, Events (incl. the plan and sharing), Mentoring, Hub (Extras), AI,
                             Songbook, Prayers, Settings
Tests/LogicTests             logic tests, run by scripts/test-logic.sh
```

- Endpoints, payloads and write flows follow the backend in the Agora repository and are ported from the Android
  client. Standing orders, status history and approved requests are written exactly like the web app
  (`assets/finance.js`), so all clients produce identical records.
- Records the app changes as a whole (people, requests, donations, expenses) are read and written as `JSONValue`,
  so fields the app does not know are kept.
- Texts are German and used as localisation keys (`LocalizedStringKey` / `String(localized:)`); an English
  translation only needs a `Localizable.xcstrings`.

Working on the code, alone or with an AI coding agent: [AGENTS.md](AGENTS.md) has the conventions, the map from the
Android files to the iOS files and how to verify a change.

## Look & feel

The screens follow the web app v3.1 (`assets/style.css` and `assets/polish.css`, palette "Stone & Lagoon"): warm
stone neutrals, a deep lagoon teal that runs into emerald, a dark theme tuned on its own (near-black, soft off-white
text, no coloured light), hairline cards, pill tabs, calendar leaves for events and role rings around profile pictures
(members teal, mentors purple, mentoring managers gold-red). The tokens live in `DesignSystem/Theme.swift`.
Built with the iOS 26 SDK, the system parts (tab bar, navigation bars, sheets, menus, switches) take on iOS 26's
Liquid Glass look by themselves.

## Roadmap

- **Push notifications.** The server sends Web Push and, for Android, Firebase Cloud Messaging (`/api/push/fcm`).
  iOS needs either APNs delivery in the backend or FCM for iOS (an Apple Developer account, an APNs key in the
  server's Firebase project and the Firebase SDK in the app). Until then notifications arrive by e-mail, and the app
  updates live while it is open. A background refresh with local notifications (like Android's 15-minute fallback)
  would work without server changes.
- English translation and a language choice in the settings
- Interactive image cropping (cover and profile picture), tables in AI answers
- TestFlight / App Store release (team id in `Package.swift`, privacy details) – see the handover

## Contributing

Issues and pull requests are welcome. Please describe the device, iOS version and the Agora server version for bugs.
New features should match the web app's behaviour, since all clients share the same backend rules. Changes are listed
in the [changelog](CHANGELOG.md).

## License

[GNU General Public License v3.0](LICENSE.md) – the same license as the Agora server and the Android app.

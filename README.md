# Agora for iOS

Native iOS and iPadOS client for [Agora](https://github.com/ricolehn/agora), built with SwiftUI.
It talks to the same backend as the web app (PWA) and the [Android app](https://github.com/ricolehn/agora-android),
follows the web app's design and uses native iOS controls where people expect them – tab bar, navigation,
forms in sheets, menus, confirmation dialogs, the photo picker and the share sheet.

**Status:** `v1.0.0-beta2` – feature complete for members, treasurers, event managers and mentoring.
Push notifications are not available on iOS yet (see [Roadmap](#roadmap)).

## Features

| Area | What the app does |
|---|---|
| **Start** | Greeting with date, overdue or soon-due membership fee (nothing while all is paid), open duty requests with *Accept* / *Decline*, *Als Nächstes* (the next five appointments and events as a swipeable row), your upcoming duties, unread mentoring messages |
| **Finances (members)** | Fee status with monthly rate, requests (payment, standing order, status change, expense with receipts), request status and rejection reasons, standing orders, payment history |
| **Finances (treasurers)** | Cash balance, open requests (approve / reject with reason), searchable and paged booking history with receipts, fee list (overdue / current), member details with payment booking, standing orders (end, also retroactively, or delete) and status changes, record donations and expenses |
| **Events** | *Termine* (appointments, multi-day events on every day) and *Events* (cover cards, highlights, past events), search, detail page with map link, Markdown description, registration / waiting list, attendees, duty roster (answer requests, assign people or groups, add and remove tasks), create / edit / delete incl. 16:9 cover, target groups and recurring appointments |
| **Mentoring** | Conversations with unread badges (mentees stay anonymous), chat with live polling, report / block / end / reopen, find and contact mentors anonymously, mentor application and profile, application review for mentoring managers |
| **AI support** | Streaming answers rendered as Markdown, collapsible reasoning, report an answer; only with permission and when AI is enabled on the server |
| **Settings** | Profile picture (cropped to 256×256 JPEG), registration code, notification preferences, colour scheme (system / light / dark), monthly fees (admins), password change, calendar subscription (Apple / Google Calendar), privacy policy, sign out, **account deletion** |

While the app is open it listens to the server's live updates (`/api/stream`, server-sent events) and refreshes the
affected data. It opens instantly with the last loaded data (kept on the device, excluded from backups, deleted on
sign-out) and refreshes in the background. Dark mode and VoiceOver labels are included.

## Requirements

- iOS / iPadOS **17** or later
- **Swift Playgrounds 4.4+** (iPad or Mac) or **Xcode 15+** (Mac)
- An Agora server reachable over **HTTPS** (the same address members open in the browser)

## Getting started

The app is a Swift Playgrounds app package (`Agora.swiftpm`).

**Swift Playgrounds (iPad or Mac)**
1. Download the repository (*Code → Download ZIP*) or clone it, and put `Agora.swiftpm` into iCloud Drive / Files.
2. Open `Agora.swiftpm` in Swift Playgrounds and press *Run*.

**Xcode (Mac)**
1. `git clone https://github.com/ricolehn/agora-ios.git`
2. Double-click `Agora.swiftpm`, choose a simulator or device and run.

On first launch the app asks for the server address, then for login or registration with the community's
six-digit registration code.

## Architecture

```
Agora.swiftpm
├── Package.swift            Swift Playgrounds app product (bundle id org.agora.app, iOS 17)
├── App/                     entry point, router (one navigation stack per tab), tab shell with header
├── Core/                    everything without UI
│   ├── Models/              API models with lenient decoding (numeric ids, German amounts "12,50", nulls)
│   ├── Networking/          APIClient (URLSession, Bearer token only to the own server, uploads, SSE and
│   │                        AI streams) and Repository (every endpoint the app uses)
│   ├── Store/               AppStore (@Observable: session, member data, live updates), Keychain session,
│   │                        on-device data cache
│   ├── Domain/              rules shared with web and Android: standing orders, status history, Termine
│   │                        filter, event badges, Markdown blocks, AI reasoning
│   └── Support/             JSONValue for untyped records, lenient decoder, date and money formats
├── DesignSystem/            colour tokens of the web app (light / dark), cards, buttons, pill tabs, avatars with
│                            role rings, authenticated image loading, toasts, Markdown view
└── Features/                Auth, Home, Finance, Events, Mentoring, AI, Settings
```

- Endpoints, payloads and write flows follow the backend in the Agora repository and are ported from the Android
  client. Standing orders and status history are written exactly like the web app (`applyStatusChangeToHistory`),
  so all clients produce identical records.
- Records the app changes as a whole (people, requests, donations, expenses) are read and written as `JSONValue`,
  so fields the app does not know are kept.
- Texts are German and used as localisation keys (`LocalizedStringKey` / `String(localized:)`); an English
  translation only needs a `Localizable.xcstrings`.

## Look & feel

The screens follow the web app's `assets/style.css`: cyan → emerald gradients, heavy headings, bordered cards,
pill tabs, uppercase section headers, calendar leaves for events and role rings around profile pictures
(members cyan, mentors purple, mentoring managers gold-red). The tokens live in `DesignSystem/Theme.swift`.

## Roadmap

- **Push notifications** via APNs (needs an Apple Developer account and APNs delivery in the backend).
  Until then notifications arrive by e-mail, and the app updates live while it is open.
- English translation, app icon, interactive image cropping
- TestFlight / App Store release (team id in `Package.swift`, privacy details)

## Contributing

Issues and pull requests are welcome. Please describe the device, iOS version and the Agora server version for bugs.
New features should match the web app's behaviour, since all clients share the same backend rules.

## License

[GNU General Public License v3.0](LICENSE.md) – the same license as the Agora server and the Android app.

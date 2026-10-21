# Working on Agora for iOS

Guide for AI coding agents and for people working with them. Read it before changing code; it is short on purpose.
Background, features and setup are in the [README](README.md), the open work in [docs/HANDOVER.md](docs/HANDOVER.md).

## The project

Agora is the app of a church or association: membership fees and the treasury, appointments and events with a duty
roster, anonymous mentoring, an AI assistant, a songbook and prayer requests. Every community runs its own server.
Three repositories belong together:

| Repository | What it is | Role for this app |
|---|---|---|
| [ricolehn/agora](https://github.com/ricolehn/agora) | Server (Node.js, PocketBase) and the web app (`index.html`, `assets/app.js`, `assets/finance.js`, `assets/songbook.js`, `assets/locales/de.json`) | **Source of truth**: endpoints, rules, texts |
| [ricolehn/agora-android](https://github.com/ricolehn/agora-android) | Native Android app (Kotlin, Jetpack Compose) | **Reference for native behaviour**; usually gets features first |
| ricolehn/agora-ios (this one) | Native iOS / iPadOS app (SwiftUI, a Swift Playgrounds app package) | Follows web and Android |

Releases carry codenames: web 3.1 *ORION*, web 3.2 *AIR TEMPLE*, Android 1.2 *AZULA*, iOS 1.0 *APPA*. A codename names
a feature level across the clients; the iOS release notes say which web and Android versions they match.

**Parity rule:** the iOS app behaves like the web app and Android – same rules, same records, same German wording –
and looks like the web app, with native iOS controls where people expect them (tab bar, navigation, sheets, menus,
confirmation dialogs, the share sheet). When the clients differ, the web app decides.

## Rules that are easy to break

1. **Records are written whole and like the web app.** People, requests, donations and expenses are read and written
   as `JSONValue`, so fields the app does not know survive. Never write a partial record or a new field the web app
   does not write. Write flows live in `Core/Networking/Repository.swift`, their pure rules in `Core/Domain`.
2. **Money.** Amounts people type go through `Amount.typed` (strict, refuses "1.500"); stored amounts through
   `JSONValue.amount` / `Amount.parse` (lenient, legacy formats). Approving a request goes through
   `Repository.approveRequest`: pending check, `RequestBookings` (booking id `req_<request id>`), roll-back on `409`.
   Person records change only through `mutatePerson` (optimistic locking with the record's version).
3. **German texts are the localisation keys.** Use `LocalizedStringKey` / `String(localized:)` with the German text
   and take the wording from the web app (`assets/locales/de.json`) or Android (`res/values-de/*.xml`), so all clients
   say the same. No English UI strings in code.
4. **`Core/Domain`, `Core/Models` and `Core/Support` import Foundation only** (no SwiftUI, UIKit, Security). The
   logic tests compile them on Linux as well.
5. **No third-party dependencies, iOS 17 minimum.** The package must keep building in Swift Playgrounds and Xcode.
   `Package.swift` is in the format Swift Playgrounds writes; change it only for versions, team id or capabilities.
6. **Security.** The token goes only to the own server (`APIClient.request`), secrets and account data live in the
   Keychain (`SessionStore`), cached data is excluded from backups and deleted on sign-out, web views that show
   server content run without JavaScript, plain `http` only to `localhost` in debug builds.
7. **Versions change only for a release** (see below), not in feature commits.

## Where things are

| Area | iOS (`Agora.swiftpm/`) | Android (`app/src/main/java/org/agora/app/`) |
|---|---|---|
| Entry, tabs, navigation | `App/AgoraApp.swift`, `App/MainShell.swift`, `App/Router.swift` | `MainActivity.kt`, `ui/AgoraApp.kt` |
| HTTP, SSE, uploads | `Core/Networking/APIClient.swift` | `data/remote/AgoraApi.kt` |
| Endpoints, write flows | `Core/Networking/Repository.swift`, `ExtrasRepository.swift` | `data/AgoraRepository.kt`, `data/SongbookApi.kt`, `PrayersApi.kt`, `ProgramApi.kt` |
| Session, cache, live updates | `Core/Store/AppStore.swift`, `Core/Store/SessionStore.swift` | `data/AppStore.kt`, `data/local/*` |
| Models | `Core/Models/Models.swift`, `ExtrasModels.swift` | `data/model/Models.kt`, `Serializers.kt` |
| Money rules | `Core/Domain/FinanceRules.swift`, `Core/Support/JSONValue.swift` (`Amount`) | `RequestBookings`, `StandingOrders`, `StatusHistory` in `data/AgoraRepository.kt`; `parseTypedAmount` in `Serializers.kt` |
| Event rules, links | `Core/Domain/EventRules.swift`, `Core/Domain/EventLinks.swift` | `ui/events/EventComponents.kt`, `util/EventLinks.kt` |
| Server logo | `DesignSystem/ServerLogo.swift`, `ServerLogoRules` in `Core/Domain/TextRules.swift` | `data/local/LogoStore.kt` |
| Design system | `DesignSystem/*` (tokens in `Theme.swift`, cards and buttons in `Components.swift`) | `ui/components/*`, `ui/theme/Theme.kt` |
| Screens | `Features/<Area>/*` | `ui/<area>/*` |
| Songbook logic | `Features/Songbook/SongbookLogic.swift` | `ui/songbook/SongbookLogic.kt` |
| Tests | `Tests/LogicTests/*` (run by `scripts/test-logic.sh`) | `app/src/test/*` |

## Porting a change from Android or the web

1. Read the change: `git show <commit>` in agora-android, and the web commit it refers to in agora. Android commit
   messages explain the behaviour in plain words; they are the best spec.
2. Find the iOS counterpart in the table above and read the surrounding code first.
3. Port the rules into `Core/Domain` (Foundation only) and add tests to `Tests/LogicTests` with the expected values of
   the web or Android tests (`tests/*.test.js` in agora, `app/src/test` in agora-android).
4. Build the screen with the design system (`card()`, `.agoraPrimary` / `.agoraSecondary` buttons, `PillTabs`,
   `IconTile`, `CapsLabel`, `StatusPill`, `ActionRunner` with toasts for actions, `FormSheet` + `FormAction` for forms).
5. Verify (next section), then update the feature table in the README and the [changelog](CHANGELOG.md).

## Verifying a change

- **Logic:** `./scripts/test-logic.sh` – on a Mac with Xcode, or on Linux with a Swift toolchain (6.x from
  [swift.org](https://www.swift.org/install/linux/); `String(localized:)` is shimmed there).
- **The app:** only Xcode compiles SwiftUI. Without a Mac, push to a branch: the *Build (iOS)* job of
  [the iOS workflow](.github/workflows/ios.yml) builds with the newest stable Xcode and uploads the build log as an
  artifact. Fix every error and every new warning.
- **Behaviour:** needs a simulator or a device. Say what was verified and how; "compiles on CI" is not "tested".

## Code style

- Swift 5 language mode (`swift-tools-version: 5.9`), SwiftUI with Observation (`@Observable`, `@Environment`),
  async/await; stores and view models are `@MainActor`.
- Follow the surrounding code: short English comments that say why, `///` on types and non-obvious functions, the
  lenient decoding helpers (`c.string("key")`, `c.models("key")`), lines up to about 140 characters.
- Show errors with `APIError.text(_:)` (server messages are German and shown as they are).

## Git and releases

- `develop` is the main line. Commit messages follow the history: `feat: …`, `fix: …`, `docs: …`, `ci: …`,
  `chore: …`, a subject that says what changed for the user, a body in plain words with the why.
- Version and build number are in `Agora.swiftpm/Package.swift` (`displayVersion`, `bundleVersion`). Raise the build
  number for every upload to App Store Connect; the version follows the release (`1.0.0` *APPA*).
- A release is tagged on GitHub (`v1.0.0`) and described in the changelog.

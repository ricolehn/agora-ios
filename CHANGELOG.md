# Changelog

All notable changes of the iOS app. Releases are tagged on GitHub; versions without a date are not released yet.
Codenames follow the Agora family: the web app (server) 3.1 *ORION* and 3.2 *AIR TEMPLE*, Android 1.2 *AZULA*,
iOS 1.0 *APPA*.

## 1.0.0 *APPA* – unreleased

On the level of the web app 3.2 *AIR TEMPLE* and the Android app 1.2.0 *AZULA*. Compiles on CI and passes the logic
tests; not yet tested on a device, see [docs/HANDOVER.md](docs/HANDOVER.md).

**Events**
- Share an event: the share icon right of the title and the organiser opens a sheet with the event's link (built like
  the web app builds it, so it opens the same page), *Link kopieren* and *Teilen …* (system share sheet). Those who may
  edit the event get the switch *Ohne Konto sichtbar*: people without an account open the link in the browser and sign
  up as guests (server 3.2 or newer; older servers send no switch and the sheet shows the members' link).
- The attendee list marks guests; editors see their e-mail address (tap to write) and age and can remove them.
- Date and place on the event page stay on one line and get smaller on narrow phones, then end with "…".
- New events no longer get the server's default duties as empty tasks (the web app and Android never added them).
- Event editor: the times shown are the times saved; the end time is optional and can be removed again.
- Members who may only create events get the editor directly from "+", without a menu with one entry.

**Finances**
- A request is booked only once: the app checks that it is still pending, bookings carry the request's id
  (`req_<id>`, the same as the web app and Android), and an approval that loses against a rejection made at the same
  moment takes its booking back. The treasurer who was too late sees "Diese Anfrage wurde bereits entschieden."
- A request whose amount cannot be read is no longer booked as 0 €.
- Typed amounts are read strictly, like the web app: "1.500" or "1,500" is not guessed (it was booked as 1,50 €), the
  field turns red and says how to write it. Amount fields keep only digits, "," and ".".
- Saving the monthly fees can no longer wipe the settings when the server could not be read; empty fields keep their
  rate, missing rates are no longer written as 0.
- Expense requests without receipts no longer count as "receipt attached"; receipts are pictures only (the server
  refuses other files).
- Request tiles also show for accounts without a member record; status pickers preselect a known status.
- The fee list keeps the history of an opened member after a refresh instead of a spinner without end.
- Free text (notes, descriptions, names) is saved trimmed.

**App**
- The church logo is kept on the device per server and shows at once on start (no flash of the Agora knot); the server
  is checked at most once a minute, the server's default logo brings back the bundled knot. Logos are rendered without
  JavaScript.
- The device's time zone is reported to the server, so duty reminders (3 hours before) come at the right local time.
- Live updates start right after login (they only started after the app had been in the background once).
- Refreshes always deliver data read after the action that asked for them (a refresh asked for while another one ran
  could be lost).
- After logout nothing of the previous account is written back to the device; the cached account (e-mail,
  permissions, calendar key) moved from UserDefaults (part of device backups) to the Keychain, this device only.
- Pictures that failed only because the device was offline are tried again.
- The mentoring chat polls only while the app is in the foreground; its menu shows once the conversation is loaded.
- Plain `http://` to `localhost` only in debug builds; a proxy's HTTP 503 reads as "server not reachable".
- Transparent profile pictures get a white instead of a black background.
- Texts: song editor key field "Tonart", the duty reminder in the notification settings, the account deletion text
  lists what the server deletes.

**Project**
- Logic tests (`scripts/test-logic.sh`, `Tests/LogicTests`) for macOS and Linux; GitHub Actions builds the app and runs
  them on every push.
- README, handover document and a guide for AI coding agents (`AGENTS.md`).

## *ORION* – 2026-10-14 (not released separately)

Level of the web app 3.1 *ORION* and the Android app 1.1.0: Extras tab with AI support, songbook and prayer requests;
one plan per event (duty roster and order of service); the "Stone & Lagoon" look; new Agora logo (celtic knot) as app
icon and app mark.

## 1.0.0-beta3 – 2026-10-08

Finance requests on the start page and in the treasury with a detail sheet, financial report as PDF, booking history
with avatars, Termine month calendar on iPad, settings as sub-pages, notifications per channel and kind.

## 1.0.0-beta2 – 2026-10-03

Start page and event cards in the web app's beta16 design, iPad layouts (regular width), editor improvements.

## 1.0.0-beta1 – 2026-10-02

First version: native SwiftUI client (iOS / iPadOS 17) as a Swift Playgrounds app package with server, login and
registration, start page, finances for members and treasurers, Termine & Events, mentoring, AI support and settings
including account deletion.

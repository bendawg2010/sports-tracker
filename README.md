# Sports Tracker

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-blue)](https://www.apple.com/macos)
[![Open Source](https://img.shields.io/badge/Open-Source-purple)](https://github.com/bendawg2010/sports-tracker)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange)](https://swift.org)

A native macOS menu bar app that tracks live scores from 22+ sports leagues — NFL, NBA, MLB, NHL, Premier League, F1, PGA, UFC, tennis, college and more — with hand-drawn fields, courts, and rinks. Lives in your menu bar, gets out of your way, never asks for an account.

![demo](docs/demo.gif)

---

## Install in 30 seconds

```bash
curl -fsSL https://raw.githubusercontent.com/bendawg2010/sports-tracker/main/install.sh | bash
```

Then look for the trophy in your menu bar.

Prefer to click instead of type? See [INSTALL.md](INSTALL.md) for manual install, the Gatekeeper warning explainer, and build-from-source instructions.

---

## Features

- 🏟 **Hand-drawn widgets** — Every sport gets its own field, court, rink, or octagon, drawn in SwiftUI. Live action layered on top.
- 📊 **22+ leagues** — NFL, NBA, MLB, NHL, NCAA (men's & women's), Premier League, La Liga, Bundesliga, Serie A, Ligue 1, MLS, UCL, PGA, ATP, WTA, F1, NASCAR, UFC and more.
- 📌 **Floating scoreboards** — Pin any live game as a 280×180 widget that floats above every app.
- 🎯 **Smart ticker** — Subtle scrolling ticker across the top of your screen. Close games glow. Upsets get badges.
- 🏆 **Tournament mode** — March Madness brackets, region/round grouping, Cinderella tracking, chaos rankings.
- ⚡ **Live play-by-play** — Dedicated Plays tab for every sport, with color-coded scoring events.
- 🔔 **Smart notifications** — Get alerted on close games, upsets, and your favorite teams.
- 🎾 **Tennis point scoring** — Bring your own free api-tennis.com key for live 15/30/40/Ad scoring.
- 🪟 **Multiview** — Watch up to 4 games tiled at once via embedded ESPN/league players.
- 🧩 **Desktop widgets** — Real WidgetKit widgets for your desktop and Notification Center.

---

## Why it's free and open source

Sports apps are mostly hostile. They harvest your data, push notifications you didn't ask for, paywall basic stats, and bury everything under ads. I wanted a sports app that I'd actually want on my own machine, so I built one and put the source on GitHub.

It's free because it costs nothing to run — no servers, no accounts, no analytics. It's open source because I think the only way to trust software on your own computer is to be able to read it.

---

## How to support

- **⭐ Star the repo** — costs you nothing, makes my day.
- **💸 Donate** — there's a tip jar inside the app's preferences. Pay-what-you-want, totally optional.
- **🐛 File issues** — bug reports and feature requests are gold.
- **📣 Tell a friend** — word of mouth is everything for indie apps.

---

## Privacy promise

**Zero tracking. No accounts. Direct ESPN.**

- No analytics SDK. No telemetry. No phone-home.
- No account, ever — there's nothing to sign up for.
- Data comes straight from ESPN's public API. Nothing about you ever leaves your Mac.
- Your favorites, settings, and pinned games live in `defaults` on your machine and nowhere else.

If you don't believe me, read the source. The networking layer is one file.

---

## Build from source

```bash
git clone https://github.com/bendawg2010/sports-tracker.git
cd sports-tracker
open SportsTracker.xcodeproj
```

Then in Xcode:

1. Pick the `SportsTracker` scheme.
2. Set your free personal Team in **Signing & Capabilities** for both the main target and the widget extension.
3. Cmd+R to run.

Requirements: **macOS 14+**, **Xcode 15+**. No third-party dependencies — pure Apple frameworks.

---

## Architecture

- **Swift 6 + SwiftUI** with a thin AppKit layer for menu bar / floating windows
- **WidgetKit** for desktop and Notification Center widgets
- **WebKit** for embedded game viewing
- **No third-party packages** — everything is Apple frameworks

For the full feature breakdown and per-sport widget designs, see [`AppStoreDescription.md`](AppStoreDescription.md).

---

## Contributing

Issues and PRs welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, ship it. Just don't claim you wrote it.

Sports data provided by ESPN. Not affiliated with the NCAA, NFL, NBA, MLB, NHL, MLS, PGA Tour, ATP, WTA, FIA, UFC, or any other league or team.

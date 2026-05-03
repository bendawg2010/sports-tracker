# Install Sports Tracker

A free, open-source menu bar app for live sports scores on macOS.

> **TL;DR** — Run one command, look for the trophy in your menu bar. Done.

---

## Quick Install (30 seconds)

Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/bendawg2010/sports-tracker/main/install.sh | bash
```

That's it. The script downloads the latest release, installs it to `/Applications`, and removes the macOS quarantine flag so the app just opens. No clicking through warnings, no Privacy & Security panel.

If you want to read the script before running it (you should!), here it is:
https://github.com/bendawg2010/sports-tracker/blob/main/install.sh

---

## Manual Install

If you'd rather click than type:

1. Go to the [Releases page](https://github.com/bendawg2010/sports-tracker/releases/latest).
2. Download `SportsTracker.app.zip`.
3. Double-click the zip to unzip it.
4. Drag `SportsTracker.app` into your `/Applications` folder.
5. Open it.

When you double-click the app for the first time, macOS will probably stop you with a warning. Read the next section.

---

## Warning — This Is Not A Virus

If you see this message:

> **"Sports Tracker" can't be opened because Apple cannot check it for malicious software.**

**Take a breath. This is NOT a virus. This is open-source code you can read.**

### Why does macOS say that?

Apple charges developers **$100 per year** to join the Apple Developer Program. Once you pay, Apple lets you sign your apps with a certificate, and macOS will open them without scary warnings.

Sports Tracker is a free, open-source hobby project. The author hasn't paid Apple's $100/year toll, so macOS doesn't recognize the app's signature and shows the warning. That's the entire story. The warning is about **paperwork**, not about the code.

You can verify this for yourself:
- The complete source is on GitHub: https://github.com/bendawg2010/sports-tracker
- It uses only Apple's own frameworks (SwiftUI, AppKit, WidgetKit, WebKit) — no third-party libraries, no analytics SDKs, no telemetry.
- It talks to ESPN's public API and nothing else. No accounts, no servers, no tracking.
- You can build it from source yourself in Xcode — see below.

### How to open it anyway (Method 1: right-click)

1. Open Finder and go to `/Applications`.
2. Find `SportsTracker.app`.
3. **Right-click** (or Control-click) the app.
4. Choose **Open** from the menu.
5. A dialog appears with the same warning, but now there's an **"Open"** button. Click it.
6. From now on, you can double-click the app like normal.

### How to open it anyway (Method 2: System Settings)

If the right-click trick doesn't show an Open button on your version of macOS:

1. Try to open the app normally — let macOS show the warning, then click **Done**.
2. Open **System Settings** (the gear icon).
3. Click **Privacy & Security** in the sidebar.
4. Scroll down to the **Security** section.
5. You'll see a message: *"Sports Tracker was blocked from use because it is not from an identified developer."*
6. Click **Open Anyway** next to it.
7. macOS asks one more time. Click **Open**.

You only have to do this once. After that, the app launches normally.

### Why the install script avoids all of this

The `install.sh` script removes a hidden file attribute called `com.apple.quarantine` that macOS attaches to anything downloaded from the internet. With that attribute gone, Gatekeeper doesn't show the warning at all. It's the same trick Apple uses for apps installed by package managers like Homebrew. It's not a hack — it's a documented `xattr` flag.

---

## Don't Trust Me? Read The Source.

This is the whole point of open source. You don't have to take my word for it.

- **Full source code:** https://github.com/bendawg2010/sports-tracker
- **The install script:** https://github.com/bendawg2010/sports-tracker/blob/main/install.sh
- **The release artifacts:** https://github.com/bendawg2010/sports-tracker/releases

Every release is built from a tagged commit. You can diff the source between releases, audit the network calls, and convince yourself that nothing fishy is happening.

---

## Build From Source (For The Truly Paranoid)

If you'd rather not trust a binary at all, build it yourself. It takes about a minute.

**Requirements:**
- macOS 14 (Sonoma) or later
- Xcode 15 or later (free from the App Store)

**Steps:**

```bash
git clone https://github.com/bendawg2010/sports-tracker.git
cd sports-tracker
open SportsTracker.xcodeproj
```

In Xcode:

1. Select the `SportsTracker` scheme in the toolbar.
2. Go to **Signing & Capabilities** for both the main target and the widget extension. Pick your personal Team (your free Apple ID works fine).
3. Press **Cmd+R** to build and run.

When the app launches, it'll be signed with your own Apple ID, so macOS won't complain. The built `.app` lives in `~/Library/Developer/Xcode/DerivedData/` — you can copy it to `/Applications` if you want it there permanently.

---

## Uninstall

```bash
rm -rf /Applications/SportsTracker.app
defaults delete com.bendawg2010.sportstracker 2>/dev/null
```

That's it. Sports Tracker stores nothing outside its own preferences file. No daemons, no launch agents, no leftover login items.

---

## Questions

Open an issue: https://github.com/bendawg2010/sports-tracker/issues

# App Store Connect Metadata

Reference document for App Store submission. Copy values into App Store
Connect manually — this file is not consumed by any submission tool.

## App Information

| Field               | Value                                    |
| ------------------- | ---------------------------------------- |
| App Name            | Sports Tracker                           |
| Subtitle (30 chars) | Live scores for 22+ sports               |
| Bundle Display Name | Sports Tracker                           |
| Primary Category    | Sports                                   |
| Secondary Category  | News                                     |
| Age Rating          | 4+                                       |
| Copyright           | © 2026 Sports Tracker                    |

Subtitle character count check: `Live scores for 22+ sports` = 26 characters
(well under the 30-character limit).

## Keywords

Comma-separated, 100-character maximum. Do not include spaces after commas
(they count against the limit).

```
live scores,sports,nfl,nba,mlb,nhl,soccer,f1,tennis,golf,ufc,ncaa,widgets,menu bar,tracker
```

Character count: 90 / 100.

## Promotional Text (170 chars)

Shown above the description on the product page. Can be updated without
submitting a new build.

```
Follow every game across the NFL, NBA, MLB, NHL, soccer, F1, tennis, golf, UFC and more — right from your menu bar with live widgets.
```

Character count: 135 / 170.

## URLs

| Field              | Value                                        |
| ------------------ | -------------------------------------------- |
| Support URL        | https://example.com/sports-tracker/support   |
| Marketing URL      | https://example.com/sports-tracker           |
| Privacy Policy URL | https://example.com/sports-tracker/privacy   |

Replace the placeholder URLs before submission. A Privacy Policy URL is
required by App Store Connect even when the app collects no data.

## Version

| Field                 | Value |
| --------------------- | ----- |
| Version (Marketing)   | 1.0.0 |
| Build Number          | 1     |
| Minimum macOS Version | 14.0  |

## Description (draft)

Sports Tracker lives in your menu bar and keeps you on top of every game
that matters. Follow live scores, play-by-play, and player stats across
the NFL, NBA, MLB, NHL, NCAA football and basketball, MLS, the Premier
League and other top soccer leagues, F1, tennis, golf, and UFC — without
leaving what you're doing.

Pick the sports you care about, pin the teams you follow, and glance at
the menu bar to see the score. Open a richer window for drive charts,
box scores, standings, and upcoming games. Add home-screen widgets for
the leagues, teams, and drivers you want to watch most.

Features
- Live scores and play-by-play for 22+ sports
- Menu bar score for your pinned team
- Widgets for scores, standings, brackets, and player stats
- Works offline for recent data
- No account, no ads, no tracking

Sports Tracker uses public data from ESPN. It is not affiliated with or
endorsed by the NFL, NBA, MLB, NHL, NCAA, FIA, ATP, PGA Tour, UFC, or any
other league or organization.

## Notes for Reviewer

- The app is a menu-bar-only utility (`LSUIElement` is true); there is
  no Dock icon or main window on launch.
- All sports data is fetched from public ESPN endpoints. No user account
  is required and no personal data is collected or transmitted.
- The app requests no sensitive entitlements beyond network access.
- Apple Events usage (`NSAppleEventsUsageDescription`) is declared solely
  to open stream links in the user's default browser.

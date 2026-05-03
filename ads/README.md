# Sports Tracker — Promotional Video Ads

Remotion project that produces vertical (1080x1920) promotional video ads for **Sports Tracker**, a free open-source macOS menu bar app that tracks 22+ live sports.

## Compositions

| ID                | Duration | Format     | Use                                 |
| ----------------- | -------- | ---------- | ----------------------------------- |
| `AdSportsTracker` | 30 s     | 1080x1920  | TikTok / Reels / YouTube Shorts     |
| `AdShortFormat`   | 15 s     | 1080x1920  | IG Reels / paid social bumpers      |

## Storyboard (30 s main ad)

| Time     | Scene                | Description                                                       |
| -------- | -------------------- | ----------------------------------------------------------------- |
| 0 - 3 s  | Hook                 | "Stop tabbing to ESPN" — period scales dramatically               |
| 3 - 6 s  | Problem              | Cycles through 3 stylized problem boxes (alt-tab, new tab, ESPN)  |
| 6 - 9 s  | Solution reveal      | Zoom in on Mac menu bar with trophy + scrolling live ticker       |
| 9 - 14 s | Sport carousel       | 3x3 grid of sport fields appearing one cell at a time             |
| 14 - 19s | Live drawings        | Football w/ drive arrow, basketball w/ shots, baseball w/ runners |
| 19 - 24s | Pin feature          | Floating widget animates from center to corner ("Pin any game")   |
| 24 - 28s | Open source moment   | "Free. Open source. Forever." + GitHub icon                       |
| 28 - 30s | CTA                  | "Sports Tracker", URL, download button, trophy icon               |

## Install

```bash
cd ads
npm install
```

## Preview in Remotion Studio

```bash
npm run start
```

This opens the Remotion Studio at `http://localhost:3000` where you can scrub through both compositions interactively.

## Render

### Main 30-second ad

```bash
npx remotion render AdSportsTracker out/sports-tracker-ad.mp4
```

or:

```bash
npm run build
```

### 15-second short format

```bash
npx remotion render AdShortFormat out/sports-tracker-ad-15s.mp4
```

or:

```bash
npm run build:short
```

### Render with custom output

```bash
npx remotion render AdSportsTracker out/my-cut.mp4 --crf 16
```

## Project structure

```
ads/
├── package.json
├── remotion.config.ts        # codec, CRF, concurrency
├── tsconfig.json             # TS strict mode, ESM
├── README.md
└── src/
    ├── index.ts              # registerRoot
    ├── Root.tsx              # Composition registry (both ads)
    ├── AdSportsTracker.tsx   # 30 s main ad
    ├── AdShortFormat.tsx     # 15 s short ad
    └── components/
        ├── SportField.tsx    # 9 inline-SVG sport field/court drawings
        └── MenuBarMockup.tsx # animated macOS menu bar w/ live ticker
```

## Visual style tokens

| Token             | Value                       |
| ----------------- | --------------------------- |
| Background        | `#0A0A0C`                   |
| Gold accent       | `#FFB81C`                   |
| Text              | `#FFFFFF`                   |
| Font stack        | `Inter, -apple-system, ...` |
| Heading size      | 72 - 200 px                 |

## Sports rendered

`football`, `basketball`, `baseball`, `hockey`, `soccer`, `tennis`, `golf`, `f1`, `ufc` — each with authentic field/court colors and inline SVG line markings (yard lines, three-point arcs, diamond bases, blue lines, octagon, etc.).

## Notes

- Uses Remotion v4 syntax — `Composition` / `Sequence` / `AbsoluteFill` / `spring()` / `interpolate()` / `useCurrentFrame()`.
- TypeScript strict mode + ESM modules.
- All animations are deterministic and frame-based — no random or time-based values.
- The ticker scrolls via `useCurrentFrame()` in `MenuBarMockup.tsx`.
- Audio is intentionally omitted so you can drop in your own music track and re-render with `--audio-codec aac --audio-file path/to/music.mp3` (or layer it in your DAW/editor).

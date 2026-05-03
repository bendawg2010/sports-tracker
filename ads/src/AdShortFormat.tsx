import React from "react";
import {
  AbsoluteFill,
  Sequence,
  spring,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  Easing,
} from "remotion";
import { SportField, type Sport, SPORT_LABELS } from "./components/SportField";
import { MenuBarMockup, TrophyIcon } from "./components/MenuBarMockup";

const FONT_STACK = "Inter, -apple-system, BlinkMacSystemFont, sans-serif";
const BG = "#0A0A0C";
const GOLD = "#FFB81C";

const SHORT_GRID: Sport[] = [
  "football",
  "basketball",
  "baseball",
  "hockey",
  "soccer",
  "tennis",
];

/* --------- Scene 1: Punchy hook (0-3s, frames 0-90) --------- */
const ShortHook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const opacity = interpolate(frame, [4, 18], [0, 1], {
    extrapolateRight: "clamp",
  });
  const scale = spring({
    frame: frame - 4,
    fps,
    config: { damping: 12, stiffness: 90 },
  });

  return (
    <AbsoluteFill
      style={{
        background: BG,
        justifyContent: "center",
        alignItems: "center",
        padding: 80,
      }}
    >
      <div
        style={{
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 150,
          fontWeight: 900,
          letterSpacing: -3,
          textAlign: "center",
          lineHeight: 1.0,
          opacity,
          transform: `scale(${scale})`,
        }}
      >
        Live scores
        <br />
        <span style={{ color: GOLD }}>in your menu bar.</span>
      </div>
    </AbsoluteFill>
  );
};

/* --------- Scene 2: Menu bar reveal (3-6s, frames 90-180) --------- */
const ShortMenuBar: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const scale = spring({
    frame,
    fps,
    config: { damping: 16, stiffness: 70 },
  });

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(ellipse at center, #1A1A22, ${BG})`,
        justifyContent: "center",
        alignItems: "center",
        padding: 30,
      }}
    >
      <div
        style={{
          transform: `scale(${0.7 + scale * 0.4})`,
        }}
      >
        <MenuBarMockup width={1000} scrollSpeed={4} />
      </div>
    </AbsoluteFill>
  );
};

/* --------- Scene 3: Sport grid (6-10s, frames 180-300) --------- */
const ShortGrid: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const cellWidth = 300;
  const cellHeight = 200;
  const gap = 24;

  return (
    <AbsoluteFill
      style={{
        background: BG,
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        gap: 40,
        padding: 60,
      }}
    >
      <div
        style={{
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 84,
          fontWeight: 900,
          letterSpacing: -2,
          textAlign: "center",
        }}
      >
        <span style={{ color: GOLD }}>22+</span> sports.
      </div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: `repeat(2, ${cellWidth}px)`,
          gap,
        }}
      >
        {SHORT_GRID.map((sport, i) => {
          const cellStart = i * 8;
          const cellSpring = spring({
            frame: frame - cellStart,
            fps,
            config: { damping: 12 },
          });
          const op = interpolate(frame, [cellStart, cellStart + 6], [0, 1], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          });
          return (
            <div key={sport} style={{ opacity: op, transform: `scale(${cellSpring})` }}>
              <SportField sport={sport} width={cellWidth} height={cellHeight} />
              <div
                style={{
                  color: "white",
                  fontFamily: FONT_STACK,
                  fontSize: 20,
                  fontWeight: 800,
                  textAlign: "center",
                  letterSpacing: 1.5,
                  marginTop: 10,
                }}
              >
                {SPORT_LABELS[sport]}
              </div>
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

/* --------- Scene 4: Open source line (10-12s, frames 300-360) --------- */
const ShortOpenSource: React.FC = () => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [0, 12], [0, 1], {
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill
      style={{
        background: "#000",
        justifyContent: "center",
        alignItems: "center",
        opacity,
      }}
    >
      <div
        style={{
          color: GOLD,
          fontFamily: FONT_STACK,
          fontSize: 110,
          fontWeight: 900,
          letterSpacing: -2,
          textAlign: "center",
          lineHeight: 1.05,
        }}
      >
        Free.
        <br />
        Open source.
      </div>
    </AbsoluteFill>
  );
};

/* --------- Scene 5: CTA (12-15s, frames 360-450) --------- */
const ShortCta: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const titleScale = spring({
    frame,
    fps,
    config: { damping: 14, stiffness: 80 },
  });
  const urlOpacity = interpolate(frame, [10, 22], [0, 1], {
    extrapolateRight: "clamp",
  });
  const buttonOpacity = interpolate(frame, [22, 36], [0, 1], {
    extrapolateRight: "clamp",
  });
  const buttonScale = spring({
    frame: frame - 22,
    fps,
    config: { damping: 12 },
  });

  return (
    <AbsoluteFill
      style={{
        background: BG,
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        gap: 40,
        padding: 60,
      }}
    >
      <div style={{ transform: `scale(${titleScale})` }}>
        <TrophyIcon size={140} color={GOLD} />
      </div>
      <div
        style={{
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 110,
          fontWeight: 900,
          letterSpacing: -2,
          textAlign: "center",
          lineHeight: 1.0,
          transform: `scale(${titleScale})`,
        }}
      >
        Sports
        <br />
        <span style={{ color: GOLD }}>Tracker</span>
      </div>
      <div
        style={{
          color: "rgba(255,255,255,0.85)",
          fontFamily: FONT_STACK,
          fontSize: 50,
          fontWeight: 600,
          opacity: urlOpacity,
        }}
      >
        sportstracker.app
      </div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 14,
          background: GOLD,
          color: BG,
          padding: "18px 36px",
          borderRadius: 16,
          fontFamily: FONT_STACK,
          fontSize: 40,
          fontWeight: 900,
          opacity: buttonOpacity,
          transform: `scale(${buttonScale})`,
        }}
      >
        <svg width={36} height={36} viewBox="0 0 24 24" fill="none">
          <path
            d="M12 3v12m0 0l-5-5m5 5l5-5M5 21h14"
            stroke={BG}
            strokeWidth={3}
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
        Download free
      </div>
    </AbsoluteFill>
  );
};

export const AdShortFormat: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: BG }}>
      <Sequence from={0} durationInFrames={90}>
        <ShortHook />
      </Sequence>
      <Sequence from={90} durationInFrames={90}>
        <ShortMenuBar />
      </Sequence>
      <Sequence from={180} durationInFrames={120}>
        <ShortGrid />
      </Sequence>
      <Sequence from={300} durationInFrames={60}>
        <ShortOpenSource />
      </Sequence>
      <Sequence from={360} durationInFrames={90}>
        <ShortCta />
      </Sequence>
    </AbsoluteFill>
  );
};

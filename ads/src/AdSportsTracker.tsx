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

const SPORTS_GRID: Sport[] = [
  "football",
  "basketball",
  "baseball",
  "hockey",
  "soccer",
  "tennis",
  "golf",
  "f1",
  "ufc",
];

// Fade helper
const useFadeIn = (start: number, duration = 8) => {
  const frame = useCurrentFrame();
  return interpolate(frame, [start, start + duration], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
};

/* -------------------- Scene 1: Hook (0-3s, frames 0-90) -------------------- */
const SceneHook: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const textOpacity = interpolate(frame, [10, 30], [0, 1], {
    extrapolateRight: "clamp",
  });
  const textY = interpolate(frame, [10, 40], [40, 0], {
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  // Scale the period dramatically around frame 60
  const periodScale = spring({
    frame: frame - 55,
    fps,
    config: { damping: 8, stiffness: 80, mass: 0.6 },
  });

  return (
    <AbsoluteFill
      style={{
        background: BG,
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        padding: 80,
      }}
    >
      <div
        style={{
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 130,
          fontWeight: 900,
          letterSpacing: -3,
          textAlign: "center",
          lineHeight: 1.05,
          opacity: textOpacity,
          transform: `translateY(${textY}px)`,
        }}
      >
        Stop tabbing
        <br />
        to ESPN
        <span
          style={{
            display: "inline-block",
            transform: `scale(${1 + periodScale * 4})`,
            color: GOLD,
            transformOrigin: "left bottom",
          }}
        >
          .
        </span>
      </div>
    </AbsoluteFill>
  );
};

/* ----------------- Scene 2: Problem (3-6s, frames 90-180) ----------------- */
const ProblemBox: React.FC<{
  label: string;
  emoji: string;
  active: boolean;
  x: number;
  y: number;
}> = ({ label, emoji, active, x, y }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const scale = spring({ frame: frame - 2, fps, config: { damping: 12 } });

  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: 480,
        height: 320,
        background: active ? "#1F1F23" : "#141418",
        border: `4px solid ${active ? GOLD : "#2A2A30"}`,
        borderRadius: 24,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: 20,
        transform: `scale(${active ? 1 : 0.92}) scale(${scale})`,
        opacity: active ? 1 : 0.5,
        transition: "all 0.3s",
      }}
    >
      <div style={{ fontSize: 140 }}>{emoji}</div>
      <div
        style={{
          color: active ? "white" : "rgba(255,255,255,0.6)",
          fontFamily: FONT_STACK,
          fontSize: 36,
          fontWeight: 800,
          textAlign: "center",
          padding: "0 20px",
        }}
      >
        {label}
      </div>
    </div>
  );
};

const SceneProblem: React.FC = () => {
  const frame = useCurrentFrame();
  // Cycle through 3 boxes, ~30 frames each
  const activeIdx = Math.min(2, Math.floor(frame / 30));

  return (
    <AbsoluteFill
      style={{
        background: BG,
        padding: 60,
      }}
    >
      <div
        style={{
          color: "rgba(255,255,255,0.7)",
          fontFamily: FONT_STACK,
          fontSize: 44,
          fontWeight: 700,
          textAlign: "center",
          marginTop: 80,
          marginBottom: 50,
        }}
      >
        The old way:
      </div>
      <div style={{ position: "relative", flex: 1 }}>
        <ProblemBox
          label="Alt-tab to browser"
          emoji="🪟"
          active={activeIdx === 0}
          x={300}
          y={120}
        />
        <ProblemBox
          label="Open new tab"
          emoji="🔍"
          active={activeIdx === 1}
          x={300}
          y={500}
        />
        <ProblemBox
          label="Launch ESPN app"
          emoji="📱"
          active={activeIdx === 2}
          x={300}
          y={880}
        />
      </div>
    </AbsoluteFill>
  );
};

/* --------------- Scene 3: Solution Reveal (6-9s, frames 180-270) --------- */
const SceneSolution: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const zoom = spring({
    frame,
    fps,
    config: { damping: 18, stiffness: 60, mass: 1 },
  });

  // Title appears slightly later
  const titleScale = spring({
    frame: frame - 30,
    fps,
    config: { damping: 12 },
  });
  const titleOpacity = interpolate(frame, [30, 50], [0, 1], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(ellipse at center, #1A1A20 0%, ${BG} 70%)`,
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        padding: 40,
      }}
    >
      {/* Faux desktop hint behind */}
      <AbsoluteFill style={{ opacity: 0.15 }}>
        <div
          style={{
            position: "absolute",
            top: 200,
            left: 100,
            right: 100,
            bottom: 200,
            background:
              "linear-gradient(135deg, rgba(255,184,28,0.05), rgba(0,0,0,0))",
            borderRadius: 32,
          }}
        />
      </AbsoluteFill>

      <div
        style={{
          transform: `scale(${0.6 + zoom * 0.4})`,
          marginBottom: 60,
        }}
      >
        <MenuBarMockup width={960} scrollSpeed={3} />
      </div>

      <div
        style={{
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 110,
          fontWeight: 900,
          letterSpacing: -2,
          textAlign: "center",
          opacity: titleOpacity,
          transform: `scale(${titleScale})`,
        }}
      >
        Sports
        <br />
        <span style={{ color: GOLD }}>Tracker.</span>
      </div>
    </AbsoluteFill>
  );
};

/* ---------------- Scene 4: Sport Carousel (9-14s, frames 270-420) -------- */
const SceneCarousel: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const cellWidth = 300;
  const cellHeight = 200;
  const gap = 24;
  const totalWidth = cellWidth * 3 + gap * 2;

  const cellAppearStartFrames = 8;
  const cellInterval = 12; // 250ms = ~7.5 frames -> bumped to 12 for visual rhythm

  return (
    <AbsoluteFill
      style={{
        background: BG,
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        gap: 50,
      }}
    >
      <div
        style={{
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 72,
          fontWeight: 900,
          letterSpacing: -1,
          textAlign: "center",
          lineHeight: 1.1,
        }}
      >
        <span style={{ color: GOLD }}>22+</span> sports.
        <br />
        One menu bar.
      </div>
      <div
        style={{
          width: totalWidth,
          display: "grid",
          gridTemplateColumns: `repeat(3, ${cellWidth}px)`,
          gap,
        }}
      >
        {SPORTS_GRID.map((sport, i) => {
          const cellStart = cellAppearStartFrames + i * cellInterval;
          const cellSpring = spring({
            frame: frame - cellStart,
            fps,
            config: { damping: 14, stiffness: 90 },
          });
          const cellOpacity = interpolate(
            frame,
            [cellStart, cellStart + 8],
            [0, 1],
            { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
          );
          return (
            <div
              key={sport}
              style={{
                opacity: cellOpacity,
                transform: `scale(${cellSpring})`,
                transformOrigin: "center",
              }}
            >
              <SportField sport={sport} width={cellWidth} height={cellHeight} />
              <div
                style={{
                  color: "white",
                  fontFamily: FONT_STACK,
                  fontSize: 22,
                  fontWeight: 800,
                  textAlign: "center",
                  letterSpacing: 1.5,
                  marginTop: 12,
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

/* -------------- Scene 5: Live Drawings (14-19s, frames 420-570) ---------- */
const LiveDrawingPanel: React.FC<{
  sport: Sport;
  overlayText: string;
  startFrame: number;
  durationFrames: number;
  showShots?: boolean;
  showRunners?: boolean;
  showDriveArrow?: boolean;
}> = ({ sport, overlayText, startFrame, durationFrames, showShots, showRunners, showDriveArrow }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const localFrame = frame - startFrame;
  if (localFrame < 0 || localFrame > durationFrames) return null;

  const enterScale = spring({
    frame: localFrame,
    fps,
    config: { damping: 14, stiffness: 80 },
  });
  const exitOpacity = interpolate(
    localFrame,
    [durationFrames - 8, durationFrames],
    [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill
      style={{
        background: BG,
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        gap: 40,
        opacity: exitOpacity,
      }}
    >
      <div
        style={{
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 56,
          fontWeight: 800,
          letterSpacing: -1,
        }}
      >
        Live game view
      </div>
      <div
        style={{
          transform: `scale(${enterScale * 1.6})`,
          transformOrigin: "center",
        }}
      >
        <SportField
          sport={sport}
          width={760}
          height={475}
          showOverlay
          overlayText={overlayText}
          showShots={showShots}
          showRunners={showRunners}
          showDriveArrow={showDriveArrow}
        />
      </div>
    </AbsoluteFill>
  );
};

const SceneLiveDrawings: React.FC = () => {
  // 5 seconds = 150 frames. Three panels of ~50 frames each.
  return (
    <>
      <LiveDrawingPanel
        sport="football"
        overlayText="1ST & GOAL"
        startFrame={0}
        durationFrames={50}
        showDriveArrow
      />
      <LiveDrawingPanel
        sport="basketball"
        overlayText="DUKE 78  UNC 75"
        startFrame={50}
        durationFrames={50}
        showShots
      />
      <LiveDrawingPanel
        sport="baseball"
        overlayText="BASES LOADED"
        startFrame={100}
        durationFrames={50}
        showRunners
      />
    </>
  );
};

/* ----------------- Scene 6: Pin Feature (19-24s, frames 570-720) --------- */
const ScenePinFeature: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phase 1 (0-30): widget appears centered
  // Phase 2 (30-90): widget shrinks and moves to corner (pin)
  // Phase 3 (90-150): pin icon shows, label fades in

  const widgetScale = spring({
    frame,
    fps,
    config: { damping: 14, stiffness: 70 },
  });

  const pinProgress = interpolate(frame, [40, 90], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
    easing: Easing.bezier(0.65, 0, 0.35, 1),
  });

  const widgetX = interpolate(pinProgress, [0, 1], [0, 200]);
  const widgetY = interpolate(pinProgress, [0, 1], [0, 480]);
  const widgetSize = interpolate(pinProgress, [0, 1], [1, 0.5]);

  const pinIconOpacity = interpolate(frame, [80, 100], [0, 1], {
    extrapolateRight: "clamp",
  });
  const labelOpacity = interpolate(frame, [95, 120], [0, 1], {
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(ellipse at top, #1F1F26 0%, ${BG} 70%)`,
        padding: 60,
      }}
    >
      {/* Faux wallpaper hint */}
      <AbsoluteFill style={{ opacity: 0.08 }}>
        {Array.from({ length: 20 }).map((_, i) => (
          <div
            key={i}
            style={{
              position: "absolute",
              left: (i * 97) % 1080,
              top: (i * 173) % 1920,
              width: 4,
              height: 4,
              background: "white",
              borderRadius: "50%",
            }}
          />
        ))}
      </AbsoluteFill>

      <div
        style={{
          position: "absolute",
          left: 540 - 360 + widgetX,
          top: 700 + widgetY,
          width: 720,
          transform: `scale(${widgetScale * widgetSize})`,
          transformOrigin: "center",
          background: "rgba(20, 20, 24, 0.96)",
          border: "1px solid rgba(255,255,255,0.12)",
          borderRadius: 22,
          padding: 28,
          boxShadow: "0 30px 80px rgba(0,0,0,0.7)",
          backdropFilter: "blur(20px)",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 12,
            marginBottom: 16,
          }}
        >
          <div
            style={{
              width: 32,
              height: 32,
              background: GOLD,
              borderRadius: 8,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              color: BG,
              fontFamily: FONT_STACK,
              fontSize: 16,
              fontWeight: 900,
            }}
          >
            🏀
          </div>
          <div
            style={{
              color: "rgba(255,255,255,0.65)",
              fontFamily: FONT_STACK,
              fontSize: 18,
              fontWeight: 700,
              letterSpacing: 1.5,
            }}
          >
            NBA · 4TH QUARTER
          </div>
          {/* Pin indicator */}
          <div style={{ flex: 1 }} />
          <div
            style={{
              opacity: pinIconOpacity,
              fontSize: 26,
              transform: `rotate(${pinIconOpacity * 25}deg)`,
            }}
          >
            📌
          </div>
        </div>
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            color: "white",
            fontFamily: FONT_STACK,
          }}
        >
          <div style={{ textAlign: "center" }}>
            <div style={{ fontSize: 26, fontWeight: 700, opacity: 0.8 }}>
              LAL
            </div>
            <div style={{ fontSize: 88, fontWeight: 900, lineHeight: 1 }}>
              102
            </div>
          </div>
          <div
            style={{
              fontSize: 22,
              fontWeight: 700,
              color: GOLD,
              opacity: 0.85,
            }}
          >
            2:14
          </div>
          <div style={{ textAlign: "center" }}>
            <div style={{ fontSize: 26, fontWeight: 700, opacity: 0.8 }}>
              BOS
            </div>
            <div style={{ fontSize: 88, fontWeight: 900, lineHeight: 1 }}>
              99
            </div>
          </div>
        </div>
      </div>

      {/* Title */}
      <div
        style={{
          position: "absolute",
          top: 260,
          left: 0,
          right: 0,
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 96,
          fontWeight: 900,
          letterSpacing: -2,
          textAlign: "center",
          opacity: labelOpacity,
        }}
      >
        Pin any
        <br />
        <span style={{ color: GOLD }}>game.</span>
      </div>
    </AbsoluteFill>
  );
};

/* -------------- Scene 7: Open Source (24-28s, frames 720-840) ------------ */
const SceneOpenSource: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const opacity = interpolate(frame, [0, 12], [0, 1], {
    extrapolateRight: "clamp",
  });
  const scale = spring({ frame, fps, config: { damping: 14, stiffness: 70 } });

  return (
    <AbsoluteFill
      style={{
        background: "#000000",
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        gap: 40,
        opacity,
      }}
    >
      <div
        style={{
          color: GOLD,
          fontFamily: FONT_STACK,
          fontSize: 130,
          fontWeight: 900,
          letterSpacing: -3,
          textAlign: "center",
          lineHeight: 1.05,
          transform: `scale(${scale})`,
        }}
      >
        Free.
        <br />
        Open source.
        <br />
        Forever.
      </div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 14,
          marginTop: 30,
          opacity: interpolate(frame, [25, 45], [0, 1], {
            extrapolateRight: "clamp",
          }),
        }}
      >
        <svg width={48} height={48} viewBox="0 0 24 24" fill="white">
          <path d="M12 0a12 12 0 0 0-3.79 23.4c.6.11.82-.26.82-.58v-2.04c-3.34.72-4.04-1.6-4.04-1.6-.55-1.39-1.34-1.76-1.34-1.76-1.09-.74.08-.73.08-.73 1.21.09 1.84 1.24 1.84 1.24 1.07 1.84 2.81 1.31 3.5 1 .11-.78.42-1.31.76-1.61-2.66-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.13-.3-.54-1.52.11-3.18 0 0 1.01-.32 3.3 1.23a11.5 11.5 0 0 1 6.01 0c2.29-1.55 3.3-1.23 3.3-1.23.65 1.66.24 2.88.12 3.18.77.84 1.23 1.91 1.23 3.22 0 4.61-2.81 5.62-5.49 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.22.7.83.58A12 12 0 0 0 12 0z" />
        </svg>
        <div
          style={{
            color: "white",
            fontFamily: FONT_STACK,
            fontSize: 32,
            fontWeight: 600,
          }}
        >
          GitHub
        </div>
      </div>
    </AbsoluteFill>
  );
};

/* ------------------- Scene 8: CTA (28-30s, frames 840-900) --------------- */
const SceneCta: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phase 1 (0-15): "Sports Tracker" big
  // Phase 2 (15-35): "sportstracker.app"
  // Phase 3 (35-50): "Download free"
  // Phase 4 (50-60): trophy

  const titleOpacity = interpolate(frame, [0, 8], [0, 1], {
    extrapolateRight: "clamp",
  });
  const titleScale = spring({
    frame,
    fps,
    config: { damping: 14, stiffness: 80 },
  });

  const urlOpacity = interpolate(frame, [12, 22], [0, 1], {
    extrapolateRight: "clamp",
  });
  const urlY = interpolate(frame, [12, 25], [25, 0], {
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });

  const downloadOpacity = interpolate(frame, [28, 40], [0, 1], {
    extrapolateRight: "clamp",
  });
  const downloadScale = spring({
    frame: frame - 28,
    fps,
    config: { damping: 12 },
  });

  const trophyOpacity = interpolate(frame, [44, 54], [0, 1], {
    extrapolateRight: "clamp",
  });
  const trophyScale = spring({
    frame: frame - 44,
    fps,
    config: { damping: 10, stiffness: 100 },
  });

  return (
    <AbsoluteFill
      style={{
        background: BG,
        justifyContent: "center",
        alignItems: "center",
        flexDirection: "column",
        gap: 30,
        padding: 60,
      }}
    >
      <div
        style={{
          color: "white",
          fontFamily: FONT_STACK,
          fontSize: 130,
          fontWeight: 900,
          letterSpacing: -3,
          textAlign: "center",
          lineHeight: 1.0,
          opacity: titleOpacity,
          transform: `scale(${titleScale})`,
        }}
      >
        Sports
        <br />
        <span style={{ color: GOLD }}>Tracker</span>
      </div>

      <div
        style={{
          color: "rgba(255,255,255,0.8)",
          fontFamily: FONT_STACK,
          fontSize: 56,
          fontWeight: 600,
          opacity: urlOpacity,
          transform: `translateY(${urlY}px)`,
          letterSpacing: -0.5,
        }}
      >
        sportstracker.app
      </div>

      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 16,
          background: GOLD,
          color: BG,
          padding: "20px 40px",
          borderRadius: 18,
          fontFamily: FONT_STACK,
          fontSize: 44,
          fontWeight: 900,
          letterSpacing: -0.5,
          opacity: downloadOpacity,
          transform: `scale(${downloadScale})`,
        }}
      >
        <svg width={42} height={42} viewBox="0 0 24 24" fill="none">
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

      <div
        style={{
          marginTop: 30,
          opacity: trophyOpacity,
          transform: `scale(${trophyScale * 1.5})`,
        }}
      >
        <TrophyIcon size={130} color={GOLD} />
      </div>
    </AbsoluteFill>
  );
};

/* ============================ Main composition ============================ */
export const AdSportsTracker: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: BG, fontFamily: FONT_STACK }}>
      {/* 0-3s Hook */}
      <Sequence from={0} durationInFrames={90}>
        <SceneHook />
      </Sequence>
      {/* 3-6s Problem */}
      <Sequence from={90} durationInFrames={90}>
        <SceneProblem />
      </Sequence>
      {/* 6-9s Solution */}
      <Sequence from={180} durationInFrames={90}>
        <SceneSolution />
      </Sequence>
      {/* 9-14s Carousel */}
      <Sequence from={270} durationInFrames={150}>
        <SceneCarousel />
      </Sequence>
      {/* 14-19s Live drawings */}
      <Sequence from={420} durationInFrames={150}>
        <SceneLiveDrawings />
      </Sequence>
      {/* 19-24s Pin */}
      <Sequence from={570} durationInFrames={150}>
        <ScenePinFeature />
      </Sequence>
      {/* 24-28s Open source */}
      <Sequence from={720} durationInFrames={120}>
        <SceneOpenSource />
      </Sequence>
      {/* 28-30s CTA */}
      <Sequence from={840} durationInFrames={60}>
        <SceneCta />
      </Sequence>
    </AbsoluteFill>
  );
};

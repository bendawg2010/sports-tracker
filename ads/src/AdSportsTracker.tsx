import React from "react";
import {
  AbsoluteFill,
  Audio,
  Sequence,
  spring,
  staticFile,
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

/* ---------- Reusable: a Sports Tracker WidgetKit widget mockup ---------- */
/* Renders the actual native macOS widget look — proper container, dark
   gradient background like our SwiftUI .containerBackground produces,
   game rows in the LiveScoreWidget style.                                  */
const NativeWidgetMockup: React.FC<{
  size: "small" | "medium" | "large";
  scoreOffset?: number; // shift score numbers up over time
}> = ({ size, scoreOffset = 0 }) => {
  const dims = {
    small:  { w: 240, h: 240, rows: 2, padding: 12, fontHeader: 13, fontTeam: 13, fontScore: 22 },
    medium: { w: 500, h: 240, rows: 3, padding: 16, fontHeader: 14, fontTeam: 15, fontScore: 26 },
    large:  { w: 500, h: 500, rows: 6, padding: 20, fontHeader: 16, fontTeam: 16, fontScore: 28 },
  }[size];

  const games = [
    { away: "DUKE", home: "UNC", aS: 78 + scoreOffset, hS: 75, status: "2H · 4:32", live: true,  ac: "#003087", hc: "#7BAFD4" },
    { away: "LAL",  home: "BOS", aS: 102 + Math.floor(scoreOffset * 1.3), hS: 99,   status: "Q4 · 1:15", live: true,  ac: "#552583", hc: "#007A33" },
    { away: "NYY",  home: "BOS", aS: 4,   hS: 3,   status: "Top 5th",   live: true,  ac: "#003087", hc: "#BD3039" },
    { away: "ARS",  home: "MCI", aS: 2 + (scoreOffset > 1 ? 1 : 0), hS: 2, status: "87'", live: true, ac: "#EF0107", hc: "#6CABDD" },
    { away: "VER",  home: "HAM", aS: 1,   hS: 2,   status: "Lap 38/57", live: true,  ac: "#0600EF", hc: "#00D2BE" },
    { away: "PSG",  home: "RMA", aS: 0,   hS: 1,   status: "62'",       live: true,  ac: "#004170", hc: "#FFFFFF" },
  ].slice(0, dims.rows);

  return (
    <div
      style={{
        width: dims.w,
        height: dims.h,
        // Same .containerBackground gradient our real widget uses
        background: "linear-gradient(180deg, #0F0F14, #1A1A22)",
        borderRadius: 26,
        padding: dims.padding,
        boxShadow: "0 24px 60px rgba(0,0,0,0.55)",
        display: "flex",
        flexDirection: "column",
        gap: dims.padding * 0.5,
        fontFamily: FONT_STACK,
        color: "white",
        // Subtle Apple-widget glassy edge
        border: "1px solid rgba(255,255,255,0.06)",
        position: "relative",
        overflow: "hidden",
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          <TrophyIcon size={dims.fontHeader * 1.5} color={GOLD} />
          <span style={{ fontSize: dims.fontHeader, fontWeight: 700 }}>Sports Tracker</span>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 4, color: "#FF453A" }}>
          <span style={{ width: 6, height: 6, borderRadius: "50%", background: "#FF453A" }} />
          <span style={{ fontSize: dims.fontHeader * 0.75, fontWeight: 800 }}>LIVE</span>
        </div>
      </div>

      {games.map((g) => (
        <div
          key={g.away}
          style={{
            display: "grid",
            gridTemplateColumns: "auto 1fr auto",
            alignItems: "center",
            gap: 6,
            padding: "4px 0",
            borderTop: "1px solid rgba(255,255,255,0.05)",
          }}
        >
          <div style={{ display: "flex", gap: 3 }}>
            <span
              style={{
                width: dims.fontTeam * 1.3, height: dims.fontTeam * 1.3, borderRadius: 4,
                background: g.ac, color: "white",
                fontSize: dims.fontTeam * 0.7, fontWeight: 800,
                display: "flex", alignItems: "center", justifyContent: "center",
              }}
            >{g.away.charAt(0)}</span>
            <span
              style={{
                width: dims.fontTeam * 1.3, height: dims.fontTeam * 1.3, borderRadius: 4,
                background: g.hc, color: "#13294B",
                fontSize: dims.fontTeam * 0.7, fontWeight: 800,
                display: "flex", alignItems: "center", justifyContent: "center",
              }}
            >{g.home.charAt(0)}</span>
          </div>
          <div style={{ fontSize: dims.fontTeam, fontWeight: 600 }}>
            <span style={{ opacity: 0.85 }}>{g.away}</span>{" "}
            <span style={{ color: "rgba(255,255,255,0.4)" }}>vs</span>{" "}
            <span style={{ opacity: 0.85 }}>{g.home}</span>
            <div style={{ fontSize: dims.fontTeam * 0.65, color: "#FF453A", fontWeight: 700, marginTop: 1 }}>
              {g.status}
            </div>
          </div>
          <div
            style={{
              fontSize: dims.fontScore,
              fontWeight: 900,
              fontFamily: "SF Mono, monospace",
              color: g.live ? GOLD : "white",
            }}
          >
            {g.aS}–{g.hS}
          </div>
        </div>
      ))}
    </div>
  );
};

/* ---------------- Scene 4: Widget Gallery (9-14s, frames 270-420) -------- */
/* Shows that this is a real, native macOS WidgetKit widget — render a
   Notification Center sliding in from the right, the Sports Tracker widget
   sitting in the gallery, and an "Apple WidgetKit" badge.                  */
const SceneWidgetGallery: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Notification Center slides in from the right
  const slideIn = spring({
    frame,
    fps,
    config: { damping: 18, stiffness: 70, mass: 1 },
  });
  const slideX = interpolate(slideIn, [0, 1], [600, 0]);
  // Widget sizes appear staggered
  const smallScale  = spring({ frame: frame - 28, fps, config: { damping: 14 } });
  const mediumScale = spring({ frame: frame - 42, fps, config: { damping: 14 } });
  const largeScale  = spring({ frame: frame - 56, fps, config: { damping: 14 } });
  // Caption fade in
  const capOpacity = interpolate(frame, [50, 75], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <AbsoluteFill
      style={{
        background:
          "linear-gradient(135deg, #1a2a4a 0%, #2a1a3a 35%, #4a1a2a 100%)",
        overflow: "hidden",
      }}
    >
      {/* Wallpaper-style soft glows */}
      <AbsoluteFill style={{ opacity: 0.5 }}>
        <div
          style={{
            position: "absolute", top: -200, left: -200,
            width: 700, height: 700, borderRadius: "50%",
            background: "radial-gradient(circle, rgba(255,184,28,0.18), transparent 70%)",
            filter: "blur(60px)",
          }}
        />
      </AbsoluteFill>

      {/* macOS Menu Bar (top) */}
      <div
        style={{
          position: "absolute", top: 0, left: 0, right: 0, height: 80,
          background: "rgba(20,20,28,0.85)",
          backdropFilter: "blur(40px)",
          borderBottom: "1px solid rgba(255,255,255,0.08)",
          display: "flex", alignItems: "center", padding: "0 28px",
          fontFamily: FONT_STACK, color: "white", gap: 24,
        }}
      >
        <div style={{ fontSize: 22 }}>{"\u{F8FF}"}</div>
        <div style={{ fontWeight: 600, fontSize: 18 }}>Finder</div>
        <div style={{ flex: 1 }} />
        <TrophyIcon size={28} color={GOLD} />
        <span style={{ fontWeight: 800, color: "#FF453A", fontSize: 15 }}>4 LIVE</span>
        <div style={{ fontSize: 17, opacity: 0.7 }}>7:24 PM</div>
      </div>

      {/* Notification Center sliding in from right */}
      <div
        style={{
          position: "absolute",
          top: 90,
          right: 30,
          bottom: 30,
          width: 620,
          background: "rgba(15,15,22,0.85)",
          backdropFilter: "blur(40px)",
          borderRadius: 28,
          border: "1px solid rgba(255,255,255,0.08)",
          padding: "30px 30px 24px",
          transform: `translateX(${slideX}px)`,
          boxShadow: "0 30px 80px rgba(0,0,0,0.6)",
          display: "flex", flexDirection: "column",
          fontFamily: FONT_STACK, color: "white",
        }}
      >
        {/* Section header */}
        <div
          style={{
            fontSize: 24, fontWeight: 800, marginBottom: 16,
            display: "flex", alignItems: "center", gap: 10,
          }}
        >
          <span style={{ fontSize: 22 }}>📅</span>
          Today
        </div>

        {/* Three widget sizes laid out */}
        <div style={{ display: "flex", flexDirection: "column", gap: 16, alignItems: "center", flex: 1 }}>
          <div style={{ transform: `scale(${largeScale * 0.9})`, transformOrigin: "center" }}>
            <NativeWidgetMockup size="large" scoreOffset={Math.floor(frame / 30)} />
          </div>
          <div
            style={{
              display: "flex",
              gap: 16,
              transform: `scale(${mediumScale})`,
              transformOrigin: "center",
            }}
          >
            <div style={{ transform: `scale(${smallScale * 0.85})` }}>
              <NativeWidgetMockup size="small" scoreOffset={Math.floor(frame / 30)} />
            </div>
          </div>
        </div>
      </div>

      {/* Left side caption — "Native Apple Widget" */}
      <div
        style={{
          position: "absolute",
          top: 280,
          left: 80,
          width: 600,
          color: "white",
          fontFamily: FONT_STACK,
          opacity: capOpacity,
        }}
      >
        <div
          style={{
            display: "inline-block",
            background: "rgba(255,255,255,0.08)",
            border: "1px solid rgba(255,255,255,0.15)",
            borderRadius: 999,
            padding: "8px 18px",
            fontSize: 18,
            fontWeight: 700,
            color: GOLD,
            marginBottom: 24,
            letterSpacing: 0.5,
          }}
        >
          BUILT WITH APPLE WIDGETKIT
        </div>
        <div
          style={{
            fontSize: 96,
            fontWeight: 900,
            letterSpacing: -3,
            lineHeight: 1.0,
            marginBottom: 20,
          }}
        >
          A real
          <br />
          <span style={{ color: GOLD }}>native widget.</span>
        </div>
        <div
          style={{
            fontSize: 28,
            fontWeight: 600,
            color: "rgba(255,255,255,0.75)",
            lineHeight: 1.3,
          }}
        >
          Add it from Notification Center.
          <br />
          Three sizes. 100% Swift. Zero hacks.
        </div>
      </div>
    </AbsoluteFill>
  );
};

/* ---------------- Old Menu Bar Tour kept around for reference ---------- */
const SceneMenuBarTour: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phases (150 frames total = 5s @ 30fps)
  // 0-30   : Menu bar with trophy icon, cursor moves toward it
  // 30-45  : Click pulse on trophy icon
  // 45-150 : Popover opens (spring), score rows tick up live
  const cursorX = interpolate(frame, [0, 30], [380, 540], {
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const cursorY = interpolate(frame, [0, 30], [800, 105], {
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  // Click ripple at frame 32
  const clickRipple = interpolate(frame, [32, 52], [0, 1.5], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const clickRippleOpacity = interpolate(frame, [32, 52], [0.7, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  // Popover open spring at frame 38
  const popoverOpen = spring({
    frame: frame - 38,
    fps,
    config: { damping: 14, stiffness: 95, mass: 0.8 },
  });
  const popoverOpacity = interpolate(frame, [38, 60], [0, 1], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Live score updates within popover
  const dukeScore = frame < 75 ? 78 : frame < 95 ? 79 : frame < 115 ? 81 : 83;
  const lalScore = frame < 90 ? 102 : frame < 110 ? 104 : 105;
  const arsScore = frame < 100 ? 2 : 3;
  const flash = (changeFrame: number) => {
    const d = frame - changeFrame;
    if (d < 0 || d > 14) return 0;
    return Math.sin((d / 14) * Math.PI) * 0.85;
  };

  return (
    <AbsoluteFill
      style={{
        background:
          "linear-gradient(135deg, #1a2a4a 0%, #2a1a3a 35%, #4a1a2a 100%)",
        overflow: "hidden",
      }}
    >
      {/* Wallpaper-style soft glow */}
      <AbsoluteFill style={{ opacity: 0.5 }}>
        <div
          style={{
            position: "absolute",
            top: -200, left: -200, width: 700, height: 700,
            borderRadius: "50%",
            background: "radial-gradient(circle, rgba(255,184,28,0.18), transparent 70%)",
            filter: "blur(60px)",
          }}
        />
      </AbsoluteFill>

      {/* macOS Menu Bar (top edge) */}
      <div
        style={{
          position: "absolute",
          top: 0, left: 0, right: 0,
          height: 100,
          background: "rgba(20,20,28,0.85)",
          backdropFilter: "blur(40px)",
          borderBottom: "1px solid rgba(255,255,255,0.08)",
          display: "flex",
          alignItems: "center",
          padding: "0 32px",
          fontFamily: FONT_STACK,
          color: "white",
          gap: 28,
        }}
      >
        <div style={{ fontSize: 28 }}>{"\u{F8FF}"}</div>
        <div style={{ fontWeight: 600, fontSize: 22 }}>Finder</div>
        <div style={{ fontSize: 20, opacity: 0.65 }}>File</div>
        <div style={{ fontSize: 20, opacity: 0.65 }}>Edit</div>
        <div style={{ fontSize: 20, opacity: 0.65 }}>View</div>
        <div style={{ flex: 1 }} />
        {/* Trophy icon — pulses, then highlights when clicked */}
        <div
          style={{
            position: "relative",
            display: "flex",
            alignItems: "center",
            gap: 10,
            padding: "10px 16px",
            borderRadius: 12,
            background:
              frame >= 32 && frame < 60
                ? "rgba(255,184,28,0.28)"
                : "transparent",
            transition: "background 0.2s",
          }}
        >
          {/* Click ripple */}
          {frame >= 32 && (
            <div
              style={{
                position: "absolute",
                top: "50%", left: "50%",
                width: 10, height: 10,
                marginTop: -5, marginLeft: -5,
                borderRadius: "50%",
                background: GOLD,
                transform: `scale(${1 + clickRipple * 8})`,
                opacity: clickRippleOpacity,
              }}
            />
          )}
          <TrophyIcon size={36} color={GOLD} />
          <span style={{ fontWeight: 800, color: "#FF453A", fontSize: 18 }}>
            4 LIVE
          </span>
        </div>
        <div style={{ fontSize: 20, opacity: 0.7 }}>7:24 PM</div>
      </div>

      {/* POPOVER — opens from the trophy icon */}
      <div
        style={{
          position: "absolute",
          top: 110,
          right: 200,
          width: 720,
          background: "rgba(15,15,20,0.97)",
          borderRadius: 22,
          padding: 28,
          backdropFilter: "blur(40px)",
          border: "1px solid rgba(255,255,255,0.1)",
          boxShadow: "0 40px 100px rgba(0,0,0,0.7)",
          color: "white",
          fontFamily: FONT_STACK,
          opacity: popoverOpacity,
          transform: `scale(${0.85 + popoverOpen * 0.15}) translateY(${(1 - popoverOpen) * -20}px)`,
          transformOrigin: "top right",
        }}
      >
        {/* Connector triangle to menu bar */}
        <div
          style={{
            position: "absolute",
            top: -10, right: 60,
            width: 20, height: 20,
            background: "rgba(15,15,20,0.97)",
            transform: "rotate(45deg)",
            borderTop: "1px solid rgba(255,255,255,0.1)",
            borderLeft: "1px solid rgba(255,255,255,0.1)",
          }}
        />

        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            marginBottom: 22,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            <TrophyIcon size={36} color={GOLD} />
            <div style={{ fontSize: 30, fontWeight: 800 }}>Sports Tracker</div>
          </div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 10,
              color: "#FF453A",
              fontWeight: 800,
              fontSize: 18,
            }}
          >
            <span
              style={{
                width: 14, height: 14, borderRadius: "50%",
                background: "#FF453A",
                opacity: 0.6 + 0.4 * Math.sin(frame * 0.4),
              }}
            />
            4 LIVE
          </div>
        </div>

        {/* Game rows with live ticking scores */}
        {[
          { away: "DUKE", home: "UNC", aColor: "#003087", hColor: "#7BAFD4",
            aScore: dukeScore, hScore: 75, status: "2H · 4:32",
            wp: `DUKE ${64 + (dukeScore - 78)}%`, flashOn: 75 },
          { away: "LAL", home: "BOS", aColor: "#552583", hColor: "#007A33",
            aScore: lalScore, hScore: 99, status: "Q4 · 1:15",
            wp: "LAL 78%", flashOn: 90 },
          { away: "NYY", home: "BOS", aColor: "#003087", hColor: "#BD3039",
            aScore: 4, hScore: 3, status: "Top 5th",
            wp: "NYY 56%", flashOn: -1 },
          { away: "ARS", home: "MCI", aColor: "#EF0107", hColor: "#6CABDD",
            aScore: arsScore, hScore: 2, status: "87'",
            wp: "DRAW", flashOn: 100 },
        ].map((g) => {
          const f = flash(g.flashOn);
          return (
            <div
              key={g.away}
              style={{
                display: "grid",
                gridTemplateColumns: "auto 1fr auto auto",
                gap: 18,
                alignItems: "center",
                padding: "14px 16px",
                borderRadius: 14,
                background: `rgba(255,184,28,${f * 0.3})`,
                marginBottom: 10,
              }}
            >
              <div style={{ display: "flex", gap: 6 }}>
                <span
                  style={{
                    width: 32, height: 32, borderRadius: 6,
                    background: g.aColor,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    fontWeight: 800, fontSize: 13,
                  }}
                >
                  {g.away.slice(0, 1)}
                </span>
                <span
                  style={{
                    width: 32, height: 32, borderRadius: 6,
                    background: g.hColor,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    fontWeight: 800, fontSize: 13,
                    color: "#13294B",
                  }}
                >
                  {g.home.slice(0, 1)}
                </span>
              </div>
              <div style={{ fontSize: 22, fontWeight: 700 }}>
                {g.away} <span style={{ opacity: 0.5 }}>vs</span> {g.home}
              </div>
              <div
                style={{
                  fontSize: 30, fontWeight: 900,
                  fontFamily: "SF Mono, monospace",
                  color: f > 0.05 ? GOLD : "white",
                  filter: `brightness(${1 + f * 0.6})`,
                }}
              >
                {g.aScore}–{g.hScore}
              </div>
              <div
                style={{
                  display: "flex", flexDirection: "column",
                  alignItems: "flex-end", gap: 2,
                }}
              >
                <span style={{ fontSize: 14, color: "#FF453A", fontWeight: 700 }}>
                  {g.status}
                </span>
                <span style={{ fontSize: 12, color: GOLD, fontWeight: 700 }}>
                  {g.wp}
                </span>
              </div>
            </div>
          );
        })}
      </div>

      {/* Cursor */}
      <div
        style={{
          position: "absolute",
          top: cursorY,
          left: cursorX,
          width: 32,
          height: 32,
          pointerEvents: "none",
          opacity: frame < 130 ? 1 : interpolate(frame, [130, 145], [1, 0]),
        }}
      >
        <svg viewBox="0 0 32 32" width="32" height="32">
          <path
            d="M3 3 L3 24 L9 19 L13 28 L17 26 L13 17 L21 17 Z"
            fill="white"
            stroke="black"
            strokeWidth="1.5"
          />
        </svg>
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
  // 5 seconds = 150 frames. Two quick field flashes then drop into a full
  // desktop showcase with the app actually working live on a Mac.
  return (
    <>
      <LiveDrawingPanel
        sport="football"
        overlayText="1ST & GOAL"
        startFrame={0}
        durationFrames={36}
        showDriveArrow
      />
      <LiveDrawingPanel
        sport="basketball"
        overlayText="DUKE 78  UNC 75"
        startFrame={36}
        durationFrames={36}
        showShots
      />
      {/* Full Mac desktop, menu bar ticker scrolling, popover open with
          live-updating game rows, two pinned widgets in the corners */}
      <Sequence from={72} durationInFrames={78}>
        <SceneDesktopShowcase />
      </Sequence>
    </>
  );
};

/* ---------- Scene 5b: Widget On Desktop — the WidgetKit hero shot ---------- */
const SceneDesktopShowcase: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Whole-scene entry
  const enter = spring({ frame, fps, config: { damping: 14, stiffness: 70, mass: 0.8 } });

  // The widget pulses gently when fresh data lands (every ~30 frames)
  const pulseFrame = frame % 30;
  const pulse = pulseFrame < 6 ? Math.sin((pulseFrame / 6) * Math.PI) * 0.05 : 0;

  // Score offset ticks up over time so users see the widget UPDATE
  const scoreOffset = Math.floor(frame / 24);

  // Caption fade
  const capFade = interpolate(frame, [20, 50], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <AbsoluteFill
      style={{
        background: "linear-gradient(135deg, #1a2a4a 0%, #2a1a3a 35%, #4a1a2a 100%)",
        overflow: "hidden",
      }}
    >
      {/* Wallpaper glows */}
      <AbsoluteFill style={{ opacity: 0.6 }}>
        <div style={{
          position: "absolute", top: -150, right: -150, width: 700, height: 700,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(255,184,28,0.20), transparent 70%)",
          filter: "blur(60px)",
        }} />
        <div style={{
          position: "absolute", bottom: -250, left: -250, width: 800, height: 800,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(85,37,131,0.18), transparent 70%)",
          filter: "blur(80px)",
        }} />
      </AbsoluteFill>

      {/* macOS Menu Bar */}
      <div style={{
        position: "absolute", top: 0, left: 0, right: 0, height: 80,
        background: "rgba(20,20,28,0.85)",
        backdropFilter: "blur(40px)",
        borderBottom: "1px solid rgba(255,255,255,0.08)",
        display: "flex", alignItems: "center", padding: "0 28px",
        fontFamily: FONT_STACK, color: "white", gap: 24,
      }}>
        <div style={{ fontSize: 22 }}>{"\u{F8FF}"}</div>
        <div style={{ fontWeight: 600, fontSize: 18 }}>Finder</div>
        <div style={{ flex: 1 }} />
        <TrophyIcon size={28} color={GOLD} />
        <span style={{ fontWeight: 800, color: "#FF453A", fontSize: 15 }}>4 LIVE</span>
        <div style={{ fontSize: 17, opacity: 0.7 }}>7:24 PM</div>
      </div>

      {/* Big "WidgetKit" caption header */}
      <div style={{
        position: "absolute", top: 130, left: 0, right: 0,
        textAlign: "center", color: "white", fontFamily: FONT_STACK,
        opacity: capFade,
      }}>
        <div style={{
          display: "inline-block",
          background: "rgba(255,255,255,0.06)",
          border: "1px solid rgba(255,255,255,0.12)",
          borderRadius: 999,
          padding: "6px 16px",
          fontSize: 16, fontWeight: 700,
          color: GOLD, letterSpacing: 0.4,
        }}>NATIVE macOS WIDGET · BUILT WITH WIDGETKIT</div>
      </div>

      {/* THE HERO: a large native widget right in the center of the desktop */}
      <div style={{
        position: "absolute",
        top: "50%", left: "50%",
        transform: `translate(-50%, -50%) scale(${(0.85 + enter * 0.15) * (1 + pulse)})`,
        opacity: enter,
        // Outer "selected" gold ring that pulses subtly
        padding: 4,
        borderRadius: 30,
        background: pulse > 0.01
          ? `radial-gradient(circle, rgba(255,184,28,${0.5 + pulse * 4}), rgba(255,184,28,0))`
          : "transparent",
      }}>
        <NativeWidgetMockup size="large" scoreOffset={scoreOffset} />
      </div>

      {/* Bottom caption */}
      <div style={{
        position: "absolute", bottom: 60, left: 0, right: 0,
        textAlign: "center", color: "white", fontFamily: FONT_STACK,
        opacity: capFade,
      }}>
        <div style={{ fontSize: 36, fontWeight: 800, letterSpacing: -1 }}>
          Lives in <span style={{ color: GOLD }}>Notification Center</span>.
        </div>
        <div style={{ fontSize: 20, fontWeight: 600, color: "rgba(255,255,255,0.65)", marginTop: 8 }}>
          Updates automatically. Like every other Apple widget.
        </div>
      </div>
    </AbsoluteFill>
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
  // Phase 2 (15-35): "sports-tracker.pages.dev"
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
        sports-tracker.pages.dev
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
      {/* Sport-anthem soundtrack — synthesized arena hype track timed to
          the storyboard cuts. Place sports-anthem.mp3 in `public/`. */}
      <Audio src={staticFile("sports-anthem.mp3")} volume={0.85} />
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
        <SceneWidgetGallery />
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

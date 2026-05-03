import React from "react";
import { useCurrentFrame, useVideoConfig } from "remotion";

interface MenuBarMockupProps {
  width?: number;
  scrollSpeed?: number;
}

const TICKER_GAMES = [
  { league: "CBB", home: "DUKE", homeScore: 78, away: "UNC", awayScore: 75, status: "F" },
  { league: "NBA", home: "LAL", homeScore: 102, away: "BOS", awayScore: 99, status: "Q4" },
  { league: "NFL", home: "KC", homeScore: 24, away: "BUF", awayScore: 21, status: "Q3" },
  { league: "MLB", home: "NYY", homeScore: 5, away: "BOS", awayScore: 3, status: "T7" },
  { league: "NHL", home: "BOS", homeScore: 4, away: "NYR", awayScore: 2, status: "P3" },
  { league: "EPL", home: "ARS", homeScore: 2, away: "MCI", awayScore: 1, status: "82'" },
];

const TrophyIcon: React.FC<{ size?: number; color?: string }> = ({
  size = 22,
  color = "#FFB81C",
}) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <path
      d="M6 4h12v3a6 6 0 0 1-6 6 6 6 0 0 1-6-6V4z"
      fill={color}
      stroke={color}
      strokeWidth={1}
    />
    <path
      d="M6 6H3v2a3 3 0 0 0 3 3M18 6h3v2a3 3 0 0 1-3 3"
      stroke={color}
      strokeWidth={1.5}
      fill="none"
    />
    <path
      d="M10 14h4v3h-4z M8 17h8v2H8z"
      fill={color}
    />
  </svg>
);

const TickerItem: React.FC<{
  game: (typeof TICKER_GAMES)[number];
}> = ({ game }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 8,
      padding: "0 16px",
      borderRight: "1px solid rgba(255,255,255,0.18)",
      whiteSpace: "nowrap",
      fontFamily: "Inter, -apple-system, SF Pro Text, sans-serif",
      color: "white",
      fontSize: 22,
      fontWeight: 600,
    }}
  >
    <span
      style={{
        color: "#FFB81C",
        fontSize: 14,
        fontWeight: 800,
        letterSpacing: 1,
      }}
    >
      {game.league}
    </span>
    <span style={{ opacity: 0.85 }}>{game.away}</span>
    <span style={{ fontWeight: 900 }}>{game.awayScore}</span>
    <span style={{ opacity: 0.4 }}>·</span>
    <span style={{ opacity: 0.85 }}>{game.home}</span>
    <span style={{ fontWeight: 900 }}>{game.homeScore}</span>
    <span
      style={{
        color: "#10B981",
        fontSize: 16,
        fontWeight: 700,
        marginLeft: 4,
      }}
    >
      {game.status}
    </span>
  </div>
);

export const MenuBarMockup: React.FC<MenuBarMockupProps> = ({
  width = 980,
  scrollSpeed = 2.2,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Scroll loops over total ticker width
  const scrollPx = (frame / fps) * scrollSpeed * 100;

  const barHeight = 56;
  const tickerOffset = -((scrollPx) % 2400);

  return (
    <div
      style={{
        width,
        background: "rgba(20, 20, 24, 0.92)",
        backdropFilter: "blur(20px)",
        borderRadius: 14,
        border: "1px solid rgba(255,255,255,0.08)",
        boxShadow: "0 24px 60px rgba(0,0,0,0.6)",
        overflow: "hidden",
      }}
    >
      {/* Top bar */}
      <div
        style={{
          height: barHeight,
          display: "flex",
          alignItems: "center",
          padding: "0 20px",
          gap: 14,
          borderBottom: "1px solid rgba(255,255,255,0.08)",
        }}
      >
        <TrophyIcon size={26} />
        <div
          style={{
            color: "white",
            fontFamily: "Inter, -apple-system, sans-serif",
            fontSize: 20,
            fontWeight: 700,
            letterSpacing: 0.3,
          }}
        >
          Sports Tracker
        </div>
        <div style={{ flex: 1 }} />
        {/* macOS menu bar items (faded) */}
        {["Wi-Fi", "Battery", "Time", "100%"].map((item) => (
          <span
            key={item}
            style={{
              color: "rgba(255,255,255,0.45)",
              fontFamily: "Inter, -apple-system, sans-serif",
              fontSize: 14,
              fontWeight: 500,
            }}
          >
            {item}
          </span>
        ))}
      </div>
      {/* Ticker row */}
      <div
        style={{
          height: 50,
          display: "flex",
          alignItems: "center",
          overflow: "hidden",
          position: "relative",
        }}
      >
        <div
          style={{
            display: "flex",
            transform: `translateX(${tickerOffset}px)`,
            willChange: "transform",
          }}
        >
          {[...TICKER_GAMES, ...TICKER_GAMES, ...TICKER_GAMES].map((g, i) => (
            <TickerItem key={i} game={g} />
          ))}
        </div>
      </div>
    </div>
  );
};

export { TrophyIcon };

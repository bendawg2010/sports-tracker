import React from "react";

export type Sport =
  | "football"
  | "basketball"
  | "baseball"
  | "hockey"
  | "soccer"
  | "tennis"
  | "golf"
  | "f1"
  | "ufc";

export const SPORT_LABELS: Record<Sport, string> = {
  football: "FOOTBALL",
  basketball: "BASKETBALL",
  baseball: "BASEBALL",
  hockey: "HOCKEY",
  soccer: "SOCCER",
  tennis: "TENNIS",
  golf: "GOLF",
  f1: "F1",
  ufc: "UFC",
};

interface SportFieldProps {
  sport: Sport;
  width?: number;
  height?: number;
  showOverlay?: boolean;
  overlayText?: string;
  showShots?: boolean;
  showRunners?: boolean;
  showDriveArrow?: boolean;
}

const VIEW_W = 400;
const VIEW_H = 250;

const Football: React.FC<{ showDriveArrow?: boolean }> = ({
  showDriveArrow,
}) => (
  <g>
    {/* Field grass */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#1F6F3D" />
    {/* End zones */}
    <rect x={0} y={0} width={40} height={VIEW_H} fill="#0E4A26" />
    <rect x={VIEW_W - 40} y={0} width={40} height={VIEW_H} fill="#8C1D1D" />
    {/* Yard lines */}
    {Array.from({ length: 9 }, (_, i) => (
      <line
        key={i}
        x1={40 + (i + 1) * 32}
        y1={10}
        x2={40 + (i + 1) * 32}
        y2={VIEW_H - 10}
        stroke="white"
        strokeWidth={2}
        opacity={0.85}
      />
    ))}
    {/* Hash marks center */}
    <line
      x1={40}
      y1={VIEW_H / 2}
      x2={VIEW_W - 40}
      y2={VIEW_H / 2}
      stroke="white"
      strokeWidth={1}
      opacity={0.4}
      strokeDasharray="4 4"
    />
    {/* 50-yard line */}
    <text
      x={VIEW_W / 2}
      y={VIEW_H / 2 + 6}
      fill="white"
      fontSize={18}
      fontWeight={700}
      textAnchor="middle"
      opacity={0.9}
    >
      50
    </text>
    {showDriveArrow && (
      <g>
        <path
          d={`M 80 ${VIEW_H / 2} Q 200 60, 340 ${VIEW_H / 2}`}
          stroke="#FFB81C"
          strokeWidth={6}
          fill="none"
          strokeLinecap="round"
        />
        <polygon
          points={`340,${VIEW_H / 2 - 10} 360,${VIEW_H / 2} 340,${VIEW_H / 2 + 10}`}
          fill="#FFB81C"
        />
        <circle cx={80} cy={VIEW_H / 2} r={8} fill="#FFB81C" />
      </g>
    )}
  </g>
);

const Basketball: React.FC<{ showShots?: boolean }> = ({ showShots }) => (
  <g>
    {/* Court */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#C99368" />
    {/* Outer boundary */}
    <rect
      x={10}
      y={10}
      width={VIEW_W - 20}
      height={VIEW_H - 20}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Center line */}
    <line
      x1={VIEW_W / 2}
      y1={10}
      x2={VIEW_W / 2}
      y2={VIEW_H - 10}
      stroke="white"
      strokeWidth={2.5}
    />
    {/* Center circle */}
    <circle
      cx={VIEW_W / 2}
      cy={VIEW_H / 2}
      r={28}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Left key */}
    <rect
      x={10}
      y={VIEW_H / 2 - 40}
      width={60}
      height={80}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Left three-point arc */}
    <path
      d={`M 10 50 Q 130 ${VIEW_H / 2}, 10 ${VIEW_H - 50}`}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Right key */}
    <rect
      x={VIEW_W - 70}
      y={VIEW_H / 2 - 40}
      width={60}
      height={80}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Right three-point arc */}
    <path
      d={`M ${VIEW_W - 10} 50 Q ${VIEW_W - 130} ${VIEW_H / 2}, ${VIEW_W - 10} ${VIEW_H - 50}`}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Hoops */}
    <circle cx={20} cy={VIEW_H / 2} r={5} fill="#FFB81C" />
    <circle cx={VIEW_W - 20} cy={VIEW_H / 2} r={5} fill="#FFB81C" />
    {showShots && (
      <g>
        <circle cx={120} cy={80} r={8} fill="#22C55E" stroke="white" strokeWidth={2} />
        <circle cx={150} cy={170} r={8} fill="#EF4444" stroke="white" strokeWidth={2} />
        <circle cx={100} cy={130} r={8} fill="#22C55E" stroke="white" strokeWidth={2} />
        <circle cx={280} cy={90} r={8} fill="#22C55E" stroke="white" strokeWidth={2} />
        <circle cx={310} cy={160} r={8} fill="#EF4444" stroke="white" strokeWidth={2} />
        <circle cx={250} cy={130} r={8} fill="#22C55E" stroke="white" strokeWidth={2} />
      </g>
    )}
  </g>
);

const Baseball: React.FC<{ showRunners?: boolean }> = ({ showRunners }) => (
  <g>
    {/* Field background */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#1F6F3D" />
    {/* Outfield arc */}
    <path
      d={`M 30 ${VIEW_H - 20} Q ${VIEW_W / 2} -120, ${VIEW_W - 30} ${VIEW_H - 20} Z`}
      fill="#2D8A4F"
    />
    {/* Infield diamond (dirt) */}
    <polygon
      points={`${VIEW_W / 2},${VIEW_H - 50} ${VIEW_W / 2 + 80},${VIEW_H / 2 + 30} ${VIEW_W / 2},${VIEW_H / 2 - 50} ${VIEW_W / 2 - 80},${VIEW_H / 2 + 30}`}
      fill="#B07A4A"
      stroke="white"
      strokeWidth={2}
    />
    {/* Pitcher's mound */}
    <circle cx={VIEW_W / 2} cy={VIEW_H / 2 + 20} r={10} fill="#8C5E36" />
    {/* Bases */}
    <rect
      x={VIEW_W / 2 - 6}
      y={VIEW_H - 56}
      width={12}
      height={12}
      fill="white"
      transform={`rotate(45 ${VIEW_W / 2} ${VIEW_H - 50})`}
    />
    <rect
      x={VIEW_W / 2 + 74}
      y={VIEW_H / 2 + 24}
      width={12}
      height={12}
      fill={showRunners ? "#FFB81C" : "white"}
      transform={`rotate(45 ${VIEW_W / 2 + 80} ${VIEW_H / 2 + 30})`}
    />
    <rect
      x={VIEW_W / 2 - 6}
      y={VIEW_H / 2 - 56}
      width={12}
      height={12}
      fill={showRunners ? "#FFB81C" : "white"}
      transform={`rotate(45 ${VIEW_W / 2} ${VIEW_H / 2 - 50})`}
    />
    <rect
      x={VIEW_W / 2 - 86}
      y={VIEW_H / 2 + 24}
      width={12}
      height={12}
      fill="white"
      transform={`rotate(45 ${VIEW_W / 2 - 80} ${VIEW_H / 2 + 30})`}
    />
    {showRunners && (
      <g>
        <circle cx={VIEW_W / 2 + 80} cy={VIEW_H / 2 + 18} r={6} fill="#EF4444" stroke="white" strokeWidth={2} />
        <circle cx={VIEW_W / 2} cy={VIEW_H / 2 - 62} r={6} fill="#EF4444" stroke="white" strokeWidth={2} />
      </g>
    )}
  </g>
);

const Hockey: React.FC = () => (
  <g>
    {/* Ice */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#D6E8F0" />
    {/* Boards */}
    <rect
      x={10}
      y={10}
      width={VIEW_W - 20}
      height={VIEW_H - 20}
      rx={40}
      ry={40}
      stroke="#1F2937"
      strokeWidth={3}
      fill="none"
    />
    {/* Center red line */}
    <line
      x1={VIEW_W / 2}
      y1={10}
      x2={VIEW_W / 2}
      y2={VIEW_H - 10}
      stroke="#EF4444"
      strokeWidth={4}
    />
    {/* Blue lines */}
    <line
      x1={VIEW_W / 2 - 60}
      y1={10}
      x2={VIEW_W / 2 - 60}
      y2={VIEW_H - 10}
      stroke="#3B82F6"
      strokeWidth={4}
    />
    <line
      x1={VIEW_W / 2 + 60}
      y1={10}
      x2={VIEW_W / 2 + 60}
      y2={VIEW_H - 10}
      stroke="#3B82F6"
      strokeWidth={4}
    />
    {/* Center circle */}
    <circle
      cx={VIEW_W / 2}
      cy={VIEW_H / 2}
      r={26}
      stroke="#3B82F6"
      strokeWidth={2}
      fill="none"
    />
    {/* Goal creases */}
    <path
      d={`M 30 ${VIEW_H / 2 - 20} Q 60 ${VIEW_H / 2}, 30 ${VIEW_H / 2 + 20}`}
      fill="#93C5FD"
      stroke="#EF4444"
      strokeWidth={2}
    />
    <path
      d={`M ${VIEW_W - 30} ${VIEW_H / 2 - 20} Q ${VIEW_W - 60} ${VIEW_H / 2}, ${VIEW_W - 30} ${VIEW_H / 2 + 20}`}
      fill="#93C5FD"
      stroke="#EF4444"
      strokeWidth={2}
    />
    {/* Faceoff dots */}
    <circle cx={80} cy={70} r={4} fill="#EF4444" />
    <circle cx={80} cy={VIEW_H - 70} r={4} fill="#EF4444" />
    <circle cx={VIEW_W - 80} cy={70} r={4} fill="#EF4444" />
    <circle cx={VIEW_W - 80} cy={VIEW_H - 70} r={4} fill="#EF4444" />
  </g>
);

const Soccer: React.FC = () => (
  <g>
    {/* Pitch */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#1F6F3D" />
    {/* Stripes */}
    {Array.from({ length: 8 }, (_, i) => (
      <rect
        key={i}
        x={i * 50}
        y={0}
        width={50}
        height={VIEW_H}
        fill={i % 2 === 0 ? "#1F6F3D" : "#2A8049"}
      />
    ))}
    {/* Outer line */}
    <rect
      x={10}
      y={10}
      width={VIEW_W - 20}
      height={VIEW_H - 20}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Center line */}
    <line
      x1={VIEW_W / 2}
      y1={10}
      x2={VIEW_W / 2}
      y2={VIEW_H - 10}
      stroke="white"
      strokeWidth={2.5}
    />
    {/* Center circle */}
    <circle
      cx={VIEW_W / 2}
      cy={VIEW_H / 2}
      r={32}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    <circle cx={VIEW_W / 2} cy={VIEW_H / 2} r={3} fill="white" />
    {/* Penalty boxes */}
    <rect
      x={10}
      y={VIEW_H / 2 - 50}
      width={50}
      height={100}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    <rect
      x={VIEW_W - 60}
      y={VIEW_H / 2 - 50}
      width={50}
      height={100}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Goals */}
    <rect
      x={2}
      y={VIEW_H / 2 - 18}
      width={8}
      height={36}
      fill="white"
      stroke="#1F2937"
      strokeWidth={1}
    />
    <rect
      x={VIEW_W - 10}
      y={VIEW_H / 2 - 18}
      width={8}
      height={36}
      fill="white"
      stroke="#1F2937"
      strokeWidth={1}
    />
  </g>
);

const Tennis: React.FC = () => (
  <g>
    {/* Court surface */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#2563EB" />
    {/* Outer green */}
    <rect x={20} y={20} width={VIEW_W - 40} height={VIEW_H - 40} fill="#15803D" />
    {/* Inner court (blue) */}
    <rect x={50} y={50} width={VIEW_W - 100} height={VIEW_H - 100} fill="#2563EB" />
    {/* Outer lines */}
    <rect
      x={50}
      y={50}
      width={VIEW_W - 100}
      height={VIEW_H - 100}
      stroke="white"
      strokeWidth={2.5}
      fill="none"
    />
    {/* Net */}
    <line
      x1={VIEW_W / 2}
      y1={50}
      x2={VIEW_W / 2}
      y2={VIEW_H - 50}
      stroke="white"
      strokeWidth={3}
    />
    {/* Service boxes */}
    <line
      x1={VIEW_W / 2 - 60}
      y1={80}
      x2={VIEW_W / 2 - 60}
      y2={VIEW_H - 80}
      stroke="white"
      strokeWidth={2}
    />
    <line
      x1={VIEW_W / 2 + 60}
      y1={80}
      x2={VIEW_W / 2 + 60}
      y2={VIEW_H - 80}
      stroke="white"
      strokeWidth={2}
    />
    <line
      x1={VIEW_W / 2 - 60}
      y1={VIEW_H / 2}
      x2={VIEW_W / 2 + 60}
      y2={VIEW_H / 2}
      stroke="white"
      strokeWidth={2}
    />
    {/* Doubles tramlines */}
    <line
      x1={50}
      y1={80}
      x2={VIEW_W - 50}
      y2={80}
      stroke="white"
      strokeWidth={2}
    />
    <line
      x1={50}
      y1={VIEW_H - 80}
      x2={VIEW_W - 50}
      y2={VIEW_H - 80}
      stroke="white"
      strokeWidth={2}
    />
    {/* Ball */}
    <circle cx={VIEW_W / 2 + 90} cy={VIEW_H / 2 - 30} r={6} fill="#FBBF24" stroke="white" strokeWidth={1.5} />
  </g>
);

const Golf: React.FC = () => (
  <g>
    {/* Rough */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#2D8A4F" />
    {/* Fairway */}
    <path
      d={`M 30 ${VIEW_H - 20} Q 100 ${VIEW_H / 2}, 200 ${VIEW_H / 2 - 20} T ${VIEW_W - 80} 50`}
      stroke="#7DC97D"
      strokeWidth={70}
      fill="none"
      strokeLinecap="round"
    />
    {/* Green */}
    <ellipse cx={VIEW_W - 80} cy={60} rx={50} ry={36} fill="#A7E5A7" />
    {/* Sand bunker */}
    <ellipse cx={180} cy={120} rx={28} ry={18} fill="#F4D58C" />
    {/* Pond */}
    <ellipse cx={130} cy={200} rx={32} ry={14} fill="#3B82F6" />
    {/* Tee */}
    <circle cx={50} cy={VIEW_H - 30} r={6} fill="white" />
    {/* Flag pole */}
    <line
      x1={VIEW_W - 80}
      y1={60}
      x2={VIEW_W - 80}
      y2={20}
      stroke="white"
      strokeWidth={2}
    />
    <polygon
      points={`${VIEW_W - 80},20 ${VIEW_W - 60},28 ${VIEW_W - 80},36`}
      fill="#EF4444"
    />
    {/* Hole */}
    <circle cx={VIEW_W - 80} cy={62} r={4} fill="#1F2937" />
    {/* Ball trajectory dotted line */}
    <path
      d={`M 50 ${VIEW_H - 30} Q 200 -20, ${VIEW_W - 80} 60`}
      stroke="white"
      strokeWidth={1.5}
      strokeDasharray="3 5"
      fill="none"
      opacity={0.6}
    />
  </g>
);

const F1: React.FC = () => (
  <g>
    {/* Asphalt background */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#3F3F46" />
    {/* Track outline */}
    <path
      d={`M 60 ${VIEW_H / 2}
          C 60 60, 160 40, 220 80
          C 280 120, 260 180, 320 200
          C 380 220, ${VIEW_W - 30} 180, ${VIEW_W - 30} 130
          C ${VIEW_W - 30} 80, ${VIEW_W - 100} 50, ${VIEW_W - 160} 80
          C ${VIEW_W - 220} 110, ${VIEW_W - 200} ${VIEW_H - 60}, 220 ${VIEW_H - 60}
          C 100 ${VIEW_H - 60}, 60 ${VIEW_H - 100}, 60 ${VIEW_H / 2} Z`}
      stroke="#1F1F23"
      strokeWidth={28}
      fill="none"
      strokeLinejoin="round"
    />
    <path
      d={`M 60 ${VIEW_H / 2}
          C 60 60, 160 40, 220 80
          C 280 120, 260 180, 320 200
          C 380 220, ${VIEW_W - 30} 180, ${VIEW_W - 30} 130
          C ${VIEW_W - 30} 80, ${VIEW_W - 100} 50, ${VIEW_W - 160} 80
          C ${VIEW_W - 220} 110, ${VIEW_W - 200} ${VIEW_H - 60}, 220 ${VIEW_H - 60}
          C 100 ${VIEW_H - 60}, 60 ${VIEW_H - 100}, 60 ${VIEW_H / 2} Z`}
      stroke="white"
      strokeWidth={1.5}
      fill="none"
      strokeDasharray="6 6"
      opacity={0.7}
    />
    {/* Start/finish line - checkered */}
    {Array.from({ length: 6 }, (_, i) => (
      <rect
        key={i}
        x={50 + (i % 2) * 6}
        y={VIEW_H / 2 - 18 + i * 6}
        width={6}
        height={6}
        fill={i % 2 === 0 ? "white" : "#1F1F23"}
      />
    ))}
    {/* Car */}
    <g transform={`translate(${VIEW_W - 80} 130)`}>
      <rect x={-10} y={-5} width={20} height={10} rx={3} fill="#FFB81C" />
      <rect x={-12} y={-7} width={4} height={3} fill="#1F1F23" />
      <rect x={8} y={-7} width={4} height={3} fill="#1F1F23" />
    </g>
  </g>
);

const Ufc: React.FC = () => (
  <g>
    {/* Black background */}
    <rect x={0} y={0} width={VIEW_W} height={VIEW_H} fill="#0A0A0C" />
    {/* Octagon */}
    <polygon
      points={(() => {
        const cx = VIEW_W / 2;
        const cy = VIEW_H / 2;
        const r = 95;
        const pts: string[] = [];
        for (let i = 0; i < 8; i++) {
          const a = (Math.PI / 4) * i + Math.PI / 8;
          pts.push(`${cx + Math.cos(a) * r},${cy + Math.sin(a) * (r * 0.7)}`);
        }
        return pts.join(" ");
      })()}
      fill="#7A4A1A"
      stroke="#FFB81C"
      strokeWidth={3}
    />
    {/* Inner mat lines */}
    <polygon
      points={(() => {
        const cx = VIEW_W / 2;
        const cy = VIEW_H / 2;
        const r = 70;
        const pts: string[] = [];
        for (let i = 0; i < 8; i++) {
          const a = (Math.PI / 4) * i + Math.PI / 8;
          pts.push(`${cx + Math.cos(a) * r},${cy + Math.sin(a) * (r * 0.7)}`);
        }
        return pts.join(" ");
      })()}
      fill="none"
      stroke="white"
      strokeWidth={1.5}
      opacity={0.4}
    />
    {/* Center logo */}
    <text
      x={VIEW_W / 2}
      y={VIEW_H / 2 + 8}
      fill="white"
      fontSize={22}
      fontWeight={900}
      textAnchor="middle"
      opacity={0.85}
      letterSpacing={2}
    >
      UFC
    </text>
    {/* Two fighter dots */}
    <circle cx={VIEW_W / 2 - 30} cy={VIEW_H / 2} r={6} fill="#EF4444" stroke="white" strokeWidth={2} />
    <circle cx={VIEW_W / 2 + 30} cy={VIEW_H / 2} r={6} fill="#3B82F6" stroke="white" strokeWidth={2} />
  </g>
);

export const SportField: React.FC<SportFieldProps> = ({
  sport,
  width = VIEW_W,
  height = VIEW_H,
  showOverlay = false,
  overlayText,
  showShots,
  showRunners,
  showDriveArrow,
}) => {
  const renderSport = () => {
    switch (sport) {
      case "football":
        return <Football showDriveArrow={showDriveArrow} />;
      case "basketball":
        return <Basketball showShots={showShots} />;
      case "baseball":
        return <Baseball showRunners={showRunners} />;
      case "hockey":
        return <Hockey />;
      case "soccer":
        return <Soccer />;
      case "tennis":
        return <Tennis />;
      case "golf":
        return <Golf />;
      case "f1":
        return <F1 />;
      case "ufc":
        return <Ufc />;
    }
  };

  return (
    <div style={{ position: "relative", width, height }}>
      <svg
        viewBox={`0 0 ${VIEW_W} ${VIEW_H}`}
        width={width}
        height={height}
        preserveAspectRatio="xMidYMid meet"
        style={{ display: "block", borderRadius: 18 }}
      >
        <defs>
          <clipPath id={`clip-${sport}`}>
            <rect x={0} y={0} width={VIEW_W} height={VIEW_H} rx={18} ry={18} />
          </clipPath>
        </defs>
        <g clipPath={`url(#clip-${sport})`}>{renderSport()}</g>
      </svg>
      {showOverlay && overlayText && (
        <div
          style={{
            position: "absolute",
            bottom: 16,
            left: 16,
            background: "#FFB81C",
            color: "#0A0A0C",
            padding: "8px 16px",
            borderRadius: 8,
            fontWeight: 900,
            fontSize: 22,
            letterSpacing: 1,
            fontFamily: "Inter, -apple-system, sans-serif",
          }}
        >
          {overlayText}
        </div>
      )}
    </div>
  );
};

import { Composition } from "remotion";
import { AdSportsTracker } from "./AdSportsTracker";
import { AdShortFormat } from "./AdShortFormat";

const FPS = 30;
const WIDTH = 1080;
const HEIGHT = 1920;

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="AdSportsTracker"
        component={AdSportsTracker}
        durationInFrames={30 * FPS}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
      />
      <Composition
        id="AdShortFormat"
        component={AdShortFormat}
        durationInFrames={15 * FPS}
        fps={FPS}
        width={WIDTH}
        height={HEIGHT}
      />
    </>
  );
};

import { NativeEventEmitter, NativeModules, Platform } from 'react-native';

const EVENT_NAME = 'RSPlayerEvent';
const NativeRSPlayer = NativeModules.RSPlayer;
const rsPlayerEventEmitter = NativeRSPlayer
  ? new NativeEventEmitter(NativeRSPlayer)
  : null;

function getNativeRSPlayer() {
  if (!NativeRSPlayer) {
    throw new Error(
      `RSPlayer native module is not linked for ${Platform.OS}. Rebuild the native app after installing @rsplayer/rsplayer.`
    );
  }

  return NativeRSPlayer;
}

export const RSPlayer = {
  addListener(listener) {
    if (!rsPlayerEventEmitter) {
      return () => {};
    }

    const subscription = rsPlayerEventEmitter.addListener(EVENT_NAME, listener);

    return () => {
      subscription.remove();
    };
  },
  getState: () => getNativeRSPlayer().getState(),
  load: options => getNativeRSPlayer().load(options),
  pause: () => getNativeRSPlayer().pause(),
  play: () => getNativeRSPlayer().play(),
  reset: () => getNativeRSPlayer().reset(),
  seekTo: seconds => getNativeRSPlayer().seekTo(seconds),
  setLoop: loop => getNativeRSPlayer().setLoop(loop),
  setVolume: volume => getNativeRSPlayer().setVolume(volume),
  stop: () => getNativeRSPlayer().stop(),
};

import { AppState } from 'react-native';
import { RSPlayer } from './native';

const DEFAULT_PROGRESS = {
  buffered: 0,
  duration: 0,
  position: 0,
};

const DEFAULT_SNAPSHOT = {
  activeTrack: null,
  buffering: false,
  ended: false,
  playing: false,
  progress: DEFAULT_PROGRESS,
  sessionKey: 0,
  shouldPlay: false,
};

function normalizeError(error) {
  if (error instanceof Error) {
    return error;
  }

  return new Error(
    typeof error === 'string' ? error : JSON.stringify(error)
  );
}

function clampSeekPosition(position, duration) {
  if (duration > 0) {
    return Math.max(0, Math.min(position, duration));
  }

  return Math.max(0, position);
}

function getDefaultTrackDuration(track) {
  return track?.duration && track.duration > 0 ? track.duration : 0;
}

export function createRSPlayerController(options) {
  const player = options.player ?? RSPlayer;
  const getTrackDuration = options.getTrackDuration ?? getDefaultTrackDuration;
  const syncOnAppActive = options.syncOnAppActive ?? true;
  const listeners = new Set();
  let snapshot = DEFAULT_SNAPSHOT;
  let appState = AppState.currentState;
  let removePlayerListener = null;
  let appStateSubscription = null;

  function emit(nextSnapshot) {
    snapshot = nextSnapshot;
    listeners.forEach(listener => listener());
  }

  function updateSnapshot(updater) {
    const next =
      typeof updater === 'function' ? updater(snapshot) : updater;
    emit(next);
  }

  function handlePlaybackError(error) {
    const normalizedError = normalizeError(error);
    options.onError?.(normalizedError);
    updateSnapshot(previous => ({
      ...previous,
      buffering: false,
      ended: false,
      playing: false,
      shouldPlay: false,
    }));
  }

  function runCommand(action) {
    Promise.resolve()
      .then(action)
      .catch(handlePlaybackError);
  }

  function loadNativeTrack(track, shouldPlay) {
    updateSnapshot(previous => ({
      ...previous,
      buffering: shouldPlay,
      ended: false,
      playing: false,
    }));

    runCommand(async () => {
      await player.pause().catch(() => {});
      await player.load(options.getLoadOptions(track, shouldPlay));
    });
  }

  function setTrack(track, shouldPlay) {
    updateSnapshot(previous => ({
      activeTrack: track,
      buffering: shouldPlay,
      ended: false,
      playing: false,
      progress: {
        buffered: 0,
        duration: getTrackDuration(track),
        position: 0,
      },
      sessionKey: previous.sessionKey + 1,
      shouldPlay,
    }));

    loadNativeTrack(track, shouldPlay);
  }

  function handleNativeEvent(event) {
    switch (event.type) {
      case 'load':
        updateSnapshot(previous => {
          const duration =
            event.duration && event.duration > 0
              ? event.duration
              : previous.progress.duration ||
                getTrackDuration(previous.activeTrack);

          return {
            ...previous,
            buffering: previous.shouldPlay && !previous.playing,
            ended: false,
            progress: {
              buffered: event.buffered ?? duration,
              duration,
              position: event.position ?? previous.progress.position,
            },
          };
        });
        break;
      case 'progress':
        updateSnapshot(previous => ({
          ...previous,
          ended: false,
          progress: {
            buffered: event.buffered ?? previous.progress.buffered,
            duration:
              event.duration && event.duration > 0
                ? event.duration
                : previous.progress.duration,
            position: event.position ?? previous.progress.position,
          },
        }));
        break;
      case 'state':
        if (event.state === 'buffering' || event.state === 'loading') {
          updateSnapshot(previous => ({
            ...previous,
            buffering: Boolean(previous.activeTrack && previous.shouldPlay),
            ended: false,
          }));
        } else if (event.state === 'playing') {
          updateSnapshot(previous => ({
            ...previous,
            buffering: false,
            ended: false,
            playing: true,
            shouldPlay: true,
          }));
        } else if (event.state === 'paused' || event.state === 'idle') {
          updateSnapshot(previous => ({
            ...previous,
            buffering: false,
            playing: false,
          }));
        }
        break;
      case 'ended':
        updateSnapshot(previous => {
          if (previous.activeTrack?.repeat) {
            return {
              ...previous,
              buffering: false,
              ended: false,
              playing: previous.shouldPlay,
              progress: {
                ...previous.progress,
                position: 0,
              },
              shouldPlay: true,
            };
          }

          return {
            ...previous,
            buffering: false,
            ended: true,
            playing: false,
            progress: {
              ...previous.progress,
              position: previous.progress.duration,
            },
            shouldPlay: false,
          };
        });
        break;
      case 'error':
        handlePlaybackError(event.message || 'Audio playback error');
        break;
    }
  }

  function syncNativeState() {
    if (!snapshot.activeTrack) {
      return Promise.resolve();
    }

    return player.getState().then(nativeState => {
      updateSnapshot(previous => {
        if (!previous.activeTrack) {
          return previous;
        }

        const playing = nativeState.state === 'playing';
        const buffering =
          nativeState.state === 'buffering' ||
          nativeState.state === 'loading';
        const ended = nativeState.state === 'ended';
        const paused =
          nativeState.state === 'idle' ||
          nativeState.state === 'paused' ||
          ended;

        return {
          ...previous,
          buffering,
          ended,
          playing,
          progress: {
            buffered: nativeState.buffered ?? previous.progress.buffered,
            duration:
              nativeState.duration && nativeState.duration > 0
                ? nativeState.duration
                : previous.progress.duration,
            position: nativeState.position ?? previous.progress.position,
          },
          shouldPlay: playing ? true : paused ? false : previous.shouldPlay,
        };
      });
    });
  }

  function start() {
    if (!removePlayerListener) {
      removePlayerListener = player.addListener(handleNativeEvent);
    }

    if (syncOnAppActive && !appStateSubscription) {
      appStateSubscription = AppState.addEventListener('change', nextState => {
        const previousState = appState;
        appState = nextState;

        if (previousState !== 'active' && nextState === 'active') {
          syncNativeState().catch(handlePlaybackError);
        }
      });
    }
  }

  function dispose() {
    removePlayerListener?.();
    appStateSubscription?.remove();
    removePlayerListener = null;
    appStateSubscription = null;
  }

  const controller = {
    dispose,
    getSnapshot: () => snapshot,
    loadTrack: async track => {
      setTrack(track, false);
    },
    pause: async () => {
      runCommand(() => player.pause());
      updateSnapshot(previous => ({
        ...previous,
        buffering: false,
        playing: false,
        shouldPlay: false,
      }));
    },
    play: async () => {
      const current = snapshot;
      if (!current.activeTrack) {
        return;
      }

      if (current.ended) {
        runCommand(() => player.seekTo(0));
      }

      updateSnapshot(previous => ({
        ...previous,
        buffering: !previous.playing,
        ended: false,
        progress: previous.ended
          ? {
              ...previous.progress,
              position: 0,
            }
          : previous.progress,
        shouldPlay: true,
      }));

      runCommand(() => player.play());
    },
    playTrack: async track => {
      setTrack(track, true);
    },
    reset: async () => {
      runCommand(() => player.reset());
      updateSnapshot(previous => ({
        ...DEFAULT_SNAPSHOT,
        sessionKey: previous.sessionKey + 1,
      }));
    },
    seekBy: async offset => {
      await controller.seekTo(snapshot.progress.position + offset);
    },
    seekTo: async position => {
      if (!snapshot.activeTrack) {
        return;
      }

      const nextPosition = clampSeekPosition(
        position,
        snapshot.progress.duration
      );

      runCommand(() => player.seekTo(nextPosition));
      updateSnapshot(previous => ({
        ...previous,
        ended: false,
        progress: {
          ...previous.progress,
          position: nextPosition,
        },
      }));
    },
    start,
    stop: async () => {
      runCommand(async () => {
        await player.pause();
        await player.seekTo(0);
      });

      updateSnapshot(previous => ({
        ...previous,
        buffering: false,
        ended: false,
        playing: false,
        progress: {
          ...previous.progress,
          position: 0,
        },
        shouldPlay: false,
      }));
    },
    subscribe: listener => {
      listeners.add(listener);

      return () => {
        listeners.delete(listener);
      };
    },
    syncNativeState,
  };

  start();

  return controller;
}

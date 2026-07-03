import React, {
  forwardRef,
  useImperativeHandle,
  useMemo,
  useState,
} from 'react';
import { requireNativeComponent } from 'react-native';

const NativeRSVideo = requireNativeComponent('RSVideoView');

const RSVideo = forwardRef(
  (
    {
      muted = true,
      onBuffer,
      onError,
      onLoad,
      onLoadStart,
      paused = false,
      resizeMode = 'contain',
      source,
      style,
    },
    ref
  ) => {
    const [seekState, setSeekState] = useState({
      request: 0,
      time: 0,
    });

    useImperativeHandle(
      ref,
      () => ({
        seek: seconds => {
          setSeekState(previous => ({
            request: previous.request + 1,
            time: Math.max(0, seconds),
          }));
        },
      }),
      []
    );

    const nativeEvents = useMemo(
      () => ({
        onBuffer: onBuffer
          ? event => {
              onBuffer(event.nativeEvent);
            }
          : undefined,
        onError: onError
          ? event => {
              onError(event.nativeEvent);
            }
          : undefined,
        onLoad: onLoad
          ? event => {
              onLoad(event.nativeEvent);
            }
          : undefined,
        onLoadStart: onLoadStart
          ? () => {
              onLoadStart();
            }
          : undefined,
      }),
      [onBuffer, onError, onLoad, onLoadStart]
    );

    return React.createElement(NativeRSVideo, {
      muted,
      paused,
      resizeMode,
      seekRequest: seekState.request,
      seekTime: seekState.time,
      sourceUri: source.uri,
      style,
      ...nativeEvents,
    });
  }
);

RSVideo.displayName = 'RSVideo';

export { RSVideo };

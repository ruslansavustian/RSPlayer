# @rsplayer/rsplayer

Native audio player and video-only view for React Native.

`RSPlayer` is a small native audio module for streaming audio with background
playback and system media controls. The package also exports `RSVideo`, a
video-only native view for muted visual clips that should not compete with the
active audio session.

## Support

`rsplayer` is free to use.

If this package helped you or saved you time, you can support the project here:

**PayPal:** ruslan.elfbot@gmail.com

Thank you for supporting the first versions of `rsplayer`.

## Install

```sh
npm install @rsplayer/rsplayer
```

Or install directly from GitHub:

```sh
npm install github:ruslansavustian/RSPlayer
```

For iOS:

```sh
cd ios && pod install
```

## Changelog

### 0.3.0

- Added `RSVideo`, a native video-only view for muted timeline/session clips.
  Use it when video is only visual context and audio is handled separately by
  `RSPlayer`.
- `RSVideo` is designed for exercise timelines, guided sessions, previews, and
  similar screens where a muted clip should play behind or beside an active
  soundtrack, voice-over, or cue flow.
- Android `RSVideo` disables ExoPlayer audio tracks through `DefaultTrackSelector`
  and calls `setAudioAttributes(..., false)`, so muted visual clips do not request
  Android audio focus from the active `RSPlayer` session.
- iOS `RSVideo` uses `AVPlayerLayer`, removes audible media selection, and
  disables `AVPlayerItem` audio tracks so visual clips do not interfere with the
  app audio session.
- `RSVideo` supports the focused subset needed for visual playback: `source`,
  `paused`, `muted`, `resizeMode`, load/buffer/error callbacks, and
  `ref.current?.seek(seconds)`.
- Android `RSVideo` forces a second `PlayerView` layout pass when resize mode or
  video size changes, matching `react-native-video` cover behavior and avoiding
  vertically shifted crops in full-screen timeline views.

### 0.2.3

- Fixed Android cue playback stealing audio focus from the main player. `playCue`
  now keeps the active soundtrack/session alive while short voice prompts play on
  the secondary cue player.
- Fixed Android seeking for progressive MP3/audio streams that ExoPlayer
  previously reported as non-seekable. Android media sources now enable
  constant-bitrate extractor seeking, so `seekTo` and controller `seekBy`
  can jump to the requested position instead of restarting from the beginning.
- Improved managed controller `seekBy` accuracy by reading the current native
  player state before applying the relative seek offset.
- Android progress is now emitted after ExoPlayer reports the seek position
  change, avoiding stale progress immediately after `seekTo`.

## Requirements

- React Native `>= 0.75`
- iOS `>= 15.1`
- Android `minSdk >= 24`
- Android `compileSdk >= 35` recommended

## Dependency Model

The npm package intentionally has no regular JavaScript dependencies.

Peer dependencies:

```json
{
  "react": "*",
  "react-native": ">=0.75"
}
```

Native dependencies are declared where React Native expects them:

- Android Gradle: `react-android`, `androidx.core`, and AndroidX Media3 ExoPlayer/session/UI modules
- iOS CocoaPods: `React-Core`

This is why npm can show `0 Dependencies` while the native Android and iOS pieces are still installed during the normal React Native build.

## Usage

```ts
import { RSPlayer, RSVideo } from '@rsplayer/rsplayer';

RSPlayer.addListener(event => {
  console.log(event);
});

await RSPlayer.load({
  uri: 'https://example.com/audio.mp3',
  title: 'Story Title',
  artist: 'Visionaria',
  artwork: 'https://example.com/artwork.png',
  autoPlay: true,
});

await RSPlayer.pause();
await RSPlayer.play();
await RSPlayer.seekTo(120);
```

## Video-Only Playback

Use `RSVideo` for muted video clips when your app already has a separate audio
session, soundtrack, voice-over, or cue system.

This component exists because a normal video player can still touch platform
audio systems even when the video is muted. On Android that can request or change
audio focus; on iOS the video item can still expose audible media tracks to the
audio session. In guided sessions this can interrupt an active `RSPlayer`
soundtrack or voice-over flow.

`RSVideo` is not a general replacement for a full video player. It intentionally
does not provide video sound, system media controls, fullscreen, background
video, or picture-in-picture. Use it for visual-only clips where audio belongs to
`RSPlayer`.

```tsx
import { RSVideo } from '@rsplayer/rsplayer';

function ExerciseSegmentVideo({ activeSegment, isPlaying, videoControls }) {
  return (
    <RSVideo
      key={activeSegment.id}
      muted
      onBuffer={videoControls.onVideoBuffer}
      onError={videoControls.onVideoError}
      onLoad={videoControls.onVideoLoad}
      onLoadStart={videoControls.onVideoLoadStart}
      paused={!isPlaying}
      ref={videoControls.videoRef}
      resizeMode="cover"
      source={{ uri: activeSegment.playbackUrl }}
      style={{ height: 240, width: '100%' }}
    />
  );
}
```

### RSVideo Props

`RSVideo` accepts a focused visual-playback API:

```ts
type RSVideoProps = {
  source: { uri: string };
  paused?: boolean;
  muted?: boolean;
  resizeMode?: 'contain' | 'cover' | 'stretch';
  style?: StyleProp<ViewStyle>;
  onLoadStart?: () => void;
  onLoad?: (event: {
    duration: number;
    naturalSize?: {
      width: number;
      height: number;
    };
  }) => void;
  onBuffer?: (event: { isBuffering: boolean }) => void;
  onError?: (event: {
    error?: {
      error?: string;
      errorString?: string;
      localizedDescription?: string;
      localizedFailureReason?: string;
    };
  }) => void;
};
```

- `source`: required video URI, for example `source={{ uri: clipUrl }}`.
- `paused`: controls playback. Pass `true` to pause and `false` to play.
  Default is `false`.
- `muted`: keeps video silent. Default is `true`. `RSVideo` is built for
  visual-only playback, so keep this enabled when `RSPlayer` owns the audio.
- `resizeMode`: controls how the video fits the view. Use `cover` for full-screen
  timeline backgrounds, `contain` to show the whole video, or `stretch` to fill
  without preserving aspect ratio. Default is `contain`.
- `style`: React Native view style. For full-screen video, use an absolute-fill
  style or a parent with a fixed size.
- `onLoadStart`: fires when a new video source starts loading.
- `onLoad`: fires when metadata is ready and includes `duration` in seconds plus
  optional `naturalSize`.
- `onBuffer`: fires with `{ isBuffering }` whenever native buffering state
  changes.
- `onError`: fires with native error details if playback fails.

Use a ref when the visual timeline must jump to a specific point:

```tsx
const videoRef = useRef<RSVideoRef | null>(null);

videoRef.current?.seek(12.5);

<RSVideo
  ref={videoRef}
  muted
  paused={!isPlaying}
  resizeMode="cover"
  source={{ uri: activeSegment.playbackUrl }}
  style={StyleSheet.absoluteFill}
/>;
```

## Cue Playback

Use `playCue` for short one-shot secondary sounds such as coaching prompts,
navigation cues, or voice instructions that should play over the main track.

Cue playback uses a separate native player, does not replace the main track, and
never publishes system media controls, lock-screen metadata, or a media
notification. The returned promise resolves when the cue finishes, so apps can
temporarily lower the main player volume and restore it afterward.

Starting a new cue replaces the active cue. To play multiple cues in order,
await each `playCue` call before starting the next one.

```ts
await RSPlayer.setVolume(0.25);

try {
  await RSPlayer.playCue({
    uri: 'https://example.com/cues/stand-up.mp3',
    volume: 1,
  });
} finally {
  await RSPlayer.setVolume(1);
}
```

Call `stopCue()` to cancel the active cue. This resolves the active cue promise.

## Managed Controller

For apps that need a reusable playback state layer, `createRSPlayerController` wraps the native module and translates native events into a small subscribable snapshot.

```ts
import { createRSPlayerController } from '@rsplayer/rsplayer';

type Track = {
  artist?: string;
  artwork?: string;
  duration?: number;
  title?: string;
  uri: string;
};

const player = createRSPlayerController<Track>({
  getLoadOptions: (track, autoPlay) => ({
    artist: track.artist,
    artwork: track.artwork,
    autoPlay,
    showSystemControls: true,
    title: track.title,
    uri: track.uri,
  }),
  getTrackDuration: track => track?.duration ?? 0,
  onError: error => {
    console.error(error);
  },
});

const unsubscribe = player.subscribe(() => {
  console.log(player.getSnapshot());
});

await player.playTrack(track);
await player.seekBy(15);
await player.pause();

unsubscribe();
```

## API

### `load(options)`

Loads an audio URL.

```ts
type RSPlayerLoadOptions = {
  uri: string;
  title?: string;
  artist?: string;
  artwork?: string;
  autoPlay?: boolean;
  headers?: Record<string, string>;
  loop?: boolean;
  showSystemControls?: boolean;
  volume?: number;
};
```

```ts
type RSPlayerCueOptions = {
  uri: string;
  headers?: Record<string, string>;
  volume?: number;
};
```

`showSystemControls` defaults to `true`. Set it to `false` for in-app ambient audio that should not create lock-screen, notification, or remote-control media UI.

### Methods

Audio methods:

- `RSPlayer.play()`
- `RSPlayer.pause()`
- `RSPlayer.playCue(options)`
- `RSPlayer.stop()`
- `RSPlayer.stopCue()`
- `RSPlayer.reset()`
- `RSPlayer.seekTo(seconds)`
- `RSPlayer.setLoop(loop)`
- `RSPlayer.setVolume(volume)`
- `RSPlayer.getState()`
- `RSPlayer.addListener(listener)`

Video-only component:

- `<RSVideo />`
- `RSVideoRef.seek(seconds)`

### Events

- `state`: `idle`, `loading`, `buffering`, `paused`, `playing`, `ended`
- `load`: initial duration/progress data
- `progress`: position, duration, buffered
- `ended`
- `error`

## Background Playback Setup

### iOS

Add background audio capability to the app that installs this package.

In Xcode:

Target -> Signing & Capabilities -> `+ Capability` -> Background Modes -> check `Audio, AirPlay, and Picture in Picture`.

Or add this to `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### Android

The library manifest contributes the media playback service and base permissions:

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

On Android 13+, the host app should request notification permission at runtime if it wants the media notification to be visible.

## Notes

- Android uses Media3 ExoPlayer and `MediaSessionService`.
- iOS uses `AVPlayer`, `AVAudioSession`, `MPNowPlayingInfoCenter`, and `MPRemoteCommandCenter`.
- The package handles playback only. App-level queues, mini-player UI, analytics, and saved progress should stay in your app.

# @rsplayer/rsplayer

Easy native audio player for React Native.

`RSPlayer` is a small native audio module for streaming audio with background playback and system media controls.

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

- Android Gradle: `react-android`, `androidx.core`, and AndroidX Media3 ExoPlayer/session modules
- iOS CocoaPods: `React-Core`

This is why npm can show `0 Dependencies` while the native Android and iOS pieces are still installed during the normal React Native build.

## Usage

```ts
import { RSPlayer } from '@rsplayer/rsplayer';

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

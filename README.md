# react-native-rsplayer

Easy native audio player for React Native.

`RSPlayer` is a small native audio module for streaming audio with background playback and system media controls.

## Install

```sh
npm install react-native-rsplayer
```

Or install directly from GitHub:

```sh
npm install github:ruslansavustian/RSPlayer
```

For iOS:

```sh
cd ios && pod install
```

## Usage

```ts
import { RSPlayer } from 'react-native-rsplayer';

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

## Managed Controller

For apps that need a reusable playback state layer, `createRSPlayerController` wraps the native module and translates native events into a small subscribable snapshot.

```ts
import { createRSPlayerController } from 'react-native-rsplayer';

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

`showSystemControls` defaults to `true`. Set it to `false` for in-app ambient audio that should not create lock-screen, notification, or remote-control media UI.

### Methods

- `RSPlayer.play()`
- `RSPlayer.pause()`
- `RSPlayer.stop()`
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

export type RSPlayerLoadOptions = {
  artist?: string;
  artwork?: string;
  autoPlay?: boolean;
  headers?: Record<string, string>;
  loop?: boolean;
  showSystemControls?: boolean;
  title?: string;
  uri: string;
  volume?: number;
};

export type RSPlayerState =
  | 'buffering'
  | 'ended'
  | 'idle'
  | 'loading'
  | 'paused'
  | 'playing';

export type RSPlayerEvent =
  | {
      state: RSPlayerState;
      type: 'state';
    }
  | {
      buffered?: number;
      duration?: number;
      position?: number;
      type: 'load' | 'progress';
    }
  | {
      type: 'ended';
    }
  | {
      message?: string;
      type: 'error';
    };

export type RSPlayerSnapshot = {
  buffered: number;
  duration: number;
  position: number;
  state: RSPlayerState;
};

export type RSPlayerControllerProgress = {
  buffered: number;
  duration: number;
  position: number;
};

export type RSPlayerControllerSnapshot<Track = unknown> = {
  activeTrack: Track | null;
  buffering: boolean;
  ended: boolean;
  playing: boolean;
  progress: RSPlayerControllerProgress;
  sessionKey: number;
  shouldPlay: boolean;
};

export type RSPlayerModule = {
  addListener(listener: (event: RSPlayerEvent) => void): () => void;
  getState(): Promise<RSPlayerSnapshot>;
  load(options: RSPlayerLoadOptions): Promise<void>;
  pause(): Promise<void>;
  play(): Promise<void>;
  reset(): Promise<void>;
  seekTo(seconds: number): Promise<void>;
  setLoop(loop: boolean): Promise<void>;
  setVolume(volume: number): Promise<void>;
  stop(): Promise<void>;
};

export type RSPlayerControllerOptions<Track = unknown> = {
  getLoadOptions(
    track: Track,
    autoPlay: boolean
  ): RSPlayerLoadOptions;
  getTrackDuration?(track: Track | null): number;
  onError?(error: Error): void;
  player?: RSPlayerModule;
  syncOnAppActive?: boolean;
};

export type RSPlayerController<Track = unknown> = {
  dispose(): void;
  getSnapshot(): RSPlayerControllerSnapshot<Track>;
  loadTrack(track: Track): Promise<void>;
  pause(): Promise<void>;
  play(): Promise<void>;
  playTrack(track: Track): Promise<void>;
  reset(): Promise<void>;
  seekBy(offset: number): Promise<void>;
  seekTo(position: number): Promise<void>;
  start(): void;
  stop(): Promise<void>;
  subscribe(listener: () => void): () => void;
  syncNativeState(): Promise<void>;
};

export const RSPlayer: {
  addListener(listener: (event: RSPlayerEvent) => void): () => void;
  getState(): Promise<RSPlayerSnapshot>;
  load(options: RSPlayerLoadOptions): Promise<void>;
  pause(): Promise<void>;
  play(): Promise<void>;
  reset(): Promise<void>;
  seekTo(seconds: number): Promise<void>;
  setLoop(loop: boolean): Promise<void>;
  setVolume(volume: number): Promise<void>;
  stop(): Promise<void>;
};

export function createRSPlayerController<Track = unknown>(
  options: RSPlayerControllerOptions<Track>
): RSPlayerController<Track>;

export type RSPlayerLoadOptions = {
  artist?: string;
  artwork?: string;
  autoPlay?: boolean;
  headers?: Record<string, string>;
  loop?: boolean;
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

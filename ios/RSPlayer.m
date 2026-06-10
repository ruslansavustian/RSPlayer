#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <UIKit/UIKit.h>

static NSString *const RSPlayerEventName = @"RSPlayerEvent";
static void *RSPlayerItemStatusContext = &RSPlayerItemStatusContext;
static void *RSPlayerCueItemStatusContext = &RSPlayerCueItemStatusContext;
static void *RSPlayerTimeControlContext = &RSPlayerTimeControlContext;

@interface RSPlayer : RCTEventEmitter <RCTBridgeModule>
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) AVPlayer *cuePlayer;
@property (nonatomic, strong) AVPlayerItem *cuePlayerItem;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, assign) BOOL hasListeners;
@property (nonatomic, assign) BOOL isLooping;
@property (nonatomic, assign) BOOL observingItemStatus;
@property (nonatomic, assign) BOOL observingCueItemStatus;
@property (nonatomic, assign) BOOL observingTimeControlStatus;
@property (nonatomic, assign) BOOL remoteCommandsConfigured;
@property (nonatomic, assign) BOOL showSystemControls;
@property (nonatomic, assign) BOOL shouldPublishNowPlaying;
@property (nonatomic, copy) RCTPromiseResolveBlock cueResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock cueReject;
@property (nonatomic, copy) NSString *nowPlayingTitle;
@property (nonatomic, copy) NSString *nowPlayingArtist;
@property (nonatomic, copy) NSString *nowPlayingArtworkURL;
@property (nonatomic, strong) MPMediaItemArtwork *nowPlayingArtwork;
@property (nonatomic, strong) NSURLSessionDataTask *artworkTask;
@end

@implementation RSPlayer

RCT_EXPORT_MODULE(RSPlayer)

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[RSPlayerEventName];
}

- (void)startObserving
{
  self.hasListeners = YES;
}

- (void)stopObserving
{
  self.hasListeners = NO;
}

RCT_EXPORT_METHOD(load:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    NSString *uri = [options[@"uri"] isKindOfClass:[NSString class]] ? options[@"uri"] : nil;
    uri = [uri stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (uri.length == 0) {
      reject(@"rsplayer_error", @"Audio URI is empty", nil);
      return;
    }

    NSURL *url = [NSURL URLWithString:uri];
    if (!url) {
      reject(@"rsplayer_error", @"Audio URI is invalid", nil);
      return;
    }

    BOOL autoPlay = [self boolValue:options[@"autoPlay"] defaultValue:NO];
    self.showSystemControls = [self boolValue:options[@"showSystemControls"] defaultValue:YES];
    self.shouldPublishNowPlaying = autoPlay && self.showSystemControls;
    [self activateAudioSession];
    if (autoPlay && self.showSystemControls) {
      [self configureRemoteCommands];
    } else if (!self.showSystemControls) {
      [self teardownRemoteCommands];
      [self clearNowPlayingInfo];
    }
    [self removeCurrentItemObservers];
    [self removeTimeObserver];

    NSDictionary *headers =
      [options[@"headers"] isKindOfClass:[NSDictionary class]] ? options[@"headers"] : nil;
    NSDictionary *assetOptions = headers ? @{@"AVURLAssetHTTPHeaderFieldsKey": headers} : nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:assetOptions];
    self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
    self.isLooping = [self boolValue:options[@"loop"] defaultValue:NO];

    [self.playerItem addObserver:self
                      forKeyPath:@"status"
                         options:NSKeyValueObservingOptionNew
                         context:RSPlayerItemStatusContext];
    self.observingItemStatus = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePlaybackEnded:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:self.playerItem];

    AVPlayer *activePlayer = [self getOrCreatePlayer];
    activePlayer.volume = [self doubleValue:options[@"volume"] defaultValue:1.0];
    [activePlayer replaceCurrentItemWithPlayerItem:self.playerItem];
    if (self.showSystemControls) {
      [self configureNowPlayingWithOptions:options];
    } else {
      [self clearNowPlayingInfo];
    }

    [self startProgressUpdates];
    [self emitState:@"loading"];

    if (autoPlay) {
      [activePlayer play];
      if (self.showSystemControls) {
        [self updateNowPlayingInfo];
      }
    }

    resolve(nil);
  });
}

RCT_EXPORT_METHOD(play:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self activateAudioSession];
    if (self.showSystemControls) {
      [self configureRemoteCommands];
      self.shouldPublishNowPlaying = YES;
    } else {
      [self teardownRemoteCommands];
      [self clearNowPlayingInfo];
    }
    [[self getOrCreatePlayer] play];
    [self startProgressUpdates];
    if (self.showSystemControls) {
      [self updateNowPlayingInfo];
    }
    resolve(nil);
  });
}

RCT_EXPORT_METHOD(playCue:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    NSString *uri = [options[@"uri"] isKindOfClass:[NSString class]] ? options[@"uri"] : nil;
    uri = [uri stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (uri.length == 0) {
      reject(@"rsplayer_cue_error", @"Cue URI is empty", nil);
      return;
    }

    NSURL *url = [NSURL URLWithString:uri];
    if (!url) {
      reject(@"rsplayer_cue_error", @"Cue URI is invalid", nil);
      return;
    }

    [self activateAudioSession];
    [self resolveCueAndRelease];

    NSDictionary *headers =
      [options[@"headers"] isKindOfClass:[NSDictionary class]] ? options[@"headers"] : nil;
    NSDictionary *assetOptions = headers ? @{@"AVURLAssetHTTPHeaderFieldsKey": headers} : nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:assetOptions];
    self.cuePlayerItem = [AVPlayerItem playerItemWithAsset:asset];
    self.cueResolve = resolve;
    self.cueReject = reject;

    [self.cuePlayerItem addObserver:self
                         forKeyPath:@"status"
                            options:NSKeyValueObservingOptionNew
                            context:RSPlayerCueItemStatusContext];
    self.observingCueItemStatus = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleCuePlaybackEnded:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:self.cuePlayerItem];

    AVPlayer *activeCuePlayer = [self getOrCreateCuePlayer];
    double volume = [self doubleValue:options[@"volume"] defaultValue:1.0];
    activeCuePlayer.volume = MIN(MAX(volume, 0), 1);
    [activeCuePlayer replaceCurrentItemWithPlayerItem:self.cuePlayerItem];
    [activeCuePlayer play];
  });
}

RCT_EXPORT_METHOD(pause:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.player pause];
    [self emitState:@"paused"];
    [self emitProgress];
    [self updateNowPlayingInfo];
    resolve(nil);
  });
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self.player pause];
    [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self emitState:@"paused"];
    [self emitProgress];
    [self updateNowPlayingInfo];
    resolve(nil);
  });
}

RCT_EXPORT_METHOD(stopCue:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self resolveCueAndRelease];
    resolve(nil);
  });
}

RCT_EXPORT_METHOD(reset:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self releasePlayer];
    [self emitState:@"idle"];
    resolve(nil);
  });
}

RCT_EXPORT_METHOD(seekTo:(double)seconds
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self seekToSeconds:seconds completion:^{
      resolve(nil);
    }];
  });
}

RCT_EXPORT_METHOD(setVolume:(double)volume
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    self.player.volume = MIN(MAX(volume, 0), 1);
    resolve(nil);
  });
}

RCT_EXPORT_METHOD(setLoop:(BOOL)loop
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    self.isLooping = loop;
    resolve(nil);
  });
}

RCT_EXPORT_METHOD(getState:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
  dispatch_async(dispatch_get_main_queue(), ^{
    resolve(@{
      @"state": [self currentState],
      @"position": @([self seconds:self.player.currentTime]),
      @"duration": @([self seconds:self.player.currentItem.duration]),
      @"buffered": @([self bufferedSeconds:self.player.currentItem])
    });
  });
}

- (void)dealloc
{
  [self releaseCuePlayer];
  [self releasePlayer];
  [self teardownRemoteCommands];
}

- (AVPlayer *)getOrCreatePlayer
{
  if (self.player) {
    return self.player;
  }

  self.player = [AVPlayer new];
  [self.player addObserver:self
                forKeyPath:@"timeControlStatus"
                   options:NSKeyValueObservingOptionNew
                   context:RSPlayerTimeControlContext];
  self.observingTimeControlStatus = YES;

  return self.player;
}

- (AVPlayer *)getOrCreateCuePlayer
{
  if (self.cuePlayer) {
    return self.cuePlayer;
  }

  self.cuePlayer = [AVPlayer new];
  return self.cuePlayer;
}

- (void)activateAudioSession
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:AVAudioSessionCategoryOptionAllowAirPlay
                 error:nil];
  [session setActive:YES error:nil];
}

- (void)configureRemoteCommands
{
  if (self.remoteCommandsConfigured) {
    return;
  }

  MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
  commandCenter.playCommand.enabled = YES;
  commandCenter.pauseCommand.enabled = YES;
  commandCenter.togglePlayPauseCommand.enabled = YES;
  commandCenter.stopCommand.enabled = YES;
  commandCenter.skipForwardCommand.enabled = YES;
  commandCenter.skipBackwardCommand.enabled = YES;
  commandCenter.changePlaybackPositionCommand.enabled = YES;
  commandCenter.nextTrackCommand.enabled = NO;
  commandCenter.previousTrackCommand.enabled = NO;
  commandCenter.skipForwardCommand.preferredIntervals = @[@15];
  commandCenter.skipBackwardCommand.preferredIntervals = @[@15];

  [commandCenter.playCommand addTarget:self action:@selector(handleRemotePlayCommand:)];
  [commandCenter.pauseCommand addTarget:self action:@selector(handleRemotePauseCommand:)];
  [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(handleRemoteToggleCommand:)];
  [commandCenter.stopCommand addTarget:self action:@selector(handleRemoteStopCommand:)];
  [commandCenter.skipForwardCommand addTarget:self action:@selector(handleRemoteSkipForwardCommand:)];
  [commandCenter.skipBackwardCommand addTarget:self action:@selector(handleRemoteSkipBackwardCommand:)];
  [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(handleRemoteChangePositionCommand:)];

  [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
  self.remoteCommandsConfigured = YES;
}

- (void)teardownRemoteCommands
{
  if (!self.remoteCommandsConfigured) {
    return;
  }

  MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
  [commandCenter.playCommand removeTarget:self];
  [commandCenter.pauseCommand removeTarget:self];
  [commandCenter.togglePlayPauseCommand removeTarget:self];
  [commandCenter.stopCommand removeTarget:self];
  [commandCenter.skipForwardCommand removeTarget:self];
  [commandCenter.skipBackwardCommand removeTarget:self];
  [commandCenter.changePlaybackPositionCommand removeTarget:self];

  [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
  self.remoteCommandsConfigured = NO;
}

- (MPRemoteCommandHandlerStatus)handleRemotePlayCommand:(__unused MPRemoteCommandEvent *)event
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.player.currentItem) {
      return;
    }

    [self activateAudioSession];
    [self.player play];
    [self startProgressUpdates];
    [self emitState:[self currentState]];
    [self emitProgress];
    [self updateNowPlayingInfo];
  });

  return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemotePauseCommand:(__unused MPRemoteCommandEvent *)event
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.player.currentItem) {
      return;
    }

    [self.player pause];
    [self emitState:@"paused"];
    [self emitProgress];
    [self updateNowPlayingInfo];
  });

  return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemoteToggleCommand:(__unused MPRemoteCommandEvent *)event
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.player.currentItem) {
      return;
    }

    if ([self.currentState isEqualToString:@"playing"]) {
      [self.player pause];
    } else {
      [self activateAudioSession];
      [self.player play];
      [self startProgressUpdates];
    }

    [self emitState:[self currentState]];
    [self emitProgress];
    [self updateNowPlayingInfo];
  });

  return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemoteStopCommand:(__unused MPRemoteCommandEvent *)event
{
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!self.player.currentItem) {
      return;
    }

    [self.player pause];
    [self seekToSeconds:0 completion:nil];
    [self emitState:@"paused"];
  });

  return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemoteSkipForwardCommand:(__unused MPRemoteCommandEvent *)event
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self skipBySeconds:15];
  });

  return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemoteSkipBackwardCommand:(__unused MPRemoteCommandEvent *)event
{
  dispatch_async(dispatch_get_main_queue(), ^{
    [self skipBySeconds:-15];
  });

  return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus)handleRemoteChangePositionCommand:(MPRemoteCommandEvent *)event
{
  if (![event isKindOfClass:[MPChangePlaybackPositionCommandEvent class]]) {
    return MPRemoteCommandHandlerStatusCommandFailed;
  }

  MPChangePlaybackPositionCommandEvent *positionEvent =
    (MPChangePlaybackPositionCommandEvent *)event;

  dispatch_async(dispatch_get_main_queue(), ^{
    [self seekToSeconds:positionEvent.positionTime completion:nil];
  });

  return MPRemoteCommandHandlerStatusSuccess;
}

- (void)skipBySeconds:(double)seconds
{
  if (!self.player.currentItem) {
    return;
  }

  double current = [self seconds:self.player.currentTime];
  double duration = [self seconds:self.player.currentItem.duration];
  double nextPosition = MAX(current + seconds, 0);

  if (duration > 0) {
    nextPosition = MIN(nextPosition, duration);
  }

  [self seekToSeconds:nextPosition completion:nil];
}

- (void)seekToSeconds:(double)seconds completion:(void (^)(void))completion
{
  AVPlayer *activePlayer = self.player;
  if (!activePlayer.currentItem) {
    if (completion) {
      completion();
    }
    return;
  }

  CMTime time = CMTimeMakeWithSeconds(MAX(seconds, 0), NSEC_PER_SEC);
  [activePlayer seekToTime:time
           toleranceBefore:kCMTimeZero
            toleranceAfter:kCMTimeZero
         completionHandler:^(__unused BOOL finished) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self emitProgress];
      [self updateNowPlayingInfo];
      if (completion) {
        completion();
      }
    });
  }];
}

- (void)configureNowPlayingWithOptions:(NSDictionary *)options
{
  self.nowPlayingTitle =
    [options[@"title"] isKindOfClass:[NSString class]] ? options[@"title"] : nil;
  self.nowPlayingArtist =
    [options[@"artist"] isKindOfClass:[NSString class]] ? options[@"artist"] : nil;

  NSString *artworkURL =
    [options[@"artwork"] isKindOfClass:[NSString class]] ? options[@"artwork"] : nil;
  [self loadNowPlayingArtworkFromURLString:artworkURL];
  [self updateNowPlayingInfo];
}

- (void)loadNowPlayingArtworkFromURLString:(NSString *)urlString
{
  [self.artworkTask cancel];
  self.artworkTask = nil;
  self.nowPlayingArtwork = nil;
  self.nowPlayingArtworkURL = urlString;

  if (urlString.length == 0) {
    return;
  }

  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) {
    return;
  }

  NSString *expectedURL = [urlString copy];
  __weak typeof(self) weakSelf = self;
  self.artworkTask =
    [[NSURLSession sharedSession] dataTaskWithURL:url
                                completionHandler:^(NSData *data,
                                                    __unused NSURLResponse *response,
                                                    NSError *error) {
    if (error || data.length == 0) {
      return;
    }

    UIImage *image = [UIImage imageWithData:data];
    if (!image) {
      return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || ![strongSelf.nowPlayingArtworkURL isEqualToString:expectedURL]) {
        return;
      }

      strongSelf.nowPlayingArtwork =
        [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size
                                        requestHandler:^UIImage * _Nonnull(__unused CGSize size) {
          return image;
        }];
      [strongSelf updateNowPlayingInfo];
    });
  }];
  [self.artworkTask resume];
}

- (void)updateNowPlayingInfo
{
  if (!self.player.currentItem && self.nowPlayingTitle.length == 0) {
    return;
  }
  if (!self.shouldPublishNowPlaying) {
    return;
  }

  NSMutableDictionary *info = [NSMutableDictionary dictionary];

  if (self.nowPlayingTitle.length > 0) {
    info[MPMediaItemPropertyTitle] = self.nowPlayingTitle;
  }
  if (self.nowPlayingArtist.length > 0) {
    info[MPMediaItemPropertyArtist] = self.nowPlayingArtist;
  }

  double duration = [self seconds:self.player.currentItem.duration];
  if (duration > 0) {
    info[MPMediaItemPropertyPlaybackDuration] = @(duration);
  }

  info[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
    @([self seconds:self.player.currentTime]);
  info[MPNowPlayingInfoPropertyPlaybackRate] =
    @([[self currentState] isEqualToString:@"playing"] ? self.player.rate : 0);
  info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = @1;
  info[MPNowPlayingInfoPropertyMediaType] = @(MPNowPlayingInfoMediaTypeAudio);

  if (self.nowPlayingArtwork) {
    info[MPMediaItemPropertyArtwork] = self.nowPlayingArtwork;
  }

  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
  [self updateNowPlayingPlaybackState];
}

- (void)updateNowPlayingPlaybackState
{
  if (@available(iOS 13.0, *)) {
    NSString *state = [self currentState];
    MPNowPlayingPlaybackState playbackState = MPNowPlayingPlaybackStateStopped;

    if ([state isEqualToString:@"playing"]) {
      playbackState = MPNowPlayingPlaybackStatePlaying;
    } else if ([state isEqualToString:@"paused"] || [state isEqualToString:@"buffering"]) {
      playbackState = MPNowPlayingPlaybackStatePaused;
    }

    [MPNowPlayingInfoCenter defaultCenter].playbackState = playbackState;
  }
}

- (void)clearNowPlayingInfo
{
  [self.artworkTask cancel];
  self.artworkTask = nil;
  self.nowPlayingTitle = nil;
  self.nowPlayingArtist = nil;
  self.nowPlayingArtworkURL = nil;
  self.nowPlayingArtwork = nil;
  self.shouldPublishNowPlaying = NO;
  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;

  if (@available(iOS 13.0, *)) {
    [MPNowPlayingInfoCenter defaultCenter].playbackState = MPNowPlayingPlaybackStateStopped;
  }
}

- (void)releasePlayer
{
  [self removeTimeObserver];
  [self removeCurrentItemObservers];
  [self resolveCueAndRelease];

  if (self.observingTimeControlStatus) {
    [self.player removeObserver:self
                     forKeyPath:@"timeControlStatus"
                        context:RSPlayerTimeControlContext];
    self.observingTimeControlStatus = NO;
  }

  [self.player pause];
  [self.player replaceCurrentItemWithPlayerItem:nil];
  self.player = nil;
  self.playerItem = nil;
  [self clearNowPlayingInfo];
  [self teardownRemoteCommands];
  [[AVAudioSession sharedInstance] setActive:NO
                                 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                       error:nil];
}

- (void)releaseCuePlayer
{
  [self removeCueItemObservers];
  [self.cuePlayer pause];
  [self.cuePlayer replaceCurrentItemWithPlayerItem:nil];
  self.cuePlayer = nil;
  self.cuePlayerItem = nil;
  self.cueResolve = nil;
  self.cueReject = nil;
}

- (void)resolveCueAndRelease
{
  RCTPromiseResolveBlock resolve = self.cueResolve;
  [self releaseCuePlayer];
  if (resolve) {
    resolve(nil);
  }
}

- (void)rejectCueAndRelease:(NSString *)message error:(NSError *)error
{
  RCTPromiseRejectBlock reject = self.cueReject;
  [self releaseCuePlayer];
  if (reject) {
    reject(@"rsplayer_cue_error", message ?: @"Cue playback error", error);
  }
}

- (void)removeCurrentItemObservers
{
  if (self.playerItem) {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:self.playerItem];
    if (self.observingItemStatus) {
      [self.playerItem removeObserver:self
                           forKeyPath:@"status"
                              context:RSPlayerItemStatusContext];
      self.observingItemStatus = NO;
    }
  }
}

- (void)removeCueItemObservers
{
  if (self.cuePlayerItem) {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:self.cuePlayerItem];
    if (self.observingCueItemStatus) {
      [self.cuePlayerItem removeObserver:self
                              forKeyPath:@"status"
                                 context:RSPlayerCueItemStatusContext];
      self.observingCueItemStatus = NO;
    }
  }
}

- (void)startProgressUpdates
{
  AVPlayer *activePlayer = [self getOrCreatePlayer];
  if (self.timeObserver) {
    return;
  }

  __weak typeof(self) weakSelf = self;
  self.timeObserver =
    [activePlayer addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(0.25, NSEC_PER_SEC)
                                               queue:dispatch_get_main_queue()
                                          usingBlock:^(__unused CMTime time) {
    [weakSelf emitProgress];
  }];
}

- (void)removeTimeObserver
{
  if (self.timeObserver && self.player) {
    [self.player removeTimeObserver:self.timeObserver];
  }
  self.timeObserver = nil;
}

- (void)handlePlaybackEnded:(NSNotification *)notification
{
  if (self.isLooping) {
    [self.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    [self.player play];
    [self updateNowPlayingInfo];
    return;
  }

  [self emitProgress];
  [self emitEvent:@"ended"];
  [self updateNowPlayingInfo];
}

- (void)handleCuePlaybackEnded:(NSNotification *)notification
{
  [self resolveCueAndRelease];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
  if (context == RSPlayerItemStatusContext) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (item.status == AVPlayerItemStatusReadyToPlay) {
      [self emitLoad];
      [self emitState:[self currentState]];
      [self updateNowPlayingInfo];
    } else if (item.status == AVPlayerItemStatusFailed) {
      [self emitError:item.error.localizedDescription ?: @"Audio playback error"];
      [self updateNowPlayingInfo];
    }
    return;
  }

  if (context == RSPlayerCueItemStatusContext) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (item.status == AVPlayerItemStatusFailed) {
      [self rejectCueAndRelease:item.error.localizedDescription ?: @"Cue playback error"
                          error:item.error];
    }
    return;
  }

  if (context == RSPlayerTimeControlContext) {
    [self emitState:[self currentState]];
    [self updateNowPlayingInfo];
    return;
  }

  [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (NSString *)currentState
{
  if (!self.player || !self.player.currentItem) {
    return @"idle";
  }

  if (self.player.currentItem.status == AVPlayerItemStatusFailed) {
    return @"idle";
  }

  switch (self.player.timeControlStatus) {
    case AVPlayerTimeControlStatusPlaying:
      return @"playing";
    case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
      return @"buffering";
    case AVPlayerTimeControlStatusPaused:
    default:
      return @"paused";
  }
}

- (void)emitLoad
{
  AVPlayerItem *item = self.player.currentItem;
  [self updateNowPlayingInfo];
  [self emit:@{
    @"type": @"load",
    @"duration": @([self seconds:item.duration]),
    @"position": @([self seconds:self.player.currentTime]),
    @"buffered": @([self bufferedSeconds:item])
  }];
}

- (void)emitProgress
{
  AVPlayerItem *item = self.player.currentItem;
  if (!item) {
    return;
  }

  [self emit:@{
    @"type": @"progress",
    @"duration": @([self seconds:item.duration]),
    @"position": @([self seconds:self.player.currentTime]),
    @"buffered": @([self bufferedSeconds:item])
  }];
}

- (void)emitState:(NSString *)state
{
  [self updateNowPlayingInfo];
  [self emit:@{@"type": @"state", @"state": state}];
}

- (void)emitEvent:(NSString *)type
{
  [self emit:@{@"type": type}];
}

- (void)emitError:(NSString *)message
{
  [self emit:@{@"type": @"error", @"message": message ?: @"Audio playback error"}];
}

- (void)emit:(NSDictionary *)payload
{
  if (!self.hasListeners) {
    return;
  }

  [self sendEventWithName:RSPlayerEventName body:payload];
}

- (double)seconds:(CMTime)time
{
  if (!CMTIME_IS_NUMERIC(time) || CMTIME_IS_INDEFINITE(time)) {
    return 0;
  }

  double seconds = CMTimeGetSeconds(time);
  return isfinite(seconds) && seconds > 0 ? seconds : 0;
}

- (double)bufferedSeconds:(AVPlayerItem *)item
{
  NSValue *rangeValue = item.loadedTimeRanges.firstObject;
  if (!rangeValue) {
    return 0;
  }

  CMTimeRange range = rangeValue.CMTimeRangeValue;
  return [self seconds:CMTimeAdd(range.start, range.duration)];
}

- (BOOL)boolValue:(id)value defaultValue:(BOOL)defaultValue
{
  return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : defaultValue;
}

- (double)doubleValue:(id)value defaultValue:(double)defaultValue
{
  return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : defaultValue;
}

@end

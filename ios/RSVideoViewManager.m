#import <AVFoundation/AVFoundation.h>
#import <React/RCTConvert.h>
#import <React/RCTViewManager.h>

@interface RSVideoView : UIView
@property (nonatomic, copy) RCTDirectEventBlock onBuffer;
@property (nonatomic, copy) RCTDirectEventBlock onError;
@property (nonatomic, copy) RCTDirectEventBlock onLoad;
@property (nonatomic, copy) RCTDirectEventBlock onLoadStart;
@property (nonatomic, copy) NSString *resizeMode;
@property (nonatomic, copy) NSString *sourceUri;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) BOOL observingBufferEmpty;
@property (nonatomic, assign) BOOL observingLikelyToKeepUp;
@property (nonatomic, assign) BOOL observingStatus;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) NSInteger seekRequest;
@property (nonatomic, assign) double seekTime;
@end

@implementation RSVideoView

+ (Class)layerClass
{
  return [AVPlayerLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    _muted = YES;
    _paused = YES;
    _resizeMode = @"contain";
    self.backgroundColor = UIColor.blackColor;
  }

  return self;
}

- (AVPlayerLayer *)playerLayer
{
  return (AVPlayerLayer *)self.layer;
}

- (void)setResizeMode:(NSString *)resizeMode
{
  _resizeMode = [resizeMode copy] ?: @"contain";

  if ([_resizeMode isEqualToString:@"cover"]) {
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
  } else if ([_resizeMode isEqualToString:@"stretch"]) {
    self.playerLayer.videoGravity = AVLayerVideoGravityResize;
  } else {
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
  }
}

- (void)setMuted:(BOOL)muted
{
  _muted = muted;
  self.player.muted = muted;
  self.player.volume = muted ? 0 : 1;
}

- (void)setPaused:(BOOL)paused
{
  _paused = paused;
  [self syncPlaybackState];
}

- (void)setSourceUri:(NSString *)sourceUri
{
  NSString *trimmedUri = [sourceUri stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

  if ((_sourceUri == nil && trimmedUri.length == 0) || [_sourceUri isEqualToString:trimmedUri]) {
    return;
  }

  _sourceUri = [trimmedUri copy];
  [self loadSource];
}

- (void)setSeekRequest:(NSInteger)seekRequest
{
  if (_seekRequest == seekRequest) {
    return;
  }

  _seekRequest = seekRequest;
  [self seekToSeconds:self.seekTime];
}

- (void)loadSource
{
  [self removeCurrentItemObservers];

  if (self.sourceUri.length == 0) {
    [self.player pause];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.playerItem = nil;
    return;
  }

  NSURL *url = [NSURL URLWithString:self.sourceUri];
  if (!url) {
    [self emitError:@"Video URI is invalid"];
    return;
  }

  if (self.onLoadStart) {
    self.onLoadStart(@{});
  }

  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
  self.playerItem = [AVPlayerItem playerItemWithAsset:asset];
  [self disableAudioTracksForItem:self.playerItem];
  [self addCurrentItemObservers];

  AVPlayer *activePlayer = [self getOrCreatePlayer];
  [activePlayer replaceCurrentItemWithPlayerItem:self.playerItem];
  [self syncPlaybackState];
}

- (AVPlayer *)getOrCreatePlayer
{
  if (self.player) {
    return self.player;
  }

  self.player = [AVPlayer new];
  self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
  self.player.allowsExternalPlayback = NO;
  self.player.muted = self.muted;
  self.player.volume = self.muted ? 0 : 1;
  self.playerLayer.player = self.player;

  return self.player;
}

- (void)syncPlaybackState
{
  if (!self.player.currentItem) {
    return;
  }

  self.player.muted = self.muted;
  self.player.volume = self.muted ? 0 : 1;

  if (self.paused) {
    [self.player pause];
  } else {
    [self.player play];
  }
}

- (void)seekToSeconds:(double)seconds
{
  if (!self.player.currentItem) {
    return;
  }

  CMTime time = CMTimeMakeWithSeconds(MAX(seconds, 0), NSEC_PER_SEC);
  [self.player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)disableAudioTracksForItem:(AVPlayerItem *)item
{
  AVMediaSelectionGroup *audibleGroup = [item.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];
  if (audibleGroup) {
    [item selectMediaOption:nil inMediaSelectionGroup:audibleGroup];
  }

  for (AVPlayerItemTrack *track in item.tracks) {
    if ([track.assetTrack.mediaType isEqualToString:AVMediaTypeAudio]) {
      track.enabled = NO;
    }
  }
}

- (void)addCurrentItemObservers
{
  if (!self.playerItem) {
    return;
  }

  [self.playerItem addObserver:self
                    forKeyPath:@"status"
                       options:NSKeyValueObservingOptionNew
                       context:nil];
  self.observingStatus = YES;

  [self.playerItem addObserver:self
                    forKeyPath:@"playbackBufferEmpty"
                       options:NSKeyValueObservingOptionNew
                       context:nil];
  self.observingBufferEmpty = YES;

  [self.playerItem addObserver:self
                    forKeyPath:@"playbackLikelyToKeepUp"
                       options:NSKeyValueObservingOptionNew
                       context:nil];
  self.observingLikelyToKeepUp = YES;
}

- (void)removeCurrentItemObservers
{
  if (!self.playerItem) {
    return;
  }

  if (self.observingStatus) {
    [self.playerItem removeObserver:self forKeyPath:@"status"];
    self.observingStatus = NO;
  }

  if (self.observingBufferEmpty) {
    [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    self.observingBufferEmpty = NO;
  }

  if (self.observingLikelyToKeepUp) {
    [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    self.observingLikelyToKeepUp = NO;
  }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
  if (object != self.playerItem) {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
  }

  if ([keyPath isEqualToString:@"status"]) {
    if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
      [self disableAudioTracksForItem:self.playerItem];
      [self emitLoad];
      [self syncPlaybackState];
    } else if (self.playerItem.status == AVPlayerItemStatusFailed) {
      [self emitError:self.playerItem.error.localizedDescription ?: @"Video playback failed"];
    }
    return;
  }

  if ([keyPath isEqualToString:@"playbackBufferEmpty"] && self.playerItem.playbackBufferEmpty) {
    [self emitBuffer:YES];
    return;
  }

  if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"] && self.playerItem.playbackLikelyToKeepUp) {
    [self emitBuffer:NO];
  }
}

- (void)emitLoad
{
  if (!self.onLoad) {
    return;
  }

  double duration = CMTimeGetSeconds(self.playerItem.duration);
  if (!isfinite(duration) || duration < 0) {
    duration = 0;
  }

  CGSize presentationSize = self.playerItem.presentationSize;
  self.onLoad(@{
    @"duration": @(duration),
    @"naturalSize": @{
      @"width": @(presentationSize.width),
      @"height": @(presentationSize.height),
    },
  });
}

- (void)emitBuffer:(BOOL)isBuffering
{
  if (self.onBuffer) {
    self.onBuffer(@{@"isBuffering": @(isBuffering)});
  }
}

- (void)emitError:(NSString *)message
{
  if (self.onError) {
    self.onError(@{
      @"error": @{
        @"errorString": message ?: @"Video playback failed",
      },
    });
  }
}

- (void)dealloc
{
  [self removeCurrentItemObservers];
  [self.player pause];
  [self.player replaceCurrentItemWithPlayerItem:nil];
  self.playerLayer.player = nil;
}

@end

@interface RSVideoViewManager : RCTViewManager
@end

@implementation RSVideoViewManager

RCT_EXPORT_MODULE(RSVideoView)

- (UIView *)view
{
  return [RSVideoView new];
}

RCT_EXPORT_VIEW_PROPERTY(sourceUri, NSString)
RCT_EXPORT_VIEW_PROPERTY(paused, BOOL)
RCT_EXPORT_VIEW_PROPERTY(muted, BOOL)
RCT_EXPORT_VIEW_PROPERTY(resizeMode, NSString)
RCT_EXPORT_VIEW_PROPERTY(seekTime, double)
RCT_EXPORT_VIEW_PROPERTY(seekRequest, NSInteger)
RCT_EXPORT_VIEW_PROPERTY(onLoadStart, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onLoad, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onBuffer, RCTDirectEventBlock)
RCT_EXPORT_VIEW_PROPERTY(onError, RCTDirectEventBlock)

@end

/* Media stubs for lui_media: audio decode/playback and video frame
   decode behind one C ABI on every platform.

   - macOS (compiled as Objective-C with ARC): whole-file decode to
     float32 PCM through ExtAudioFile (AudioFileOpenWithCallbacks for
     in-memory sources); playback through one shared AVAudioEngine
     with an AVAudioPlayerNode per player (the engine's mixer gives
     simultaneous players for free); video decode through
     AVAssetReader producing BGRA buffers converted here to
     premultiplied RGBA. AVAssetWriter backs the test-clip generator.
   - Linux: decode through a runtime-resolved libsndfile, with an
     ffmpeg subprocess fallback; playback through a runtime-resolved
     SDL2 device queue, with an ffplay subprocess fallback that only
     supports play/stop. Video decode is not implemented.
   - Everything else: availability probes return false and every
     entry point raises Failure, so the OCaml side needs no platform
     conditionals.

   The player position is reported in source frames by tracking the
   player's render clock: after each (re)schedule the first
   playerTime read becomes the reference; the file frame then is
   origin + (sampleTime - ref), wrapped by duration when looping. */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/custom.h>
#include <caml/callback.h>
#include <caml/threads.h>

enum {
  LUI_MED_STOPPED = 0,
  LUI_MED_PLAYING = 1,
  LUI_MED_PAUSED = 2,
  LUI_MED_ENDED = 3
};

#define LuiPlayer_val(v) (*(void **)Data_custom_val(v))
#define LuiVideo_val(v) (*(void **)Data_custom_val(v))

/* ================================================================= */
#if defined(__APPLE__)
/* ================================================================= */

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

/* ------------------------- decode to PCM ------------------------- */

/* ExtAudioFile -> interleaved float32 at the file's native rate and
   channel count. Returns 0 with err set on failure; *pcm is
   malloc'ed (caller frees). */
static int ext_decode(ExtAudioFileRef ef, float **pcm, long *frames,
                      int *rate, int *ch, char *err, size_t errlen)
{
  AudioStreamBasicDescription src;
  UInt32 sz = sizeof(src);
  if (ExtAudioFileGetProperty(ef, kExtAudioFileProperty_FileDataFormat,
                              &sz, &src) != noErr) {
    snprintf(err, errlen, "cannot read file format");
    return 0;
  }
  unsigned nch = src.mChannelsPerFrame;
  if (nch < 1 || nch > 8) {
    snprintf(err, errlen, "unsupported channel count %u", nch);
    return 0;
  }
  AudioStreamBasicDescription dst;
  memset(&dst, 0, sizeof(dst));
  dst.mSampleRate = src.mSampleRate;
  dst.mFormatID = kAudioFormatLinearPCM;
  dst.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  dst.mBitsPerChannel = 32;
  dst.mChannelsPerFrame = nch;
  dst.mFramesPerPacket = 1;
  dst.mBytesPerFrame = nch * 4;
  dst.mBytesPerPacket = dst.mBytesPerFrame;
  if (ExtAudioFileSetProperty(ef, kExtAudioFileProperty_ClientDataFormat,
                              sizeof(dst), &dst) != noErr) {
    snprintf(err, errlen, "cannot set client format");
    return 0;
  }
  const UInt32 chunk = 1 << 16;
  float *tmp = (float *)malloc((size_t)chunk * dst.mBytesPerFrame);
  if (!tmp) {
    snprintf(err, errlen, "out of memory");
    return 0;
  }
  size_t cap = (size_t)chunk * 4;
  float *buf = (float *)malloc(cap * dst.mBytesPerFrame);
  size_t total = 0;
  for (;;) {
    AudioBufferList abl;
    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = nch;
    abl.mBuffers[0].mData = tmp;
    abl.mBuffers[0].mDataByteSize = chunk * dst.mBytesPerFrame;
    UInt32 got = chunk;
    OSStatus st = ExtAudioFileRead(ef, &got, &abl);
    if (st != noErr) {
      snprintf(err, errlen, "decode error %d", (int)st);
      free(tmp);
      free(buf);
      return 0;
    }
    if (got == 0) break;
    if (total + got > cap) {
      cap = (total + got) * 2;
      float *nb = (float *)realloc(buf, cap * dst.mBytesPerFrame);
      if (!nb) {
        snprintf(err, errlen, "out of memory");
        free(tmp);
        free(buf);
        return 0;
      }
      buf = nb;
    }
    memcpy(buf + total * nch, tmp, (size_t)got * dst.mBytesPerFrame);
    total += got;
  }
  free(tmp);
  *pcm = buf;
  *frames = (long)total;
  *rate = (int)dst.mSampleRate;
  *ch = (int)nch;
  err[0] = '\0';
  return 1;
}

static NSString *stage_bytes(const void *data, size_t len);

static int decode_any(const char *path, const void *data, size_t dlen,
                      float **pcm, long *frames, int *rate, int *ch,
                      char *err, size_t errlen)
{
  @autoreleasepool {
    /* Byte sources are staged to a temp file: an ExtAudioFile wrapped
       around a callback-opened AudioFileID crashes inside
       ExtAudioFileRead on current macOS, while URL-opened files work. */
    NSString *staged = nil;
    const char *use = path;
    if (!use) {
      staged = stage_bytes(data, dlen);
      if (!staged) {
        snprintf(err, errlen, "cannot stage input");
        return 0;
      }
      use = [staged UTF8String];
    }
    NSString *p = [NSString stringWithUTF8String:use];
    ExtAudioFileRef ef = NULL;
    OSStatus st = ExtAudioFileOpenURL(
        (__bridge CFURLRef)[NSURL fileURLWithPath:p], &ef);
    int ok = 0;
    if (st == noErr && ef) {
      ok = ext_decode(ef, pcm, frames, rate, ch, err, errlen);
      ExtAudioFileDispose(ef);
    } else
      snprintf(err, errlen, "cannot open audio (%d)", (int)st);
    if (staged)
      [[NSFileManager defaultManager] removeItemAtPath:staged
                                                 error:nil];
    return ok;
  }
}

/* ------------------------------ player ---------------------------- */

static AVAudioEngine *lui_engine(void)
{
  static AVAudioEngine *eng;
  static dispatch_once_t once;
  static BOOL ok;
  dispatch_once(&once, ^{
    eng = [[AVAudioEngine alloc] init];
    NSError *e = nil;
    /* start throws (rather than reporting) when the host has no
       input/output node at all, e.g. a headless runner. */
    @try {
      ok = [eng startAndReturnError:&e];
    } @catch (NSException *x) {
      ok = NO;
    }
    if (!ok) eng = nil;
  });
  return eng;
}

@interface LuiMediaPlayer : NSObject {
  @public
  uint64_t gen;    /* schedule generation; bumped on every (re)arm */
  volatile int ended;
}
@property(nonatomic) AVAudioPlayerNode *node;
@property(nonatomic) AVAudioFile *file;
@property(nonatomic) NSString *tmp;   /* staged byte source, or nil */
@property(nonatomic) int state;
@property(nonatomic) BOOL loop;
@property(nonatomic) float vol;
@property(nonatomic) double rate;
@property(nonatomic) AVAudioFramePosition total;
@property(nonatomic) AVAudioFramePosition origin;   /* armed frame */
@property(nonatomic) int64_t ref;                   /* playerTime ref */
@property(nonatomic) int64_t refOrigin;             /* file frame at ref */
@end

@implementation LuiMediaPlayer
@end

static LuiMediaPlayer *player_of(value v)
{
  return (__bridge LuiMediaPlayer *)LuiPlayer_val(v);
}

static void lui_player_finalize(value v)
{
  LuiMediaPlayer *p = player_of(v);
  if (p) {
    __atomic_add_fetch(&p->gen, 1, __ATOMIC_SEQ_CST);
    [p.node stop];
    AVAudioEngine *e = lui_engine();
    if (e) [e detachNode:p.node];
    if (p.tmp)
      [[NSFileManager defaultManager]
          removeItemAtPath:p.tmp
                     error:nil];
    CFRelease((CFTypeRef)p);
  }
}

static struct custom_operations player_ops = {
  "lui_media.player", lui_player_finalize, custom_compare_default,
  custom_hash_default, custom_serialize_default,
  custom_deserialize_default, custom_compare_ext_default,
  custom_fixed_length_default
};

/* Queue the segment [f, total). Loop segments reschedule themselves
   (generation-guarded) so playback stays gapless; the final
   non-looping segment flags ended when it finishes playing back. */
static void queue_from(LuiMediaPlayer *p, AVAudioFramePosition f)
{
  uint64_t g = p->gen;
  __weak LuiMediaPlayer *ws = p;
  [p.node
      scheduleSegment:p.file
        startingFrame:f
           frameCount:(AVAudioFrameCount)(p.total - f)
               atTime:nil
completionCallbackType:(p.loop ? AVAudioPlayerNodeCompletionDataRendered
                               : AVAudioPlayerNodeCompletionDataPlayedBack)
    completionHandler:^(AVAudioPlayerNodeCompletionCallbackType t) {
      LuiMediaPlayer *s = ws;
      if (!s || __atomic_load_n(&s->gen, __ATOMIC_SEQ_CST) != g) return;
      if (s.loop)
        queue_from(s, 0);
      else if (t == AVAudioPlayerNodeCompletionDataPlayedBack) {
        s->ended = 1;
        s.state = LUI_MED_ENDED;
      }
    }];
}

static void schedule_from(LuiMediaPlayer *p, AVAudioFramePosition f)
{
  __atomic_add_fetch(&p->gen, 1, __ATOMIC_SEQ_CST);
  [p.node stop];
  p.origin = f;
  p.ref = -1;
  p.refOrigin = f;
  if (p.file && p.total > f) queue_from(p, f);
}

static double player_position(LuiMediaPlayer *p)
{
  if (p.rate <= 0) return 0;
  if (p.state != LUI_MED_PLAYING && p.state != LUI_MED_PAUSED)
    return (double)p.origin / p.rate;
  AVAudioTime *lt = p.node.lastRenderTime;
  if (!lt || !lt.isSampleTimeValid)
    return (double)p.origin / p.rate;
  AVAudioTime *pt = [p.node playerTimeForNodeTime:lt];
  if (!pt) return (double)p.origin / p.rate;
  if (p.ref < 0) {
    p.ref = pt.sampleTime;
    p.refOrigin = p.origin;
  }
  int64_t fr = p.refOrigin + (pt.sampleTime - p.ref);
  if (p.loop && p.total > 0) {
    fr %= p.total;
    if (fr < 0) fr += p.total;
  } else if (fr > p.total)
    fr = p.total;
  else if (fr < 0)
    fr = 0;
  return (double)fr / p.rate;
}

/* ---------------------------- video decoder ----------------------- */

@interface LuiVideoDec : NSObject
@property(nonatomic) AVURLAsset *asset;
@property(nonatomic) AVAssetTrack *track;
@property(nonatomic) AVAssetReader *reader;
@property(nonatomic) AVAssetReaderTrackOutput *out;
@property(nonatomic) double dur;
@property(nonatomic) int w;
@property(nonatomic) int h;
@end

@implementation LuiVideoDec

- (BOOL)startReaderAt:(double)t error:(NSError **)err
{
  self.reader = [AVAssetReader assetReaderWithAsset:self.asset error:err];
  if (!self.reader) return NO;
  self.out = [AVAssetReaderTrackOutput
      assetReaderTrackOutputWithTrack:self.track
                       outputSettings:@{
                         (id)kCVPixelBufferPixelFormatTypeKey :
                             @(kCVPixelFormatType_32BGRA)
                       }];
  self.out.alwaysCopiesSampleData = NO;
  if (t > 0)
    self.reader.timeRange = CMTimeRangeMake(
        CMTimeMakeWithSeconds(t, 600), kCMTimePositiveInfinity);
  if (![self.reader canAddOutput:self.out]) {
    if (err)
      *err = [NSError errorWithDomain:@"lui_media" code:1
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"cannot add reader output"
                             }];
    return NO;
  }
  [self.reader addOutput:self.out];
  return [self.reader startReading];
}

@end

static LuiVideoDec *video_of(value v)
{
  return (__bridge LuiVideoDec *)LuiVideo_val(v);
}

static void lui_video_finalize(value v)
{
  LuiVideoDec *d = video_of(v);
  if (d) {
    [d.reader cancelReading];
    CFRelease((CFTypeRef)d);
  }
}

static struct custom_operations video_ops = {
  "lui_media.video", lui_video_finalize, custom_compare_default,
  custom_hash_default, custom_serialize_default,
  custom_deserialize_default, custom_compare_ext_default,
  custom_fixed_length_default
};

/* ---------------------------- entry points ------------------------ */

CAMLprim value lui_media_audio_available(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool(lui_engine() != nil));
}

CAMLprim value lui_media_decode_available(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool(1));
}

CAMLprim value lui_media_video_available(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool(1));
}

CAMLprim value lui_media_decode(value vsrc, value vis_data)
{
  CAMLparam2(vsrc, vis_data);
  CAMLlocal2(vout, vpcm);
  float *pcm = NULL;
  long frames = 0;
  int rate = 0, ch = 0;
  char err[256];
  err[0] = '\0';
  int is_data = Bool_val(vis_data);
  int ok = decode_any(is_data ? NULL : String_val(vsrc),
                      is_data ? String_val(vsrc) : NULL,
                      is_data ? caml_string_length(vsrc) : 0,
                      &pcm, &frames, &rate, &ch, err, sizeof(err));
  vpcm = caml_alloc_initialized_string(
      ok ? (mlsize_t)frames * ch * 4 : 0, ok ? (const char *)pcm : "");
  free(pcm);
  vout = caml_alloc_tuple(6);
  Store_field(vout, 0, Val_bool(ok));
  Store_field(vout, 1, caml_copy_string(err));
  Store_field(vout, 2, Val_long(frames));
  Store_field(vout, 3, Val_int(rate));
  Store_field(vout, 4, Val_int(ch));
  Store_field(vout, 5, vpcm);
  CAMLreturn(vout);
}

CAMLprim value lui_media_player_create(value unit)
{
  CAMLparam1(unit);
  AVAudioEngine *e = lui_engine();
  if (!e) caml_failwith("lui_media: audio engine unavailable");
  LuiMediaPlayer *p = [[LuiMediaPlayer alloc] init];
  p.node = [[AVAudioPlayerNode alloc] init];
  [e attachNode:p.node];
  p.state = LUI_MED_STOPPED;
  p.vol = 1.0f;
  p.ref = -1;
  value v = caml_alloc_custom(&player_ops, sizeof(void *),
                              4 * 1024 * 1024, 128 * 1024 * 1024);
  LuiPlayer_val(v) = (void *)CFBridgingRetain(p);
  CAMLreturn(v);
}

/* Stage a byte source into a temp file so AVAudioFile can read it.
   AudioFile sniffs the content, so no extension hint is needed. */
static NSString *stage_bytes(const void *data, size_t len)
{
  NSString *dir = NSTemporaryDirectory();
  NSString *path = [dir
      stringByAppendingPathComponent:
          [NSString
              stringWithFormat:@"lui_media_%ld_%llu.data",
                               (long)getpid(),
                               (unsigned long long)arc4random()]];
  NSData *d = [NSData dataWithBytes:data length:len];
  if (![d writeToFile:path atomically:YES]) return nil;
  return path;
}

CAMLprim value lui_media_player_load(value v, value vsrc, value vis_data)
{
  CAMLparam3(v, vsrc, vis_data);
  LuiMediaPlayer *p = player_of(v);
  @autoreleasepool {
    __atomic_add_fetch(&p->gen, 1, __ATOMIC_SEQ_CST);
    [p.node stop];
    if (p.tmp) {
      [[NSFileManager defaultManager]
          removeItemAtPath:p.tmp
                     error:nil];
      p.tmp = nil;
    }
    NSString *path;
    if (Bool_val(vis_data)) {
      path = stage_bytes(String_val(vsrc), caml_string_length(vsrc));
      if (!path) CAMLreturn(caml_copy_string("cannot stage input"));
    } else
      path = [NSString stringWithUTF8String:String_val(vsrc)];
    NSError *e = nil;
    AVAudioFile *file =
        [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:path]
                                      error:&e];
    if (!file) {
      if (Bool_val(vis_data))
        [[NSFileManager defaultManager] removeItemAtPath:path
                                                   error:nil];
      NSString *m = e ? [e localizedDescription] : @"cannot open audio";
      CAMLreturn(caml_copy_string([m UTF8String]));
    }
    if (Bool_val(vis_data)) p.tmp = path;
    AVAudioEngine *eng = lui_engine();
    [eng disconnectNodeOutput:p.node];
    [eng connect:p.node
              to:eng.mainMixerNode
          format:file.processingFormat];
    p.file = file;
    p.total = file.length;
    p.rate = file.processingFormat.sampleRate;
    p.origin = 0;
    p.ref = -1;
    p.refOrigin = 0;
    p->ended = 0;
    p.state = LUI_MED_STOPPED;
  }
  CAMLreturn(caml_copy_string(""));
}

CAMLprim value lui_media_player_play(value v)
{
  CAMLparam1(v);
  LuiMediaPlayer *p = player_of(v);
  @autoreleasepool {
    if (!p.file) CAMLreturn(Val_unit);
    switch (p.state) {
    case LUI_MED_PLAYING:
      break;
    case LUI_MED_PAUSED:
      [p.node play];
      p.state = LUI_MED_PLAYING;
      break;
    default: { /* stopped or ended: schedule from the armed frame */
      AVAudioFramePosition f =
          p.state == LUI_MED_ENDED ? 0 : p.origin;
      schedule_from(p, f);
      [p.node play];
      p->ended = 0;
      p.state = LUI_MED_PLAYING;
      break;
    }
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_pause(value v)
{
  CAMLparam1(v);
  LuiMediaPlayer *p = player_of(v);
  if (p.state == LUI_MED_PLAYING) {
    [p.node pause];
    p.state = LUI_MED_PAUSED;
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_stop(value v)
{
  CAMLparam1(v);
  LuiMediaPlayer *p = player_of(v);
  __atomic_add_fetch(&p->gen, 1, __ATOMIC_SEQ_CST);
  [p.node stop];
  p.state = LUI_MED_STOPPED;
  p.origin = 0;
  p.ref = -1;
  p.refOrigin = 0;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_unload(value v)
{
  CAMLparam1(v);
  LuiMediaPlayer *p = player_of(v);
  __atomic_add_fetch(&p->gen, 1, __ATOMIC_SEQ_CST);
  [p.node stop];
  AVAudioEngine *e = lui_engine();
  if (e) [e disconnectNodeOutput:p.node];
  p.file = nil;
  if (p.tmp) {
    [[NSFileManager defaultManager]
        removeItemAtPath:p.tmp
                   error:nil];
    p.tmp = nil;
  }
  p.total = 0;
  p.origin = 0;
  p.ref = -1;
  p.refOrigin = 0;
  p->ended = 0;
  p.state = LUI_MED_STOPPED;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_seek(value v, value vt)
{
  CAMLparam2(v, vt);
  LuiMediaPlayer *p = player_of(v);
  double t = Double_val(vt);
  if (t < 0) t = 0;
  AVAudioFramePosition f =
      (AVAudioFramePosition)(t * p.rate);
  if (f > p.total) f = p.total;
  if (p.state == LUI_MED_ENDED) p.state = LUI_MED_STOPPED;
  p.origin = f;
  p.ref = -1;
  p.refOrigin = f;
  p->ended = 0;
  if (p.state != LUI_MED_STOPPED) {
    schedule_from(p, f);
    if (p.state == LUI_MED_PLAYING) [p.node play];
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_set_volume(value v, value vvol)
{
  CAMLparam2(v, vvol);
  LuiMediaPlayer *p = player_of(v);
  float x = (float)Double_val(vvol);
  if (x < 0) x = 0;
  if (x > 1) x = 1;
  p.vol = x;
  p.node.volume = x;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_set_loop(value v, value vb)
{
  CAMLparam2(v, vb);
  LuiMediaPlayer *p = player_of(v);
  BOOL l = Bool_val(vb);
  if (l != p.loop) {
    p.loop = l;
    /* Reschedule so the new completion type applies. */
    if (p.state == LUI_MED_PLAYING || p.state == LUI_MED_PAUSED)
      schedule_from(p, p.origin);
    if (p.state == LUI_MED_PLAYING) [p.node play];
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_info(value v)
{
  CAMLparam1(v);
  CAMLlocal1(vout);
  LuiMediaPlayer *p = player_of(v);
  double dur = p.rate > 0 ? (double)p.total / p.rate : 0;
  double pos = player_position(p);
  vout = caml_alloc_tuple(5);
  Store_field(vout, 0, caml_copy_double(dur));
  Store_field(vout, 1, caml_copy_double(pos));
  Store_field(vout, 2, Val_int(p.state));
  Store_field(vout, 3, caml_copy_double(p.vol));
  Store_field(vout, 4, Val_int(p.loop ? 1 : 0));
  CAMLreturn(vout);
}

CAMLprim value lui_media_player_take_ended(value v)
{
  CAMLparam1(v);
  LuiMediaPlayer *p = player_of(v);
  int e = p->ended;
  p->ended = 0;
  CAMLreturn(Val_bool(e));
}

CAMLprim value lui_media_video_open(value vpath)
{
  CAMLparam1(vpath);
  CAMLlocal1(v);
  @autoreleasepool {
    NSString *path = [NSString stringWithUTF8String:String_val(vpath)];
    NSURL *url = [path hasPrefix:@"file://"]
                     ? [NSURL URLWithString:path]
                     : [NSURL fileURLWithPath:path];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url
                                          options:@{
                                            AVURLAssetPreferPreciseDurationAndTimingKey :
                                                @YES
                                          }];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[ @"duration", @"tracks" ]
                         completionHandler:^{
                           dispatch_semaphore_signal(sem);
                         }];
    dispatch_semaphore_wait(
        sem, dispatch_time(DISPATCH_TIME_NOW, 30LL * NSEC_PER_SEC));
    if ([asset statusOfValueForKey:@"tracks" error:nil] !=
            AVKeyValueStatusLoaded ||
        [asset statusOfValueForKey:@"duration" error:nil] !=
            AVKeyValueStatusLoaded)
      caml_failwith("lui_media: cannot open asset");
    AVAssetTrack *track =
        [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) caml_failwith("lui_media: no video track");
    LuiVideoDec *d = [[LuiVideoDec alloc] init];
    d.asset = asset;
    d.track = track;
    CGSize sz = track.naturalSize;
    d.w = (int)sz.width;
    d.h = (int)sz.height;
    d.dur = CMTimeGetSeconds(asset.duration);
    NSError *e = nil;
    if (![d startReaderAt:0 error:&e]) {
      NSString *m = e ? [e localizedDescription] : @"reader failed";
      caml_failwith([m UTF8String]);
    }
    v = caml_alloc_custom(&video_ops, sizeof(void *),
                              8 * 1024 * 1024, 128 * 1024 * 1024);
    LuiVideo_val(v) = (void *)CFBridgingRetain(d);
    CAMLreturn(v);
  }
}

CAMLprim value lui_media_video_close(value v)
{
  CAMLparam1(v);
  LuiVideoDec *d = video_of(v);
  [d.reader cancelReading];
  d.reader = nil;
  d.out = nil;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_video_duration(value v)
{
  CAMLparam1(v);
  CAMLreturn(caml_copy_double(video_of(v).dur));
}

CAMLprim value lui_media_video_size(value v)
{
  CAMLparam1(v);
  CAMLlocal1(vout);
  LuiVideoDec *d = video_of(v);
  vout = caml_alloc_tuple(2);
  Store_field(vout, 0, Val_int(d.w));
  Store_field(vout, 1, Val_int(d.h));
  CAMLreturn(vout);
}

CAMLprim value lui_media_video_seek(value v, value vt)
{
  CAMLparam2(v, vt);
  LuiVideoDec *d = video_of(v);
  double t = Double_val(vt);
  if (t < 0) t = 0;
  [d.reader cancelReading];
  NSError *e = nil;
  if (![d startReaderAt:t error:&e]) {
    NSString *m = e ? [e localizedDescription] : @"seek failed";
    caml_failwith([m UTF8String]);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_video_next(value v)
{
  CAMLparam1(v);
  CAMLlocal3(vout, vbytes, verr);
  LuiVideoDec *d = video_of(v);
  @autoreleasepool {
    CMSampleBufferRef s = [d.out copyNextSampleBuffer];
    if (!s) {
      NSError *e = d.reader.error;
      verr = caml_copy_string(
          e ? [[e localizedDescription] UTF8String] : "");
      vout = caml_alloc_tuple(6);
      Store_field(vout, 0, Val_bool(0));
      Store_field(vout, 1, caml_copy_double(0));
      Store_field(vout, 2, Val_int(0));
      Store_field(vout, 3, Val_int(0));
      Store_field(vout, 4, caml_alloc_initialized_string(0, ""));
      Store_field(vout, 5, verr);
      CAMLreturn(vout);
    }
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(s);
    double secs = CMTimeGetSeconds(pts);
    CVImageBufferRef img = CMSampleBufferGetImageBuffer(s);
    CVPixelBufferLockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
    size_t w = CVPixelBufferGetWidth(img);
    size_t h = CVPixelBufferGetHeight(img);
    size_t stride = CVPixelBufferGetBytesPerRow(img);
    const unsigned char *src =
        (const unsigned char *)CVPixelBufferGetBaseAddress(img);
    unsigned char *dst = (unsigned char *)malloc(w * h * 4);
    if (dst) {
      for (size_t y = 0; y < h; y++) {
        const unsigned char *sr = src + y * stride;
        unsigned char *dr = dst + y * w * 4;
        for (size_t x = 0; x < w; x++) {
          unsigned b = sr[x * 4], g = sr[x * 4 + 1], r = sr[x * 4 + 2],
                   a = sr[x * 4 + 3];
          dr[x * 4] = (unsigned char)((r * a + 127) / 255);
          dr[x * 4 + 1] = (unsigned char)((g * a + 127) / 255);
          dr[x * 4 + 2] = (unsigned char)((b * a + 127) / 255);
          dr[x * 4 + 3] = (unsigned char)a;
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
    CFRelease(s);
    vbytes = dst ? caml_alloc_initialized_string((mlsize_t)(w * h * 4),
                                                 (const char *)dst)
                 : caml_alloc_initialized_string(0, "");
    free(dst);
    vout = caml_alloc_tuple(6);
    Store_field(vout, 0, Val_bool(dst != NULL));
    Store_field(vout, 1, caml_copy_double(secs));
    Store_field(vout, 2, Val_int((int)w));
    Store_field(vout, 3, Val_int((int)h));
    Store_field(vout, 4, vbytes);
    Store_field(vout, 5, caml_copy_string(""));
    CAMLreturn(vout);
  }
}

/* Deterministic test clip: 8 vertical color bars (tagged BT.709,
   full range) plus a moving white block so successive frames differ. */
CAMLprim value lui_media_write_test_video(value vpath, value vw, value vh,
                                          value vsecs)
{
  CAMLparam4(vpath, vw, vh, vsecs);
  CAMLlocal1(vout);
  @try {
  @autoreleasepool {
    int w = Int_val(vw), h = Int_val(vh);
    double secs = Double_val(vsecs);
    const char *err = "";
    NSString *path = [NSString stringWithUTF8String:String_val(vpath)];
    NSURL *url = [NSURL fileURLWithPath:path];
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
    NSError *e = nil;
    AVAssetWriter *wr =
        [AVAssetWriter assetWriterWithURL:url
                                 fileType:AVFileTypeMPEG4
                                    error:&e];
    if (!wr) {
      err = e ? [[e localizedDescription] UTF8String] : "writer failed";
      vout = caml_alloc_tuple(2);
      Store_field(vout, 0, Val_bool(0));
      Store_field(vout, 1, caml_copy_string(err));
      CAMLreturn(vout);
    }
    AVAssetWriterInput *in = [AVAssetWriterInput
        assetWriterInputWithMediaType:AVMediaTypeVideo
                       outputSettings:@{
                         AVVideoCodecKey : AVVideoCodecTypeH264,
                         AVVideoWidthKey : @(w),
                         AVVideoHeightKey : @(h),
                         AVVideoCompressionPropertiesKey : @{
                           AVVideoAverageBitRateKey : @(w * h * 16)
                         }
                       }];
    in.expectsMediaDataInRealTime = NO;
    AVAssetWriterInputPixelBufferAdaptor *ad =
        [AVAssetWriterInputPixelBufferAdaptor
            assetWriterInputPixelBufferAdaptorWithAssetWriterInput:in
                                     sourcePixelBufferAttributes:@{
                                       (id)kCVPixelBufferPixelFormatTypeKey :
                                           @(kCVPixelFormatType_32BGRA),
                                       (id)kCVPixelBufferWidthKey : @(w),
                                       (id)kCVPixelBufferHeightKey : @(h)
                                     }];
    [wr addInput:in];
    [wr startWriting];
    [wr startSessionAtSourceTime:kCMTimeZero];
    static const unsigned char bars[8][3] = {
      {255, 0, 0},     {0, 255, 0},   {0, 0, 255},   {255, 255, 255},
      {0, 0, 0},       {255, 255, 0}, {0, 255, 255}, {255, 0, 255}
    };
    long frames = (long)(secs * 30.0 + 0.5);
    if (frames < 1) frames = 1;
    int bs = w > 10 ? 8 : 4;
    for (long i = 0; i < frames; i++) {
      while (!in.readyForMoreMediaData)
        [NSThread sleepForTimeInterval:0.001];
      CVPixelBufferRef pb = NULL;
      CVPixelBufferPoolCreatePixelBuffer(NULL, ad.pixelBufferPool, &pb);
      if (!pb) break;
      /* Tag the frames BT.709 so the decompressor maps them to sRGB
         instead of guessing from the container. */
      CVBufferSetAttachment(
          pb, kCVImageBufferColorPrimariesKey,
          kCVImageBufferColorPrimaries_ITU_R_709_2,
          kCVAttachmentMode_ShouldPropagate);
      CVBufferSetAttachment(
          pb, kCVImageBufferTransferFunctionKey,
          kCVImageBufferTransferFunction_ITU_R_709_2,
          kCVAttachmentMode_ShouldPropagate);
      CVBufferSetAttachment(
          pb, kCVImageBufferYCbCrMatrixKey,
          kCVImageBufferYCbCrMatrix_ITU_R_709_2,
          kCVAttachmentMode_ShouldPropagate);
      CVPixelBufferLockBaseAddress(pb, 0);
      unsigned char *base =
          (unsigned char *)CVPixelBufferGetBaseAddress(pb);
      size_t stride = CVPixelBufferGetBytesPerRow(pb);
      int bx = (int)((i * 7) % (long)(w - bs > 0 ? w - bs : 1));
      int by = (int)((i * 5) % (long)(h - bs > 0 ? h - bs : 1));
      for (int y = 0; y < h; y++) {
        unsigned char *row = base + y * stride;
        for (int x = 0; x < w; x++) {
          int bar = x * 8 / (w > 0 ? w : 1);
          if (bar > 7) bar = 7;
          unsigned r = bars[bar][0], g = bars[bar][1], b = bars[bar][2];
          if (x >= bx && x < bx + bs && y >= by && y < by + bs) {
            r = 255; g = 255; b = 255;
          }
          row[x * 4] = b;
          row[x * 4 + 1] = g;
          row[x * 4 + 2] = r;
          row[x * 4 + 3] = 255;
        }
      }
      CVPixelBufferUnlockBaseAddress(pb, 0);
      [ad appendPixelBuffer:pb
         withPresentationTime:CMTimeMake(i, 30)];
      CVPixelBufferRelease(pb);
    }
    [in markAsFinished];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [wr finishWritingWithCompletionHandler:^{
      dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(
        done, dispatch_time(DISPATCH_TIME_NOW, 60LL * NSEC_PER_SEC));
    if (wr.status != AVAssetWriterStatusCompleted) {
      err = wr.error ? [[wr.error localizedDescription] UTF8String]
                     : "write incomplete";
      vout = caml_alloc_tuple(2);
      Store_field(vout, 0, Val_bool(0));
      Store_field(vout, 1, caml_copy_string(err));
      CAMLreturn(vout);
    }
    vout = caml_alloc_tuple(2);
    Store_field(vout, 0, Val_bool(1));
    Store_field(vout, 1, caml_copy_string(""));
    CAMLreturn(vout);
  }
  } @catch (NSException *x) {
    vout = caml_alloc_tuple(2);
    Store_field(vout, 0, Val_bool(0));
    Store_field(vout, 1,
                caml_copy_string(
                    [[NSString stringWithFormat:@"writer: %@",
                                                x.reason]
                        UTF8String]));
    CAMLreturn(vout);
  }
}

/* ================================================================= */
#elif defined(__linux__)
/* ================================================================= */

#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <time.h>

/* ---- libsndfile, runtime-resolved ---- */

typedef struct SNDFILE_tag SNDFILE;
typedef long long sf_count_t;
typedef struct {
  sf_count_t frames;
  int samplerate;
  int channels;
  int format;
  int sections;
  int seekable;
} SF_INFO;
typedef sf_count_t (*sf_vio_getlen)(void *);
typedef sf_count_t (*sf_vio_seek)(sf_count_t, int, void *);
typedef sf_count_t (*sf_vio_read)(void *, sf_count_t, void *);
typedef sf_count_t (*sf_vio_write)(const void *, sf_count_t, void *);
typedef sf_count_t (*sf_vio_tell)(void *);
typedef struct {
  sf_vio_getlen get_filelen;
  sf_vio_seek seek;
  sf_vio_read read;
  sf_vio_write write;
  sf_vio_tell tell;
} SF_VIRTUAL_IO;

#define LUI_SFM_READ 0x10

static SNDFILE *(*p_sf_open)(const char *, int, SF_INFO *);
static SNDFILE *(*p_sf_open_virtual)(SF_VIRTUAL_IO *, int, SF_INFO *,
                                     void *);
static sf_count_t (*p_sf_readf_float)(SNDFILE *, float *, sf_count_t);
static int (*p_sf_close)(SNDFILE *);
static int snd_state = 0; /* 0 untried, 1 ok, -1 absent */

static int sym(void *h, const char *n, void **out)
{
  *out = dlsym(h, n);
  return *out != 0;
}

static int snd_resolve(void)
{
  if (snd_state) return snd_state;
  snd_state = -1;
  static const char *names[] = { "libsndfile.so.1", "libsndfile.so", 0 };
  void *h = 0;
  for (int i = 0; names[i] && !h; i++)
    h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
  if (!h) return -1;
  int ok = 1;
  ok &= sym(h, "sf_open", (void **)&p_sf_open);
  ok &= sym(h, "sf_open_virtual", (void **)&p_sf_open_virtual);
  ok &= sym(h, "sf_readf_float", (void **)&p_sf_readf_float);
  ok &= sym(h, "sf_close", (void **)&p_sf_close);
  snd_state = ok ? 1 : -1;
  return snd_state;
}

struct vio_src { const unsigned char *p; sf_count_t len; sf_count_t pos; };

static sf_count_t vio_len(void *ud) { return ((struct vio_src *)ud)->len; }
static sf_count_t vio_seekfn(sf_count_t off, int whence, void *ud)
{
  struct vio_src *m = (struct vio_src *)ud;
  sf_count_t n = m->pos;
  if (whence == SEEK_SET) n = off;
  else if (whence == SEEK_CUR) n += off;
  else if (whence == SEEK_END) n = m->len + off;
  if (n < 0) n = 0;
  if (n > m->len) n = m->len;
  m->pos = n;
  return n;
}
static sf_count_t vio_readfn(void *buf, sf_count_t n, void *ud)
{
  struct vio_src *m = (struct vio_src *)ud;
  sf_count_t avail = m->len - m->pos;
  if (n > avail) n = avail;
  memcpy(buf, m->p + m->pos, (size_t)n);
  m->pos += n;
  return n;
}
static sf_count_t vio_writefn(const void *p, sf_count_t n, void *ud)
{
  (void)p; (void)n; (void)ud;
  return 0;
}
static sf_count_t vio_tellfn(void *ud) { return ((struct vio_src *)ud)->pos; }

/* ---- ffmpeg / ffplay helpers ---- */

static int prog_exists(const char *name)
{
  char cmd[128];
  snprintf(cmd, sizeof(cmd), "command -v %s >/dev/null 2>&1", name);
  return system(cmd) == 0;
}

/* shell-quote: 'x' -> 'x'\''y' */
static void shell_quote(const char *in, char *out, size_t n)
{
  size_t o = 0;
  out[o++] = '\'';
  for (const char *p = in; *p && o + 5 < n; p++) {
    if (*p == '\'') {
      memcpy(out + o, "'\\''", 4);
      o += 4;
    } else
      out[o++] = *p;
  }
  out[o++] = '\'';
  out[o] = '\0';
}

/* Decode through a subprocess: f32le stereo 44100 on stdout. */
static int ffmpeg_decode(const char *path, const void *data, size_t dlen,
                         float **pcm, long *frames, int *rate, int *ch,
                         char *err, size_t errlen)
{
  char tmp[256];
  tmp[0] = '\0';
  const char *src = path;
  if (!src) {
    snprintf(tmp, sizeof(tmp), "/tmp/lui_media_%ld.raw", (long)getpid());
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0 || write(fd, data, dlen) != (ssize_t)dlen) {
      if (fd >= 0) close(fd);
      snprintf(err, errlen, "cannot stage input");
      return 0;
    }
    close(fd);
    src = tmp;
  }
  char q[512], cmd[768];
  shell_quote(src, q, sizeof(q));
  snprintf(cmd, sizeof(cmd),
           "ffmpeg -v error -nostdin -i %s -f f32le -ac 2 -ar 44100 -",
           q);
  FILE *fp = popen(cmd, "r");
  if (!fp) {
    if (tmp[0]) unlink(tmp);
    snprintf(err, errlen, "ffmpeg spawn failed");
    return 0;
  }
  size_t cap = 1 << 20, len = 0;
  unsigned char *buf = (unsigned char *)malloc(cap);
  size_t n;
  while ((n = fread(buf + len, 1, cap - len, fp)) > 0) {
    len += n;
    if (cap - len < 4096) {
      cap *= 2;
      buf = (unsigned char *)realloc(buf, cap);
    }
  }
  int rc = pclose(fp);
  if (tmp[0]) unlink(tmp);
  if (rc != 0 || len < 8) {
    free(buf);
    snprintf(err, errlen, "ffmpeg decode failed");
    return 0;
  }
  *pcm = (float *)buf;
  *frames = (long)(len / 8);
  *rate = 44100;
  *ch = 2;
  err[0] = '\0';
  return 1;
}

static int decode_any(const char *path, const void *data, size_t dlen,
                      float **pcm, long *frames, int *rate, int *ch,
                      char *err, size_t errlen)
{
  if (snd_resolve() == 1) {
    SF_INFO info;
    memset(&info, 0, sizeof(info));
    SNDFILE *f;
    struct vio_src m;
    SF_VIRTUAL_IO vio = { vio_len, vio_seekfn, vio_readfn,
                          vio_writefn, vio_tellfn };
    if (path)
      f = p_sf_open(path, LUI_SFM_READ, &info);
    else {
      m.p = (const unsigned char *)data;
      m.len = (sf_count_t)dlen;
      m.pos = 0;
      f = p_sf_open_virtual(&vio, LUI_SFM_READ, &info, &m);
    }
    if (f) {
      float *buf = (float *)malloc((size_t)info.frames * info.channels * 4);
      if (!buf) {
        p_sf_close(f);
        snprintf(err, errlen, "out of memory");
        return 0;
      }
      sf_count_t got = p_sf_readf_float(f, buf, info.frames);
      p_sf_close(f);
      if (got <= 0) {
        free(buf);
        snprintf(err, errlen, "no samples decoded");
        return 0;
      }
      *pcm = buf;
      *frames = (long)got;
      *rate = info.samplerate;
      *ch = info.channels;
      err[0] = '\0';
      return 1;
    }
  }
  if (prog_exists("ffmpeg"))
    return ffmpeg_decode(path, data, dlen, pcm, frames, rate, ch, err,
                         errlen);
  snprintf(err, errlen, "lui_media: no decoder (libsndfile, ffmpeg)");
  return 0;
}

/* ---- SDL2, runtime-resolved ---- */

typedef uint32_t LUI_SdlDev;
typedef struct {
  int freq;
  uint16_t format;
  uint8_t channels;
  uint8_t silence;
  uint16_t samples;
  uint16_t padding;
  uint32_t size;
  void (*callback)(void *, uint8_t *, int);
  void *userdata;
} LUI_SdlSpec;

#define LUI_SDL_INIT_AUDIO 0x10u
#define LUI_AUDIO_F32 0x8120u
#define LUI_SDL_ALLOW_ANY 15u

static int (*p_SDL_InitSubSystem)(uint32_t);
static LUI_SdlDev (*p_SDL_OpenAudioDevice)(const char *, int,
                                           const LUI_SdlSpec *,
                                           LUI_SdlSpec *, int);
static int (*p_SDL_QueueAudio)(LUI_SdlDev, const void *, uint32_t);
static uint32_t (*p_SDL_GetQueuedAudioSize)(LUI_SdlDev);
static void (*p_SDL_ClearQueuedAudio)(LUI_SdlDev);
static void (*p_SDL_PauseAudioDevice)(LUI_SdlDev, int);
static void (*p_SDL_CloseAudioDevice)(LUI_SdlDev);
static const char *(*p_SDL_GetError)(void);
static int sdl_state = 0;

static int sdl_resolve(void)
{
  if (sdl_state) return sdl_state;
  sdl_state = -1;
  static const char *names[] = { "libSDL2-2.0.so.0", "libSDL2.so", 0 };
  void *h = 0;
  for (int i = 0; names[i] && !h; i++)
    h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
  if (!h) {
    /* SDL may already be linked into the host process. */
    h = dlopen(NULL, RTLD_NOW);
    if (!h) return -1;
  }
  int ok = 1;
  ok &= sym(h, "SDL_InitSubSystem", (void **)&p_SDL_InitSubSystem);
  ok &= sym(h, "SDL_OpenAudioDevice", (void **)&p_SDL_OpenAudioDevice);
  ok &= sym(h, "SDL_QueueAudio", (void **)&p_SDL_QueueAudio);
  ok &= sym(h, "SDL_GetQueuedAudioSize",
            (void **)&p_SDL_GetQueuedAudioSize);
  ok &= sym(h, "SDL_ClearQueuedAudio", (void **)&p_SDL_ClearQueuedAudio);
  ok &= sym(h, "SDL_PauseAudioDevice", (void **)&p_SDL_PauseAudioDevice);
  ok &= sym(h, "SDL_CloseAudioDevice", (void **)&p_SDL_CloseAudioDevice);
  ok &= sym(h, "SDL_GetError", (void **)&p_SDL_GetError);
  sdl_state = ok ? 1 : -1;
  return sdl_state;
}

/* ---- player ---- */

struct lui_player {
  float *pcm;         /* master decode (native rate/channels) */
  float *playbuf;     /* volume-scaled copy queued to SDL */
  long frames;
  int rate;
  int ch;
  int state;
  int loopf;
  float vol;
  int ended;
  long origin;            /* armed frame */
  LUI_SdlDev dev;
  long q_origin;          /* file frame where the queue began */
  long q_frames;          /* frames queued since q_origin */
  /* ffplay fallback */
  char *src_path;         /* kept for ffplay respawn */
  char *src_tmp;          /* tmpfile owning src bytes, or NULL */
  pid_t ff;
  double ff_pos;
  double ff_start;        /* wall clock of the last respawn */
};

static double wall_s(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void player_queue_from(struct lui_player *p, long f)
{
  if (p->dev) {
    p_SDL_ClearQueuedAudio(p->dev);
    p->q_origin = f;
    size_t bpf = (size_t)p->ch * 4;
    p->q_frames = p->frames - f;
    if (p->q_frames > 0)
      p_SDL_QueueAudio(p->dev, (const void *)(p->playbuf + f * p->ch),
                       (uint32_t)((size_t)p->q_frames * bpf));
    else
      p->q_frames = 0;
  }
}

static void player_rescale(struct lui_player *p)
{
  long n = p->frames * p->ch;
  for (long i = 0; i < n; i++) p->playbuf[i] = p->pcm[i] * p->vol;
}

static void ffplay_kill(struct lui_player *p)
{
  if (p->ff > 0) {
    kill(p->ff, SIGKILL);
    waitpid(p->ff, NULL, 0);
    p->ff = -1;
  }
}

static void ffplay_spawn(struct lui_player *p)
{
  const char *src = p->src_tmp ? p->src_tmp : p->src_path;
  if (!src || !prog_exists("ffplay")) return;
  char pos[32];
  snprintf(pos, sizeof(pos), "%.3f", p->ff_pos);
  pid_t pid = fork();
  if (pid == 0) {
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull >= 0) {
      dup2(devnull, 1);
      dup2(devnull, 2);
    }
    execlp("ffplay", "ffplay", "-nodisp", "-autoexit", "-loglevel",
           "error", "-ss", pos, "--", src, (char *)NULL);
    _exit(127);
  }
  if (pid > 0) {
    p->ff = pid;
    p->ff_start = wall_s();
  }
}

static double player_position(struct lui_player *p)
{
  if (p->rate <= 0 || p->frames <= 0) return 0;
  if (p->ff > 0 || p->state == LUI_MED_ENDED) {
    double pos = p->ff_pos + (p->ff > 0 && p->state == LUI_MED_PLAYING
                                  ? wall_s() - p->ff_start
                                  : 0);
    if (pos > (double)p->frames / p->rate)
      pos = (double)p->frames / p->rate;
    return pos;
  }
  if (p->state != LUI_MED_PLAYING && p->state != LUI_MED_PAUSED)
    return (double)p->origin / p->rate;
  uint32_t qb = p->dev ? p_SDL_GetQueuedAudioSize(p->dev) : 0;
  long bpf = (long)p->ch * 4;
  long played = p->q_frames - (long)(qb / (uint32_t)bpf);
  long fr = p->q_origin + played;
  if (p->loopf) {
    fr %= p->frames;
    if (fr < 0) fr += p->frames;
  } else {
    if (fr > p->frames) fr = p->frames;
    if (fr < 0) fr = 0;
  }
  return (double)fr / p->rate;
}

/* Top the queue up while looping; flag ended once a non-looping
   stream drains. Called from the info getter. */
static void player_pump(struct lui_player *p)
{
  if (p->ff > 0) {
    if (waitpid(p->ff, NULL, WNOHANG) == p->ff) {
      p->ff = -1;
      p->ff_pos = (double)p->frames / p->rate;
      if (!p->loopf) {
        p->ended = 1;
        p->state = LUI_MED_ENDED;
      } else {
        p->ff_pos = 0;
        ffplay_spawn(p);
      }
    }
    return;
  }
  if (!p->dev || p->state != LUI_MED_PLAYING) return;
  long bpf = (long)p->ch * 4;
  long qf = (long)(p_SDL_GetQueuedAudioSize(p->dev) / (uint32_t)bpf);
  if (p->loopf) {
    while (qf < p->frames) {
      if (p_SDL_QueueAudio(p->dev, (const void *)p->playbuf,
                           (uint32_t)((size_t)p->frames * bpf)) != 0)
        break;
      p->q_frames += p->frames;
      qf += p->frames;
    }
  } else if (qf == 0 && p->q_frames > 0) {
    p->ended = 1;
    p->state = LUI_MED_ENDED;
  }
}

static struct lui_player *player_of(value v)
{
  return (struct lui_player *)LuiPlayer_val(v);
}

static void lui_player_finalize(value v)
{
  struct lui_player *p = player_of(v);
  if (p) {
    if (p->dev) p_SDL_CloseAudioDevice(p->dev);
    ffplay_kill(p);
    free(p->pcm);
    free(p->playbuf);
    free(p->src_path);
    if (p->src_tmp) {
      unlink(p->src_tmp);
      free(p->src_tmp);
    }
    free(p);
  }
}

static struct custom_operations player_ops = {
  "lui_media.player", lui_player_finalize, custom_compare_default,
  custom_hash_default, custom_serialize_default,
  custom_deserialize_default, custom_compare_ext_default,
  custom_fixed_length_default
};

static int ffplay_ok(void) { return prog_exists("ffplay"); }

/* SDL symbols resolve even on hosts with no audio device (CI runners),
   so probe an actual open once — the same attempt player_open_dev makes
   per playback. */
static int sdl_audio_out_ok(void)
{
  static int state = 0;
  if (state) return state > 0;
  state = -1;
  if (sdl_resolve() != 1 ||
      p_SDL_InitSubSystem(LUI_SDL_INIT_AUDIO) != 0)
    return 0;
  LUI_SdlSpec want;
  memset(&want, 0, sizeof(want));
  want.freq = 44100;
  want.format = LUI_AUDIO_F32;
  want.channels = 1;
  want.samples = 4096;
  want.callback = NULL;
  LUI_SdlDev dev =
      p_SDL_OpenAudioDevice(NULL, 0, &want, NULL, LUI_SDL_ALLOW_ANY);
  if (dev) p_SDL_CloseAudioDevice(dev);
  state = dev ? 1 : -1;
  return state > 0;
}

CAMLprim value lui_media_audio_available(value unit)
{
  CAMLparam1(unit);
  int dec = (snd_resolve() == 1) || prog_exists("ffmpeg");
  int out = sdl_audio_out_ok() || ffplay_ok();
  CAMLreturn(Val_bool(dec && out));
}

CAMLprim value lui_media_decode_available(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool((snd_resolve() == 1) || prog_exists("ffmpeg")));
}

CAMLprim value lui_media_video_available(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool(0));
}

CAMLprim value lui_media_decode(value vsrc, value vis_data)
{
  CAMLparam2(vsrc, vis_data);
  CAMLlocal2(vout, vpcm);
  float *pcm = NULL;
  long frames = 0;
  int rate = 0, ch = 0;
  char err[256];
  err[0] = '\0';
  int is_data = Bool_val(vis_data);
  int ok = decode_any(is_data ? NULL : String_val(vsrc),
                      is_data ? String_val(vsrc) : NULL,
                      is_data ? caml_string_length(vsrc) : 0,
                      &pcm, &frames, &rate, &ch, err, sizeof(err));
  vpcm = caml_alloc_initialized_string(
      ok ? (mlsize_t)frames * ch * 4 : 0, ok ? (const char *)pcm : "");
  free(pcm);
  vout = caml_alloc_tuple(6);
  Store_field(vout, 0, Val_bool(ok));
  Store_field(vout, 1, caml_copy_string(err));
  Store_field(vout, 2, Val_long(frames));
  Store_field(vout, 3, Val_int(rate));
  Store_field(vout, 4, Val_int(ch));
  Store_field(vout, 5, vpcm);
  CAMLreturn(vout);
}

CAMLprim value lui_media_player_create(value unit)
{
  CAMLparam1(unit);
  if (sdl_resolve() != 1 && !ffplay_ok())
    caml_failwith("lui_media: no audio output (SDL2, ffplay)");
  struct lui_player *p =
      (struct lui_player *)calloc(1, sizeof(*p));
  if (!p) caml_failwith("lui_media: out of memory");
  p->state = LUI_MED_STOPPED;
  p->vol = 1.0f;
  p->ff = -1;
  value v = caml_alloc_custom(&player_ops, sizeof(void *),
                              4 * 1024 * 1024, 128 * 1024 * 1024);
  LuiPlayer_val(v) = p;
  CAMLreturn(v);
}

CAMLprim value lui_media_player_load(value v, value vsrc, value vis_data)
{
  CAMLparam3(v, vsrc, vis_data);
  struct lui_player *p = player_of(v);
  float *pcm = NULL;
  long frames = 0;
  int rate = 0, ch = 0;
  char err[256];
  err[0] = '\0';
  int is_data = Bool_val(vis_data);
  if (!decode_any(is_data ? NULL : String_val(vsrc),
                  is_data ? String_val(vsrc) : NULL,
                  is_data ? caml_string_length(vsrc) : 0,
                  &pcm, &frames, &rate, &ch, err, sizeof(err)))
    CAMLreturn(caml_copy_string(err));
  free(p->pcm);
  free(p->playbuf);
  free(p->src_path);
  if (p->src_tmp) {
    unlink(p->src_tmp);
    free(p->src_tmp);
    p->src_tmp = NULL;
  }
  p->pcm = pcm;
  p->playbuf = NULL;
  p->frames = frames;
  p->rate = rate;
  p->ch = ch;
  p->origin = 0;
  p->q_origin = 0;
  p->q_frames = 0;
  p->ended = 0;
  p->state = LUI_MED_STOPPED;
  p->ff_pos = 0;
  /* Keep the source for the ffplay fallback. */
  if (!is_data) {
    p->src_path = strdup(String_val(vsrc));
  } else {
    char tmp[256];
    snprintf(tmp, sizeof(tmp), "/tmp/lui_media_src_%ld.bin",
             (long)getpid());
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) {
      ssize_t nw = write(fd, String_val(vsrc), caml_string_length(vsrc));
      close(fd);
      /* A truncated temp file must not be offered to the ffplay
         fallback, so only keep the path on a complete write. */
      if (nw == (ssize_t)caml_string_length(vsrc))
        p->src_tmp = strdup(tmp);
    }
    p->src_path = NULL;
  }
  if (sdl_resolve() == 1) {
    p->playbuf = (float *)malloc((size_t)frames * ch * 4);
    if (p->playbuf) player_rescale(p);
  }
  CAMLreturn(caml_copy_string(""));
}

static void player_open_dev(struct lui_player *p)
{
  if (p->dev || sdl_resolve() != 1 || !p->playbuf) return;
  if (p_SDL_InitSubSystem(LUI_SDL_INIT_AUDIO) != 0) return;
  LUI_SdlSpec want;
  memset(&want, 0, sizeof(want));
  want.freq = p->rate;
  want.format = LUI_AUDIO_F32;
  want.channels = (uint8_t)p->ch;
  want.samples = 4096;
  want.callback = NULL;
  LUI_SdlDev dev =
      p_SDL_OpenAudioDevice(NULL, 0, &want, NULL, LUI_SDL_ALLOW_ANY);
  if (dev) {
    p->dev = dev;
    p_SDL_PauseAudioDevice(dev, 0);
  }
}

CAMLprim value lui_media_player_play(value v)
{
  CAMLparam1(v);
  struct lui_player *p = player_of(v);
  if (!p->pcm || p->frames <= 0) CAMLreturn(Val_unit);
  if (p->state == LUI_MED_PLAYING) CAMLreturn(Val_unit);
  if (p->state == LUI_MED_PAUSED) {
    if (p->dev) p_SDL_PauseAudioDevice(p->dev, 0);
    else if (p->ff <= 0) ffplay_spawn(p);
    p->state = LUI_MED_PLAYING;
    CAMLreturn(Val_unit);
  }
  long f = p->state == LUI_MED_ENDED ? 0 : p->origin;
  p->ended = 0;
  if (p->playbuf) {
    player_open_dev(p);
    if (p->dev) {
      player_queue_from(p, f);
      p_SDL_PauseAudioDevice(p->dev, 0);
      p->state = LUI_MED_PLAYING;
      CAMLreturn(Val_unit);
    }
  }
  /* ffplay fallback: respawn the source from [f]. */
  p->ff_pos = (double)f / p->rate;
  ffplay_kill(p);
  ffplay_spawn(p);
  p->state = LUI_MED_PLAYING;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_pause(value v)
{
  CAMLparam1(v);
  struct lui_player *p = player_of(v);
  if (p->state == LUI_MED_PLAYING) {
    if (p->dev) p_SDL_PauseAudioDevice(p->dev, 1);
    if (p->ff > 0) {
      p->ff_pos = player_position(p);
      ffplay_kill(p);
    }
    p->state = LUI_MED_PAUSED;
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_stop(value v)
{
  CAMLparam1(v);
  struct lui_player *p = player_of(v);
  if (p->dev) {
    p_SDL_PauseAudioDevice(p->dev, 1);
    p_SDL_ClearQueuedAudio(p->dev);
  }
  ffplay_kill(p);
  p->state = LUI_MED_STOPPED;
  p->origin = 0;
  p->q_origin = 0;
  p->q_frames = 0;
  p->ff_pos = 0;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_unload(value v)
{
  CAMLparam1(v);
  struct lui_player *p = player_of(v);
  if (p->dev) {
    p_SDL_PauseAudioDevice(p->dev, 1);
    p_SDL_ClearQueuedAudio(p->dev);
    p_SDL_CloseAudioDevice(p->dev);
    p->dev = 0;
  }
  ffplay_kill(p);
  free(p->pcm);
  p->pcm = NULL;
  free(p->playbuf);
  p->playbuf = NULL;
  free(p->src_path);
  p->src_path = NULL;
  if (p->src_tmp) {
    unlink(p->src_tmp);
    free(p->src_tmp);
    p->src_tmp = NULL;
  }
  p->frames = 0;
  p->origin = 0;
  p->q_origin = 0;
  p->q_frames = 0;
  p->ended = 0;
  p->state = LUI_MED_STOPPED;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_seek(value v, value vt)
{
  CAMLparam2(v, vt);
  struct lui_player *p = player_of(v);
  double t = Double_val(vt);
  if (t < 0) t = 0;
  long f = (long)(t * p->rate);
  if (f > p->frames) f = p->frames;
  if (f < 0) f = 0;
  if (p->state == LUI_MED_ENDED) p->state = LUI_MED_STOPPED;
  p->origin = f;
  if (p->dev && p->state != LUI_MED_STOPPED)
    player_queue_from(p, f);
  if (p->ff > 0 || p->src_path || p->src_tmp) {
    p->ff_pos = (double)f / p->rate;
    if (p->state == LUI_MED_PLAYING) ffplay_spawn(p);
    else if (p->ff > 0) ffplay_kill(p);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_set_volume(value v, value vvol)
{
  CAMLparam2(v, vvol);
  struct lui_player *p = player_of(v);
  float x = (float)Double_val(vvol);
  if (x < 0) x = 0;
  if (x > 1) x = 1;
  p->vol = x;
  if (p->playbuf && p->pcm) {
    long cur =
        (long)(player_position(p) * p->rate);
    player_rescale(p);
    if (p->dev && p->state != LUI_MED_STOPPED) player_queue_from(p, cur);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_set_loop(value v, value vb)
{
  CAMLparam2(v, vb);
  player_of(v)->loopf = Bool_val(vb) ? 1 : 0;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_media_player_info(value v)
{
  CAMLparam1(v);
  CAMLlocal1(vout);
  struct lui_player *p = player_of(v);
  player_pump(p);
  double dur = p->rate > 0 ? (double)p->frames / p->rate : 0;
  double pos = player_position(p);
  vout = caml_alloc_tuple(5);
  Store_field(vout, 0, caml_copy_double(dur));
  Store_field(vout, 1, caml_copy_double(pos));
  Store_field(vout, 2, Val_int(p->state));
  Store_field(vout, 3, caml_copy_double(p->vol));
  Store_field(vout, 4, Val_int(p->loopf));
  CAMLreturn(vout);
}

CAMLprim value lui_media_player_take_ended(value v)
{
  CAMLparam1(v);
  struct lui_player *p = player_of(v);
  player_pump(p);
  int e = p->ended;
  p->ended = 0;
  CAMLreturn(Val_bool(e));
}

/* Video is unimplemented on Linux: every entry point fails. */

CAMLprim value lui_media_video_open(value vpath)
{
  (void)vpath;
  caml_failwith("lui_media: video not supported on this platform");
  return Val_unit;
}

CAMLprim value lui_media_video_close(value v)
{
  (void)v;
  caml_failwith("lui_media: video not supported on this platform");
  return Val_unit;
}

CAMLprim value lui_media_video_duration(value v)
{
  (void)v;
  caml_failwith("lui_media: video not supported on this platform");
  return Val_unit;
}

CAMLprim value lui_media_video_size(value v)
{
  (void)v;
  caml_failwith("lui_media: video not supported on this platform");
  return Val_unit;
}

CAMLprim value lui_media_video_seek(value v, value vt)
{
  (void)v; (void)vt;
  caml_failwith("lui_media: video not supported on this platform");
  return Val_unit;
}

CAMLprim value lui_media_video_next(value v)
{
  (void)v;
  caml_failwith("lui_media: video not supported on this platform");
  return Val_unit;
}

CAMLprim value lui_media_write_test_video(value vpath, value vw, value vh,
                                          value vsecs)
{
  CAMLparam4(vpath, vw, vh, vsecs);
  CAMLlocal1(vout);
  vout = caml_alloc_tuple(2);
  Store_field(vout, 0, Val_bool(0));
  Store_field(vout, 1,
              caml_copy_string(
                  "lui_media: test video unsupported on this platform"));
  CAMLreturn(vout);
}

/* ================================================================= */
#else
/* ================================================================= */

static value unsupported(void)
{
  caml_failwith("lui_media: not supported on this platform");
  return Val_unit;
}

CAMLprim value lui_media_audio_available(value u)
{ (void)u; return Val_bool(0); }
CAMLprim value lui_media_decode_available(value u)
{ (void)u; return Val_bool(0); }
CAMLprim value lui_media_video_available(value u)
{ (void)u; return Val_bool(0); }
CAMLprim value lui_media_decode(value a, value b)
{ (void)a; (void)b; return unsupported(); }
CAMLprim value lui_media_player_create(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_player_load(value a, value b, value c)
{ (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_media_player_play(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_player_pause(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_player_stop(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_player_unload(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_player_seek(value a, value b)
{ (void)a; (void)b; return unsupported(); }
CAMLprim value lui_media_player_set_volume(value a, value b)
{ (void)a; (void)b; return unsupported(); }
CAMLprim value lui_media_player_set_loop(value a, value b)
{ (void)a; (void)b; return unsupported(); }
CAMLprim value lui_media_player_info(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_player_take_ended(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_video_open(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_video_close(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_video_duration(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_video_size(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_video_seek(value a, value b)
{ (void)a; (void)b; return unsupported(); }
CAMLprim value lui_media_video_next(value a)
{ (void)a; return unsupported(); }
CAMLprim value lui_media_write_test_video(value a, value b, value c,
                                          value d)
{
  (void)a; (void)b; (void)c; (void)d;
  return unsupported();
}

#endif

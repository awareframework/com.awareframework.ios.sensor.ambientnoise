//
//  AmbientNoise.m
//  AWARE
//
//  Created by Yuuki Nishiyama on 11/26/15.
//  Copyright © 2015 Yuuki NISHIYAMA. All rights reserved.
//

#import "ANMonitor.h"
#import "AudioAnalysis.h"

static vDSP_Length const FFTViewControllerFFTWindowSize = 4096;

@implementation ANMonitor {
    
    NSTimer *timer;
    
    float recordingSampleRate;
    float targetSampleRate;
    
    float maxFrequency;
    double db;
    double rms;
    
    float lastdb;
    
    NSString * KEY_AUDIO_CLIP_NUMBER;
    
    CXCallObserver * callObserver;
    
    ANMonitorOutputHadler outputHadler;
}

- (instancetype)init{
   
    if (self != nil) {
        _frequencyMin = 5;
        _sampleSize = 30;
        _silenceThreshold = 50;
        
        recordingSampleRate = 44100;
        targetSampleRate = 8000;
        
        _needRawData = NO;
        
        maxFrequency = 0;
        db = 0;
        rms = 0;
        
        KEY_AUDIO_CLIP_NUMBER = @"key_audio_clip";
    
        
        callObserver = [[CXCallObserver alloc] init];
        [callObserver setDelegate:self queue:nil];
        
        
        [self createRawAudioDataDirectory];
        
    }
    return self;
}

- (void)setANMonitorOutputHadler:(ANMonitorOutputHadler)hadler{
    outputHadler = hadler;
}

-(void) start {
    if (timer == nil) {
        [self setupMicrophone];
        timer = [NSTimer scheduledTimerWithTimeInterval:60.0f*_frequencyMin
                                                 target:self
                                               selector:@selector(startRecording:)
                                               userInfo:[NSDictionary dictionaryWithObject:@0 forKey:KEY_AUDIO_CLIP_NUMBER]
                                                repeats:YES];
        [timer fire];
//        if ([self.delegate respondsToSelector:@selector(analyzerDidStart)]) {
//            [self.delegate analyzerDidStart];
//        }
    }
}


-(void) stop {
    if(timer != nil){
        [timer invalidate];
        timer = nil;
//        if ([self.delegate respondsToSelector:@selector(analyzerDidStop)]) {
//            [self.delegate analyzerDidStop];
//        }
    }
}

//////////////////



- (void)callObserver:(nonnull CXCallObserver *)callObserver
         callChanged:(nonnull CXCall *)call {
    
    if(!call.hasConnected && !call.hasEnded && !call.isOutgoing && !call.isOnHold){
        NSLog(@"Phone call is comming" );
        if(_isRecording) [self stopRecording:[NSDictionary dictionaryWithObject:@(self->_sampleSize) forKey:self->KEY_AUDIO_CLIP_NUMBER]];
    }else if(call.hasEnded){
        NSLog(@"phone call is end");
    }else if(call.outgoing){
        NSLog(@"outgoing call");
        if(_isRecording) [self stopRecording:[NSDictionary dictionaryWithObject:@(self->_sampleSize) forKey:self->KEY_AUDIO_CLIP_NUMBER]];
    }
}

/////////////////////////////////////////////////////////////////////////

-(void)setupMicrophone {
    //https://github.com/syedhali/EZAudio
    //
    // Setup the AVAudioSession. EZMicrophone will not work properly on iOS
    // if you don't do this!
    //
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers |
     AVAudioSessionCategoryOptionDefaultToSpeaker |
     AVAudioSessionCategoryOptionAllowBluetooth
                   error:&error];
    if (error) {
        NSLog(@"Error setting up audio session category: %@", error.localizedDescription);
    }
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"Error setting up audio session active: %@", error.localizedDescription);
    }
    
    AudioStreamBasicDescription absd = [EZAudioUtilities floatFormatWithNumberOfChannels:1 sampleRate:recordingSampleRate];
    //AudioStreamBasicDescription absd = [self monoSIntFormatWithSampleRate:8000];
    
    self.microphone = [EZMicrophone microphoneWithDelegate:self withAudioStreamBasicDescription:absd];
    
}


/**
 * Start recording ambient noise
 */
- (void) startRecording:(id)sender{
    
    // check a phone call status
    NSArray * calls = callObserver.calls;
    if (calls==nil || calls.count == 0) {
        // NSLog(@"NO phone call");
    }else if(calls.count > 0){
        // NSLog(@"the microphone is busy by a phone call");
        return;
    }
    
    // init microphone if it is nil
    if (self.microphone == nil) {
        [self setupMicrophone];
    }
    

    NSNumber * number = @-1;
    if([sender isKindOfClass:[NSTimer class]]){
        NSDictionary * userInfo = ((NSTimer *) sender).userInfo;
        number = [userInfo objectForKey:KEY_AUDIO_CLIP_NUMBER];
    }else if([sender isKindOfClass:[NSDictionary class]]){
        number = [(NSDictionary *)sender objectForKey:KEY_AUDIO_CLIP_NUMBER];
    }else{
        // NSLog(@"An error at ambient noise sensor. There is an unknow userInfo format.");
    }
    
    // if ([self isDebug] && currentSecond == 0) {
    if ([number isEqualToNumber:@0]) {
        // NSLog(@"Start Recording");
        // [AWAREUtils sendLocalNotificationForMessage:@"[Ambient Noise] Start Recording" soundFlag:NO];
    } else if ([number isEqualToNumber:@-1]){
        // NSLog(@"An error at ambient noise sensor...");
    }
    //
    // Create an instance of the EZAudioFFTRolling to keep a history of the incoming audio data and calculate the FFT.
    //
    if(!_fft){
        self.fft = [EZAudioFFTRolling fftWithWindowSize:FFTViewControllerFFTWindowSize
                                             sampleRate:self.microphone.audioStreamBasicDescription.mSampleRate
                                               delegate:self];

    }
    
    if (!_recorder) {
        self.recorder = [EZRecorder recorderWithURL:[self getAudioFilePathWithNumber:[number intValue]]
                                       clientFormat:[self.microphone audioStreamBasicDescription]
                                           fileType:EZRecorderFileTypeM4A
                                           delegate:self];
    }
    
    [self.microphone startFetchingAudio];
    

    _isRecording = YES;
    [self performSelector:@selector(stopRecording:)
               withObject:[NSDictionary dictionaryWithObject:number forKey:KEY_AUDIO_CLIP_NUMBER]
               afterDelay:1];
    
    if (number.intValue == 0){
//        if ([self.delegate respondsToSelector:@selector(analyzerDidResume)]) {
//            [self.delegate analyzerDidResume];
//        }
    }
}


/**
 * Stop recording ambient noise
 */
- (void) stopRecording:(id)sender{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isRecording) {
            int number = -1;
            if(sender != nil){
                number = [[(NSDictionary * )sender objectForKey:self->KEY_AUDIO_CLIP_NUMBER] intValue];
            }
            
            [self saveAudioDataWithNumber:number];
            
            // init variables
            self->maxFrequency = 0;
            self->db = 0;
            self->rms = 0;
            self->lastdb = 0;
            
            self.recorder = nil;
            
            // check a dutyCycle
            if( self->_sampleSize > number ){
                number++;
                [self startRecording:[NSDictionary dictionaryWithObject:@(number) forKey:self->KEY_AUDIO_CLIP_NUMBER]];
            }else{
                // stop fetching audio
                [self.microphone stopFetchingAudio];
                self.microphone.delegate = nil;
                self.microphone = nil;
                // stop recording audio
                [self.recorder closeAudioFile];
                self.recorder.delegate = nil;
                // stop fft
                self.fft.delegate = nil;
                self.fft = nil;
                // init
                number = 0;
                self->_isRecording = NO;
                // NSLog(@"Stop Recording");
                
//                if ([self.delegate respondsToSelector:@selector(analyzerDidSuspend)]) {
//                    [self.delegate analyzerDidSuspend];
//                }
            }
        }
    });
}


////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////

- (void) saveAudioDataWithNumber:(int)number {
    
    // NSString * message = [NSString stringWithFormat:@"[%d] dB:%f, RMS:%f, Frequency:%f", number, db, rms, maxFrequency];
    NSURL * url = [self getAudioFilePathWithNumber:number];
    NSData * rawData = nil;
    
    if(_needRawData){
        rawData = [NSData dataWithContentsOfURL:url];
    }
    
    if ( outputHadler !=nil) {
        outputHadler(maxFrequency,db,rms,rawData,url,number);
    }
//    if ([self.delegate respondsToSelector:@selector(analyzerOutputMaxFrequency:decibel:rootMeanSquare:rawData:audioFileURL:audioId:)]) {
//        [self.delegate analyzerOutputMaxFrequency:maxFrequency decibel:db rootMeanSquare:rms rawData:rawData audioFileURL:url audioId:number];
//    }
}

//////////////////////////////////////////////////////////////////////
// delegate

/**
 Called anytime the EZMicrophone starts or stops.
 
 @param microphone The instance of the EZMicrophone that triggered the event.
 @param isPlaying A BOOL indicating whether the EZMicrophone instance is playing or not.
 */
- (void)microphone:(EZMicrophone *)microphone changedPlayingState:(BOOL)isPlaying{
    
}

//------------------------------------------------------------------------------

/**
 Called anytime the input device changes on an `EZMicrophone` instance.
 @param microphone The instance of the EZMicrophone that triggered the event.
 @param device The instance of the new EZAudioDevice the microphone is using to pull input.
 */
- (void)microphone:(EZMicrophone *)microphone changedDevice:(EZAudioDevice *)device{
    // This is not always guaranteed to occur on the main thread so make sure you
    // wrap it in a GCD block
    dispatch_async(dispatch_get_main_queue(), ^{
        // Update UI here
        NSLog(@"Changed input device: %@", device);
        
    });
}

//------------------------------------------------------------------------------

/**
 Returns back the audio stream basic description as soon as it has been initialized. This is guaranteed to occur before the stream callbacks, `microphone:hasBufferList:withBufferSize:withNumberOfChannels:` or `microphone:hasAudioReceived:withBufferSize:withNumberOfChannels:`
 @param microphone The instance of the EZMicrophone that triggered the event.
 @param audioStreamBasicDescription The AudioStreamBasicDescription that was created for the microphone instance.
 */
- (void)              microphone:(EZMicrophone *)microphone
  hasAudioStreamBasicDescription:(AudioStreamBasicDescription)audioStreamBasicDescription{
    
}

///-----------------------------------------------------------
/// @name Audio Data Callbacks
///-----------------------------------------------------------

/**
 This method provides an array of float arrays of the audio received, each float array representing a channel of audio data This occurs on the background thread so any drawing code must explicity perform its functions on the main thread.
 @param microphone       The instance of the EZMicrophone that triggered the event.
 @param buffer           The audio data as an array of float arrays. In a stereo signal buffer[0] represents the left channel while buffer[1] would represent the right channel.
 @param bufferSize       The size of each of the buffers (the length of each float array).
 @param numberOfChannels The number of channels for the incoming audio.
 @warning This function executes on a background thread to avoid blocking any audio operations. If operations should be performed on any other thread (like the main thread) it should be performed within a dispatch block like so: dispatch_async(dispatch_get_main_queue(), ^{ ...Your Code... })
 */
- (void)    microphone:(EZMicrophone *)microphone
      hasAudioReceived:(float **)buffer
        withBufferSize:(UInt32)bufferSize
  withNumberOfChannels:(UInt32)numberOfChannels{
    // __weak typeof (self) weakSelf = self;
    
    // Getting audio data as an array of float buffer arrays that can be fed into the
    // EZAudioPlot, EZAudioPlotGL, or whatever visualization you would like to do with
    // the microphone data.
    
    //
    // Calculate the FFT, will trigger EZAudioFFTDelegate
    //
    [self.fft computeFFTWithBuffer:buffer[0] withBufferSize:bufferSize];
    
    //
    // Calculate the RMS with buffer and bufferSize
    // NOTE: 1000
    //
    rms = [EZAudioUtilities RMS:*buffer length:bufferSize] * 1000;
    // NSLog(@"%f", rms);
    
    //
    // Decibel Calculation.
    // https://github.com/syedhali/EZAudio/issues/50
    //
    float one       = 1.0;
    float meanVal = 0.0;
    float tiny = 0.1;
    
    vDSP_vsq(buffer[0], 1, buffer[0], 1, bufferSize);
    vDSP_meanv(buffer[0], 1, &meanVal, bufferSize);
    vDSP_vdbcon(&meanVal, 1, &one, &meanVal, 1, 1, 0);
    
    float currentdb = 1.0 - (fabs(meanVal)/100);
    
    if (lastdb == INFINITY || lastdb == -INFINITY || isnan(lastdb)) {
        lastdb = 0.0;
    }
    float tempdb = ((1.0 - tiny)*lastdb) + tiny*currentdb;
    //    if (tempdb == INFINITY && tempdb == -INFINITY) {
    
    bool isInfinity = false;
    if (isinf(tempdb) ){
        NSLog(@"[AmbientNoise] dB is INFINITY");
        tempdb = 0.0;
        isInfinity = true;
    }
    if(isinf(rms) ){
        NSLog(@"[AmbientNoise] RMS is INFINITY");
        rms = 0.0;
        isInfinity = true;
    }
    if(isinf(maxFrequency)){
        NSLog(@"[AmbientNoise] MAX Frequency is INFINITY");
        maxFrequency = 0.0;
        isInfinity = true;
    }
    
    if (!isInfinity){
        db = tempdb;
        lastdb = tempdb;
        dispatch_async(dispatch_get_main_queue(),^{
            // Visualize this data brah, buffer[0] = left channel, buffer[1] = right channel
            //        [weakSelf.audioPlot updateBuffer:buffer[0] withBufferSize:bufferSize];
            // NSString * value = [NSString stringWithFormat:@"dB:%f, RMS:%f, Frequency:%f", self->db, self->rms, self->maxFrequency];;
        });
    }
}

//------------------------------------------------------------------------------

/**
 Returns back the buffer list containing the audio received. This occurs on the background thread so any drawing code must explicity perform its functions on the main thread.
 @param microphone       The instance of the EZMicrophone that triggered the event.
 @param bufferList       The AudioBufferList holding the audio data.
 @param bufferSize       The size of each of the buffers of the AudioBufferList.
 @param numberOfChannels The number of channels for the incoming audio.
 @warning This function executes on a background thread to avoid blocking any audio operations. If operations should be performed on any other thread (like the main thread) it should be performed within a dispatch block like so: dispatch_async(dispatch_get_main_queue(), ^{ ...Your Code... })
 */
- (void)    microphone:(EZMicrophone *)microphone
         hasBufferList:(AudioBufferList *)bufferList
        withBufferSize:(UInt32)bufferSize
  withNumberOfChannels:(UInt32)numberOfChannels{
    if (self.isRecording)
    {
        [self.recorder appendDataFromBufferList:bufferList
                                 withBufferSize:bufferSize];
    }
}


///////////////////////////////////////////////
///////////////////////////////////////////////
// EZRecorderDelegate
/**
 Triggers when the EZRecorder is explicitly closed with the `closeAudioFile` method.
 @param recorder The EZRecorder instance that triggered the action
 */
- (void)recorderDidClose:(EZRecorder *)recorder{
    recorder.delegate = nil;
}

/**
 Triggers after the EZRecorder has successfully written audio data from the `appendDataFromBufferList:withBufferSize:` method.
 @param recorder The EZRecorder instance that triggered the action
 */
- (void)recorderUpdatedCurrentTime:(EZRecorder *)recorder{
    //    __weak typeof (self) weakSelf = self;
    //    NSString *formattedCurrentTime = [recorder formattedCurrentTime];
    //    dispatch_async(dispatch_get_main_queue(), ^{
    //        weakSelf.currentTimeLabel.text = formattedCurrentTime;
    //    });
}


///////////////////////////////////////////////
//////////////////////////////////////////////


- (NSString *)applicationDocumentsDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

- (NSURL *)getAudioFilePathWithNumber:(int)number{
    return [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@/%d_%@",
                                   [self applicationDocumentsDirectory],
                                   kRawAudioDirectory,
                                   number,
                                   kAudioFilePath
                                   ]];
}

- (BOOL) createRawAudioDataDirectory{
    NSString *basePath = [self applicationDocumentsDirectory];
    NSString *newCacheDirPath = [basePath stringByAppendingPathComponent:kRawAudioDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    BOOL created = [fileManager createDirectoryAtPath:newCacheDirPath
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:&error];
    if (!created) {
        NSLog(@"failed to create directory. reason is %@ - %@", error, error.userInfo);
        return NO;
    }else{
        return YES;
    }
}


/////////////////////////////////////////////
///////////////////////////////////////////////
// FFT delegate
- (void)        fft:(EZAudioFFT *)fft
 updatedWithFFTData:(float *)fftData
         bufferSize:(vDSP_Length)bufferSize
{
    maxFrequency = [fft maxFrequency];
    //    NSLog(@"%f", maxFrequency);
    //    [self setLatestValue:[NSString stringWithFormat:@"dB:%f, RMS:%f, Frequency:%f", db, rms, maxFrequency]];
}


@end

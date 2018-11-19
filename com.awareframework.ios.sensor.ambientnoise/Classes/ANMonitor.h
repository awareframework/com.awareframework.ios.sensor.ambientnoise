//
//  AmbientNoise.h
//  AWARE
//
//  Created by Yuuki Nishiyama on 11/26/15.
//  Copyright © 2015 Yuuki NISHIYAMA. All rights reserved.
//

#import <Accelerate/Accelerate.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <GLKit/GLKit.h>
#import <CallKit/CallKit.h>
#import "EZAudio.h"

//
// By default this will record a file to the application's documents directory
// (within the application's sandbox)
//
#define kAudioFilePath @"rawAudio.m4a"
#define kRawAudioDirectory @"rawAudioData"

@interface ANMonitor : NSObject <EZMicrophoneDelegate, EZRecorderDelegate, EZAudioFFTDelegate, CXCallObserverDelegate>

typedef void (^ANMonitorOutputHadler)(float mf, double db, double rms, NSData * _Nullable raw, NSURL * audioFileURL, int audioId);

// @property (weak, nonatomic) id <ANAnalyzerDelegate> delegate;

//
// The microphone component
//
@property (nonatomic, strong) EZMicrophone *microphone;

//
// The recorder component
//
@property (nonatomic, strong) EZRecorder *recorder;

//
// Used to calculate a rolling FFT of the incoming audio data.
//
@property (nonatomic, strong) EZAudioFFTRolling *fft;

//
// A flag indicating whether we are recording or not
//
@property (nonatomic, assign, readonly) BOOL isRecording;

@property int frequencyMin;
@property int sampleSize;
@property int silenceThreshold;
@property BOOL needRawData;

- (void) setANMonitorOutputHadler:(ANMonitorOutputHadler)hadler;

- (void) start;
- (void) stop;

@end

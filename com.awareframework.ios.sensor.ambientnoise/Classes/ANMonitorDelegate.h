//
//  ANAnalyzerDelegate.h
//  com.aware.ios.sensor.ambientnoise
//
//  Created by Yuuki Nishiyama on 2018/11/13.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol ANMonitorDelegate <NSObject>
@required
- (void) monitorOutputMaxFrequency:(float)mf decibel:(double)db rootMeanSquare:(double)rms rawData:(NSData * _Nullable)raw audioFileURL:(NSURL *)url audioId:(int)audioId;
- (void) monitorDidStart;
- (void) monitorDidResume;
- (void) monitorDidSuspend;
- (void) monitorDidStop;

@end
NS_ASSUME_NONNULL_END

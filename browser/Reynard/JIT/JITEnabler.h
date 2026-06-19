//
//  JITEnabler.h
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface JITEnabler : NSObject

@property(class, nonatomic, readonly) JITEnabler *shared;

- (BOOL)enableJITForPID:(int32_t)pid
               hasTXM26:(BOOL)hasTXM26
                  error:(NSError *_Nullable *_Nullable)error

NS_SWIFT_NAME(enableJIT(forPID:hasTXM26:));

- (void)detachAllJITSessions NS_SWIFT_NAME(detachAllJITSessions());

@end

NS_ASSUME_NONNULL_END

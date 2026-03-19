//
//  JITEnabler.h
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

typedef void (^LogHandler)(NSString *message);

@interface JITEnabler : NSObject

@property(class, nonatomic, readonly) JITEnabler *shared;

- (BOOL)enableJITForPID:(int32_t)pid
             logHandler:(nullable LogHandler)logHandler
                  error:(NSError *_Nullable *_Nullable)error

    NS_SWIFT_NAME(enableJIT(forPID:logHandler:));

@end

NS_ASSUME_NONNULL_END

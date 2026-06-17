//
//  GeckoRuntimeBridge.mm
//  Reynard
//
//  Created by Minh Ton on 24/5/26.
//

#import "GeckoRuntimeBridge.h"

#import "mozilla-config.h"

@implementation GeckoRuntimeBridge

+ (NSString *)version {
  return @MOZILLA_VERSION;
}

@end

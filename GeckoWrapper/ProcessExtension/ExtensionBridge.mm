//
//  ReynardExtensionBridge.mm
//  Reynard
//

#import "ExtensionBridge.h"

@interface NSXPCConnection (Private)
- (xpc_connection_t _Nullable)_xpcConnection;
@end

xpc_connection_t _Nullable XPCConnectionFromNSXPC(
    NSXPCConnection *_Nonnull aConnection) {
  if (![aConnection respondsToSelector:@selector(_xpcConnection)]) {
    return nil;
  }
  return [aConnection _xpcConnection];
}

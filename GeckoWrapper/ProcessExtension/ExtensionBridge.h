//
//  ReynardExtensionBridge.h
//  Reynard
//

#ifndef ReynardExtensionBridge_h
#define ReynardExtensionBridge_h

#import <Foundation/Foundation.h>
#import <xpc/xpc.h>

#ifdef __cplusplus
extern "C" {
#endif

xpc_connection_t _Nullable XPCConnectionFromNSXPC(
    NSXPCConnection *_Nonnull aConnection);

#ifdef __cplusplus
}
#endif

#endif /* ReynardExtensionBridge_h */

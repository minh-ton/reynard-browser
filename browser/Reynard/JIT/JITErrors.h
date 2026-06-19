//
//  JITErrors.h
//  Reynard
//
//  Created by Minh Ton on 22/3/26.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const ErrorDomain;

FOUNDATION_EXPORT NSString *const ErrorCategory;

typedef NS_ENUM(NSInteger, ErrorGroup) {
    ErrorGroupUnknown = 0,
    ErrorGroupSharedSetup = 1,
    ErrorGroupModernPath = 2,
    ErrorGroupPairing = 3,
    ErrorGroupProtocol = 4,
    ErrorGroupTrollStore = 5,
};

typedef NS_ERROR_ENUM(ErrorDomain, ErrorCode){
    // Pairing and bootstrap setup
    PairingFileMissing = -1,
    InvalidTargetAddress = -2,
    DeviceProviderAllocationFailed = -3,
    DeviceProviderCreateFailed = -4,
    PairingFileReadFailed = -5,
    HeartbeatConnectFailed = -6,
    
    // RSD service bootstrap
    LockdowndConnectFailed = -7,
    
    // Attach
    ProcessControlCreateFailed = -8,
    RemoteServerConnectFailed = -9,
    DebugProxyConnectFailed = -10,
    NoAckConfigureFailed = -11,
    AttachDebugProxyFailed = -12,
    SessionAllocationFailed = -13,
    
    // Protocol handling and command execution
    DebugCommandCreateFailed = -14,
    DebugCommandSendFailed = -15,
    UnexpectedRegisterWriteResponse = -16,
    UnexpectedNoAckResponse = -17,
    MemoryPrepareReadFailed = -18,
    UnexpectedPrepareRegionResponse = -19,
    
    // Developer Disk Image mounting
    DDIMountPathResolveFailed = -20,
    DDIFileReadFailed = -21,
    ImageMounterConnectFailed = -22,
    DDIMountStateQueryFailed = -23,
    UniqueChipIDReadFailed = -24,
    UniqueChipIDInvalid = -25,
    ModernDDIMountFailed = -26,
    
    // Runtime connectivity monitoring
    EndpointConnectivityLost = -27,
    
    // RPPairing tunnel
    TunnelCreateFailed = -28,
    
    // TrollStore ptrace attach path
    TSPtraceHelperMissing = -29,
    TSPtraceHelperAttachFailed = -30,
    TSPtraceHelperTerminated = -31,
};

NSString *ErrorDescription(ErrorCode code);
ErrorGroup ErrorGroupForCode(ErrorCode code);
NSError *MakeError(ErrorCode code);

NS_ASSUME_NONNULL_END

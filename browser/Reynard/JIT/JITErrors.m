//
//  JITErrors.m
//  Reynard
//
//  Created by Minh Ton on 22/3/26.
//

#import "JITErrors.h"

NSErrorDomain const ErrorDomain = @"Reynard.JIT";
NSString *const ErrorCategory = @"ErrorCategory";

NSString *ErrorDescription(ErrorCode code) {
    switch (code) {
        case PairingFileMissing:
            return @"Pairing file was not found.";
        case InvalidTargetAddress:
            return @"Target address is invalid.";
        case DeviceProviderAllocationFailed:
            return @"Failed to allocate device provider.";
        case DeviceProviderCreateFailed:
            return @"Failed to create device provider.";
        case PairingFileReadFailed:
            return @"Failed to read pairing file for provider.";
        case HeartbeatConnectFailed:
            return @"Failed to connect heartbeat service.";
        case LockdowndConnectFailed:
            return @"Failed to connect lockdownd service over RSD.";
        case ProcessControlCreateFailed:
            return @"Failed to create process control client.";
        case RemoteServerConnectFailed:
            return @"Failed to connect remote server.";
        case DebugProxyConnectFailed:
            return @"Failed to connect debug proxy.";
        case NoAckConfigureFailed:
            return @"Failed to configure no-ack mode.";
        case AttachDebugProxyFailed:
            return @"Failed to attach debug proxy.";
        case SessionAllocationFailed:
            return @"Failed to allocate debug session.";
        case DebugCommandCreateFailed:
            return @"Failed to create debug command.";
        case DebugCommandSendFailed:
            return @"Failed to send debug command.";
        case UnexpectedRegisterWriteResponse:
            return @"Unexpected register write response.";
        case UnexpectedNoAckResponse:
            return @"Unexpected no-ack response.";
        case MemoryPrepareReadFailed:
            return @"Failed to read source memory for prepare-region.";
        case UnexpectedPrepareRegionResponse:
            return @"Unexpected prepare-region response.";
        case DDIMountPathResolveFailed:
            return @"Unable to resolve the DDI directory path.";
        case DDIFileReadFailed:
            return @"Failed to read required DDI files from disk.";
        case ImageMounterConnectFailed:
            return @"Failed to connect MobileImageMounter service.";
        case DDIMountStateQueryFailed:
            return @"Failed to query current DDI mount state.";
        case UniqueChipIDReadFailed:
            return @"Failed to read UniqueChipID from lockdownd over RSD.";
        case UniqueChipIDInvalid:
            return @"UniqueChipID value is invalid.";
        case ModernDDIMountFailed:
            return @"Failed to mount personalized DDI image.";
        case EndpointConnectivityLost:
            return @"Lost TCP connectivity to the JIT debug endpoint.";
        case TunnelCreateFailed:
            return @"Failed to create RPPairing tunnel.";
        case TSPtraceHelperMissing:
            return @"Bundled ptrace_jit is missing or not executable.";
        case TSPtraceHelperAttachFailed:
            return @"ptrace_jit failed to attach to the child process.";
        case TSPtraceHelperTerminated:
            return @"ptrace_jit terminated before it could attach to the child process.";
    }
    
    return @"Unknown error.";
}

ErrorGroup ErrorGroupForCode(ErrorCode code) {
    switch (code) {
        case PairingFileMissing:
        case PairingFileReadFailed:
            return ErrorGroupPairing;
        case InvalidTargetAddress:
        case DeviceProviderAllocationFailed:
        case DeviceProviderCreateFailed:
        case HeartbeatConnectFailed:
        case DDIMountPathResolveFailed:
        case DDIFileReadFailed:
        case ImageMounterConnectFailed:
        case EndpointConnectivityLost:
            return ErrorGroupSharedSetup;
        case LockdowndConnectFailed:
        case ProcessControlCreateFailed:
        case RemoteServerConnectFailed:
        case DebugProxyConnectFailed:
        case NoAckConfigureFailed:
        case AttachDebugProxyFailed:
        case SessionAllocationFailed:
        case UniqueChipIDReadFailed:
        case UniqueChipIDInvalid:
        case ModernDDIMountFailed:
        case TunnelCreateFailed:
            return ErrorGroupModernPath;
        case TSPtraceHelperMissing:
        case TSPtraceHelperAttachFailed:
        case TSPtraceHelperTerminated:
            return ErrorGroupTrollStore;
        case DebugCommandCreateFailed:
        case DebugCommandSendFailed:
        case UnexpectedRegisterWriteResponse:
        case UnexpectedNoAckResponse:
        case MemoryPrepareReadFailed:
        case UnexpectedPrepareRegionResponse:
        case DDIMountStateQueryFailed:
            return ErrorGroupProtocol;
    }
    
    return ErrorGroupUnknown;
}

NSError *MakeError(ErrorCode code) {
    return [NSError errorWithDomain:ErrorDomain
                               code:code
                           userInfo:@{
        NSLocalizedDescriptionKey: ErrorDescription(code),
        ErrorCategory: @(ErrorGroupForCode(code)),
    }];
}

//
//  JITUtils.h
//  Reynard
//
//  Created by Minh Ton on 18/3/2026.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

void logger(NSString *message);
NSString *pairingFilePath(void);

uint64_t parseLittleEndianHex64(NSString *hexString);
NSString *encodeLittleEndianHex64(uint64_t value);
NSString *_Nullable packetField(NSString *packet, NSString *fieldName);
NSString *_Nullable packetSignal(NSString *packet);
BOOL instructionIsBreakpoint(uint32_t instruction);
BOOL isNotConnectedError(NSError *error);

NS_ASSUME_NONNULL_END

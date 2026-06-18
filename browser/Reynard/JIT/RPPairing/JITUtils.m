//
//  JITUtils.m
//  Reynard
//
//  Created by Minh Ton on 18/3/2026.
//

#import "JITUtils.h"

void logger(NSString *message) {
    NSLog(@"[REYNARD_DEBUG] %@", message);
}

NSString *pairingFilePath(void) {
    NSURL *documentsDirectory = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    if (!documentsDirectory) return @"";
    return [[documentsDirectory URLByAppendingPathComponent:@"pairingFile.plist"] path] ?: @"";
}

uint64_t parseLittleEndianHex64(NSString *hexString) {
    uint64_t value = 0;
    NSUInteger length = hexString.length;
    for (NSUInteger index = 0; index + 1 < length; index += 2) {
        NSString *byteString = [hexString substringWithRange:NSMakeRange(index, 2)];
        unsigned byteValue = 0;
        [[NSScanner scannerWithString:byteString] scanHexInt:&byteValue];
        value |= ((uint64_t)(byteValue & 0xff)) << ((index / 2) * 8);
    }
    return value;
}

NSString *encodeLittleEndianHex64(uint64_t value) {
    NSMutableString *hex = [NSMutableString stringWithCapacity:16];
    for (NSUInteger index = 0; index < 8; index++) [hex appendFormat:@"%02llx", (value >> (index * 8)) & 0xffull];
    return hex;
}

NSString *packetField(NSString *packet, NSString *fieldName) {
    NSString *needle = [fieldName stringByAppendingString:@":"];
    NSRange startRange = [packet rangeOfString:needle];
    if (startRange.location == NSNotFound) return nil;
    
    NSUInteger valueStart = NSMaxRange(startRange);
    NSRange searchRange = NSMakeRange(valueStart, packet.length - valueStart);
    NSRange endRange = [packet rangeOfString:@";" options:0 range:searchRange];
    if (endRange.location == NSNotFound) return nil;
    
    return [packet substringWithRange:NSMakeRange(valueStart, endRange.location - valueStart)];
}

NSString *packetSignal(NSString *packet) {
    if (packet.length < 3 || ![packet hasPrefix:@"T"]) return nil;
    return [packet substringWithRange:NSMakeRange(1, 2)];
}

BOOL instructionIsBreakpoint(uint32_t instruction) {
    return (instruction & 0xFFE0001Fu) == 0xD4200000u;
}

BOOL isNotConnectedError(NSError *error) {
    NSString *description = error.localizedDescription;
    if (!description) return NO;
    return [description containsString:@"NotConnected"] || [description containsString:@"not connected"];
}

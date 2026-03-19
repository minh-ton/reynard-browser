//
//  JITUtils.m
//  Reynard
//
//  Created by Minh Ton on 18/3/2026.
//

#import "JITUtils.h"

#include <errno.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static const NSTimeInterval debugPacketTimeoutSeconds = 2.0;

NSError *errorWithCode(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:@"Reynard.JIT" code:code userInfo:@{NSLocalizedDescriptionKey: description}];
}

void logger(NSString *message, void (^logHandler)(NSString *message)) {
    if (logHandler) logHandler(message);
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

NSString *secureTransportStatusDescription(OSStatus status) {
    CFStringRef errorString = SecCopyErrorMessageString(status, NULL);
    if (errorString) {
        NSString *description = [(__bridge NSString *)errorString copy];
        CFRelease(errorString);
        return description;
    }
    
    return [NSString stringWithFormat:@"OSStatus %d", (int)status];
}

NSData *decodePEMData(NSData *sourceData, NSString *beginMarker, NSString *endMarker) {
    if (!sourceData || sourceData.length == 0) return nil;
    
    NSString *rawString = [[NSString alloc] initWithData:sourceData encoding:NSUTF8StringEncoding];
    if (!rawString) return sourceData;
    
    NSRange beginRange = [rawString rangeOfString:beginMarker];
    NSRange endRange = [rawString rangeOfString:endMarker options:NSBackwardsSearch];
    if (beginRange.location == NSNotFound || endRange.location == NSNotFound) return sourceData;
    if (endRange.location <= beginRange.location) return sourceData;
    
    NSUInteger payloadStart = NSMaxRange(beginRange);
    NSUInteger payloadLength = endRange.location - payloadStart;
    NSString *base64Body = [rawString substringWithRange:NSMakeRange(payloadStart, payloadLength)];
    NSMutableString *filteredBase64 = [NSMutableString stringWithCapacity:base64Body.length];
    NSCharacterSet *validBase64Chars = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="];
    for (NSUInteger idx = 0; idx < base64Body.length; idx++) {
        unichar character = [base64Body characterAtIndex:idx];
        if ([validBase64Chars characterIsMember:character]) [filteredBase64 appendFormat:@"%C", character];
    }
    
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:filteredBase64 options:0];
    return decodedData ?: sourceData;
}

NSData *decodeRawBase64Data(NSData *sourceData) {
    if (!sourceData || sourceData.length == 0) return sourceData;
    
    NSString *rawString = [[NSString alloc] initWithData:sourceData encoding:NSUTF8StringEncoding];
    if (!rawString) return sourceData;
    
    NSString *trimmed = [[rawString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    if (trimmed.length == 0) return sourceData;
    
    NSCharacterSet *validBase64Chars = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="];
    for (NSUInteger idx = 0; idx < trimmed.length; idx++) {
        if (![validBase64Chars characterIsMember:[trimmed characterAtIndex:idx]]) return sourceData;
    }
    
    NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:trimmed options:0];
    return (decodedData.length > 0) ? decodedData : sourceData;
}

NSData *asn1EncodeLength(NSUInteger length) {
    if (length < 0x80) {
        uint8_t singleByte = (uint8_t)length;
        return [NSData dataWithBytes:&singleByte length:1];
    }
    
    uint8_t lengthBytes[sizeof(NSUInteger)] = {0};
    NSUInteger cursor = sizeof(NSUInteger);
    NSUInteger value = length;
    while (value > 0 && cursor > 0) {
        cursor--;
        lengthBytes[cursor] = (uint8_t)(value & 0xFF);
        value >>= 8;
    }
    
    NSUInteger usedBytes = sizeof(NSUInteger) - cursor;
    NSMutableData *encoded = [NSMutableData dataWithCapacity:usedBytes + 1];
    uint8_t firstByte = (uint8_t)(0x80 | usedBytes);
    [encoded appendBytes:&firstByte length:1];
    [encoded appendBytes:lengthBytes + cursor length:usedBytes];
    return encoded;
}

BOOL decodeASN1Length(const uint8_t *bytes, NSUInteger totalLength, NSUInteger *offset, NSUInteger *decodedLength) {
    if (!bytes || !offset || !decodedLength || *offset >= totalLength) return NO;
    
    uint8_t firstByte = bytes[(*offset)++];
    if ((firstByte & 0x80) == 0) {
        *decodedLength = firstByte;
        return YES;
    }
    
    uint8_t lengthBytesCount = (uint8_t)(firstByte & 0x7F);
    if (lengthBytesCount == 0 || lengthBytesCount > sizeof(NSUInteger)) return NO;
    if (*offset + lengthBytesCount > totalLength) return NO;
    
    NSUInteger value = 0;
    for (uint8_t idx = 0; idx < lengthBytesCount; idx++) {
        value = (value << 8) | bytes[*offset + idx];
    }
    
    *offset += lengthBytesCount;
    *decodedLength = value;
    return YES;
}

NSData *asn1Wrap(uint8_t tag, NSData *payload) {
    if (!payload) return nil;
    NSMutableData *wrapped = [NSMutableData dataWithCapacity:payload.length + 8];
    [wrapped appendBytes:&tag length:1];
    [wrapped appendData:asn1EncodeLength(payload.length)];
    [wrapped appendData:payload];
    return wrapped;
}

NSData *wrapRSAPKCS1PrivateKeyAsPKCS8(NSData *pkcs1Key) {
    if (!pkcs1Key || pkcs1Key.length == 0) return nil;
    
    static const uint8_t version0[] = { 0x02, 0x01, 0x00 };
    static const uint8_t rsaAlgorithmIdentifier[] = {
        0x30, 0x0D, 0x06, 0x09,
        0x2A, 0x86, 0x48, 0x86,
        0xF7, 0x0D, 0x01, 0x01,
        0x01, 0x05, 0x00
    };
    
    NSMutableData *pkcs8Body = [NSMutableData data];
    [pkcs8Body appendBytes:version0 length:sizeof(version0)];
    [pkcs8Body appendBytes:rsaAlgorithmIdentifier length:sizeof(rsaAlgorithmIdentifier)];
    [pkcs8Body appendData:asn1Wrap(0x04, pkcs1Key)];
    
    return asn1Wrap(0x30, pkcs8Body);
}

NSData *extractPKCS1PrivateKeyFromPKCS8(NSData *pkcs8Key) {
    if (!pkcs8Key || pkcs8Key.length < 16) return nil;
    
    const uint8_t *bytes = pkcs8Key.bytes;
    NSUInteger totalLength = pkcs8Key.length;
    NSUInteger offset = 0;
    NSUInteger fieldLength = 0;
    
    if (bytes[offset++] != 0x30) return nil;
    if (!decodeASN1Length(bytes, totalLength, &offset, &fieldLength)) return nil;
    if (offset + fieldLength > totalLength) return nil;
    NSUInteger sequenceEnd = offset + fieldLength;
    
    if (offset >= sequenceEnd || bytes[offset++] != 0x02) return nil;
    if (!decodeASN1Length(bytes, sequenceEnd, &offset, &fieldLength)) return nil;
    if (offset + fieldLength > sequenceEnd) return nil;
    offset += fieldLength;
    
    if (offset >= sequenceEnd || bytes[offset++] != 0x30) return nil;
    if (!decodeASN1Length(bytes, sequenceEnd, &offset, &fieldLength)) return nil;
    if (offset + fieldLength > sequenceEnd) return nil;
    offset += fieldLength;
    
    if (offset >= sequenceEnd || bytes[offset++] != 0x04) return nil;
    if (!decodeASN1Length(bytes, sequenceEnd, &offset, &fieldLength)) return nil;
    if (offset + fieldLength > sequenceEnd) return nil;
    
    return [NSData dataWithBytes:bytes + offset length:fieldLength];
}

SecKeyRef createPrivateKeyFromPairingData(NSData *privateKeyData) {
    if (!privateKeyData || privateKeyData.length == 0) return NULL;
    
    NSData *rsaPrivateKeyCandidate = extractPKCS1PrivateKeyFromPKCS8(privateKeyData) ?: privateKeyData;
    
    NSDictionary *rsaAttributes = @{ (id)kSecAttrKeyType: (id)kSecAttrKeyTypeRSA, (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPrivate };
    
    CFErrorRef createError = NULL;
    SecKeyRef privateKey = SecKeyCreateWithData((__bridge CFDataRef)rsaPrivateKeyCandidate, (__bridge CFDictionaryRef)rsaAttributes, &createError);
    if (privateKey || !createError) return privateKey;
    CFRelease(createError);
    
    NSData *pkcs8WrappedData = wrapRSAPKCS1PrivateKeyAsPKCS8(privateKeyData);
    if (pkcs8WrappedData.length > 0) {
        privateKey = SecKeyCreateWithData((__bridge CFDataRef)pkcs8WrappedData, (__bridge CFDictionaryRef)rsaAttributes, NULL);
        if (privateKey) return privateKey;
    }
    
    NSDictionary *ecAttributes = @{ (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom, (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPrivate };
    
    CFErrorRef ecCreateError = NULL;
    privateKey = SecKeyCreateWithData((__bridge CFDataRef)privateKeyData, (__bridge CFDictionaryRef)ecAttributes, &ecCreateError);
    if (privateKey || !ecCreateError) return privateKey;
    
    CFRelease(ecCreateError);
    return NULL;
}

SecIdentityRef copyLegacyPairingIdentity(NSError **error) {
    NSURL *documentsDirectory = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSString *pairingFilePath = [[documentsDirectory URLByAppendingPathComponent:@"pairingFile.plist"] path];
    if (pairingFilePath.length == 0) {
        if (error) *error = errorWithCode(-24, @"Unable to resolve pairing file path for TLS debugserver session.");
        return NULL;
    }
    
    NSDictionary *pairingDictionary = [NSDictionary dictionaryWithContentsOfFile:pairingFilePath];
    if (![pairingDictionary isKindOfClass:[NSDictionary class]]) {
        if (error) *error = errorWithCode(-24, @"Failed loading pairing file for TLS debugserver session.");
        return NULL;
    }
    
    NSData *hostCertificateRaw = pairingDictionary[@"HostCertificate"];
    NSData *hostPrivateKeyRaw = pairingDictionary[@"HostPrivateKey"];
    if (![hostCertificateRaw isKindOfClass:[NSData class]] || ![hostPrivateKeyRaw isKindOfClass:[NSData class]]) {
        if (error) *error = errorWithCode(-24, @"Pairing file is missing HostCertificate/HostPrivateKey data.");
        return NULL;
    }
    
    NSData *hostCertificateData = decodePEMData(hostCertificateRaw, @"-----BEGIN CERTIFICATE-----",  @"-----END CERTIFICATE-----");
    NSData *hostPrivateKeyData = decodePEMData(hostPrivateKeyRaw, @"-----BEGIN PRIVATE KEY-----", @"-----END PRIVATE KEY-----");
    if ([hostPrivateKeyData isEqual:hostPrivateKeyRaw]) hostPrivateKeyData = decodePEMData(hostPrivateKeyRaw, @"-----BEGIN RSA PRIVATE KEY-----", @"-----END RSA PRIVATE KEY-----");
    if ([hostPrivateKeyData isEqual:hostPrivateKeyRaw]) hostPrivateKeyData = decodePEMData(hostPrivateKeyRaw, @"-----BEGIN EC PRIVATE KEY-----", @"-----END EC PRIVATE KEY-----");
    if ([hostPrivateKeyData isEqual:hostPrivateKeyRaw]) hostPrivateKeyData = decodeRawBase64Data(hostPrivateKeyRaw);
    
    SecCertificateRef hostCertificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)hostCertificateData);
    if (!hostCertificate) {
        if (error) *error = errorWithCode(-24, @"Failed parsing HostCertificate from pairing file.");
        return NULL;
    }
    
    SecKeyRef privateKey = createPrivateKeyFromPairingData(hostPrivateKeyData);
    if (!privateKey) {
        if (error) *error = errorWithCode(-24, @"Failed parsing HostPrivateKey from pairing file.");
        CFRelease(hostCertificate);
        return NULL;
    }
    
    SecIdentityRef identity = SecIdentityCreate(NULL, hostCertificate, privateKey);
    CFRelease(privateKey);
    CFRelease(hostCertificate);
    
    if (!identity) {
        if (error) *error = errorWithCode(-24, @"Failed creating TLS identity from pairing certificate/private key.");
        return NULL;
    }
    
    return identity;
}

OSStatus legacySSLRead(SSLConnectionRef connection, void *data, size_t *dataLength) {
    if (!connection || !data || !dataLength) return errSecParam;
    
    int socketFD = *(int *)connection;
    ssize_t result = recv(socketFD, data, *dataLength, 0);
    if (result > 0) {
        *dataLength = (size_t)result;
        return noErr;
    }
    
    if (result == 0) {
        *dataLength = 0;
        return errSSLClosedGraceful;
    }
    
    if (errno == EINTR) return legacySSLRead(connection, data, dataLength);
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
        *dataLength = 0;
        return errSSLWouldBlock;
    }
    
    *dataLength = 0;
    return errSecIO;
}

OSStatus legacySSLWrite(SSLConnectionRef connection, const void *data, size_t *dataLength) {
    if (!connection || !data || !dataLength) return errSecParam;
    
    int socketFD = *(int *)connection;
    ssize_t result = send(socketFD, data, *dataLength, 0);
    if (result >= 0) {
        *dataLength = (size_t)result;
        return noErr;
    }
    
    if (errno == EINTR) return legacySSLWrite(connection, data, dataLength);
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
        *dataLength = 0;
        return errSSLWouldBlock;
    }
    
    *dataLength = 0;
    return errSecIO;
}

uint8_t packetChecksum(const uint8_t *bytes, size_t length) {
    uint8_t checksum = 0;
    for (size_t index = 0; index < length; index++) checksum = (uint8_t)(checksum + bytes[index]);
    return checksum;
}

void applyLegacyDebugSocketTimeouts(int socketFD) {
    struct timeval timeoutValue;
    timeoutValue.tv_sec = (time_t)debugPacketTimeoutSeconds;
    timeoutValue.tv_usec = (suseconds_t)((debugPacketTimeoutSeconds - timeoutValue.tv_sec) * 1000000.0);
    setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeoutValue, sizeof(timeoutValue));
    setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeoutValue, sizeof(timeoutValue));
}

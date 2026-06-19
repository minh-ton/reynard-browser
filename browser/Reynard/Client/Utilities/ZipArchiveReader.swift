//
//  ZipArchiveReader.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import Foundation
import zlib

enum ZipArchiveReader {
    static func entryData(in archiveData: Data, path: String) -> Data? {
        guard let endOfCentralDirectoryOffset = endOfCentralDirectoryOffset(in: archiveData) else {
            return nil
        }
        
        let entryCount = Int(readUInt16(in: archiveData, at: endOfCentralDirectoryOffset + 10))
        var offset = Int(readUInt32(in: archiveData, at: endOfCentralDirectoryOffset + 16))
        
        for _ in 0..<entryCount {
            guard readUInt32(in: archiveData, at: offset) == 0x02014B50 else {
                return nil
            }
            
            let compressionMethod = readUInt16(in: archiveData, at: offset + 10)
            let compressedSize = Int(readUInt32(in: archiveData, at: offset + 20))
            let uncompressedSize = Int(readUInt32(in: archiveData, at: offset + 24))
            let fileNameLength = Int(readUInt16(in: archiveData, at: offset + 28))
            let extraFieldLength = Int(readUInt16(in: archiveData, at: offset + 30))
            let commentLength = Int(readUInt16(in: archiveData, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(in: archiveData, at: offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + fileNameLength
            
            guard let fileName = String(data: archiveData.subdata(in: nameStart..<nameEnd), encoding: .utf8) else {
                return nil
            }
            
            if fileName == path {
                return localEntryData(
                    in: archiveData,
                    localHeaderOffset: localHeaderOffset,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize
                )
            }
            
            offset = nameEnd + extraFieldLength + commentLength
        }
        
        return nil
    }
    
    private static func localEntryData(
        in archiveData: Data,
        localHeaderOffset: Int,
        compressionMethod: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) -> Data? {
        guard readUInt32(in: archiveData, at: localHeaderOffset) == 0x04034B50 else {
            return nil
        }
        
        let fileNameLength = Int(readUInt16(in: archiveData, at: localHeaderOffset + 26))
        let extraFieldLength = Int(readUInt16(in: archiveData, at: localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + fileNameLength + extraFieldLength
        let dataEnd = dataStart + compressedSize
        guard archiveData.count >= dataEnd else {
            return nil
        }
        
        let compressedData = archiveData.subdata(in: dataStart..<dataEnd)
        switch compressionMethod {
        case 0:
            return compressedData
        case 8:
            return inflate(data: compressedData, expectedSize: uncompressedSize)
        default:
            return nil
        }
    }
    
    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        let minimumSize = 22
        guard data.count >= minimumSize else {
            return nil
        }
        
        let startOffset = max(0, data.count - 65557)
        let signature: UInt32 = 0x06054B50
        for offset in stride(from: data.count - minimumSize, through: startOffset, by: -1) {
            if readUInt32(in: data, at: offset) == signature {
                return offset
            }
        }
        return nil
    }
    
    private static func readUInt16(in data: Data, at offset: Int) -> UInt16 {
        let lower = UInt16(data[offset])
        let upper = UInt16(data[offset + 1]) << 8
        return lower | upper
    }
    
    private static func readUInt32(in data: Data, at offset: Int) -> UInt32 {
        let lower = UInt32(readUInt16(in: data, at: offset))
        let upper = UInt32(readUInt16(in: data, at: offset + 2)) << 16
        return lower | upper
    }
    
    private static func inflate(data: Data, expectedSize: Int) -> Data? {
        var stream = z_stream()
        var status = data.withUnsafeBytes { inputBuffer -> Int32 in
            guard let baseAddress = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return Z_DATA_ERROR
            }
            stream.next_in = UnsafeMutablePointer(mutating: baseAddress)
            stream.avail_in = uInt(inputBuffer.count)
            return inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        
        guard status == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        
        let chunkSize = max(expectedSize, 32 * 1024)
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        
        repeat {
            status = buffer.withUnsafeMutableBytes { outputBuffer -> Int32 in
                guard let baseAddress = outputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                    return Z_DATA_ERROR
                }
                stream.next_out = baseAddress
                stream.avail_out = uInt(outputBuffer.count)
                return zlib.inflate(&stream, Z_NO_FLUSH)
            }
            
            let producedCount = buffer.count - Int(stream.avail_out)
            if producedCount > 0 {
                output.append(contentsOf: buffer.prefix(producedCount))
            }
        } while status == Z_OK
        
        guard status == Z_STREAM_END else {
            return nil
        }
        
        return output
    }
}

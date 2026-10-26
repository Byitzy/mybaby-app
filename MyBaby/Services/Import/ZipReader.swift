import Compression
import Foundation

/// Reads the files inside a ZIP, for exports that come as one (Glow Baby emails a ZIP of CSV files).
///
/// iOS has no public API for opening ZIP files, and MyBaby uses no third-party code, so this is a small
/// reader of its own: it finds each file in the ZIP's central directory and either copies it (stored)
/// or inflates it with Apple's Compression framework (deflate, which `COMPRESSION_ZLIB` decodes).
/// Encrypted entries, ZIP64 archives and other compression methods are skipped. Everything happens in
/// memory: nothing is written to disk.
enum ZipReader {
    struct Entry {
        let name: String
        let data: Data
    }

    /// The most files read from one ZIP, and the most bytes they may unpack to, so a broken or
    /// hostile file can't fill the phone's memory.
    static let maxEntries = 64
    static let maxUnpackedBytes = 200 * 1024 * 1024

    static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04]
    }

    /// The files in `data` whose names `include` accepts, in the ZIP's order.
    static func entries(in data: Data, include: (String) -> Bool) -> [Entry] {
        let bytes = [UInt8](data)
        guard let directory = endOfCentralDirectory(bytes) else { return [] }
        var entries: [Entry] = []
        var unpacked = 0
        var offset = directory.offset
        for _ in 0..<directory.count {
            guard entries.count < maxEntries, offset + 46 <= bytes.count,
                  readUInt32(bytes, offset) == 0x0201_4B50
            else { break }
            let flags = readUInt16(bytes, offset + 8)
            let method = readUInt16(bytes, offset + 10)
            let compressedSize = Int(readUInt32(bytes, offset + 20))
            let size = Int(readUInt32(bytes, offset + 24))
            let nameLength = Int(readUInt16(bytes, offset + 28))
            let extraLength = Int(readUInt16(bytes, offset + 30))
            let commentLength = Int(readUInt16(bytes, offset + 32))
            let localOffset = Int(readUInt32(bytes, offset + 42))
            let nameEnd = offset + 46 + nameLength
            guard nameEnd <= bytes.count else { break }
            let name = String(decoding: bytes[(offset + 46)..<nameEnd], as: UTF8.self)
            offset = nameEnd + extraLength + commentLength

            let isEncrypted = flags & 1 != 0
            let isZip64 = compressedSize == 0xFFFF_FFFF || size == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF
            guard !isEncrypted, !isZip64, !name.hasSuffix("/"), include(name),
                  unpacked + size <= maxUnpackedBytes,
                  let contents = contents(bytes, localOffset: localOffset, method: method, compressedSize: compressedSize, size: size)
            else { continue }
            unpacked += size
            entries.append(Entry(name: name, data: contents))
        }
        return entries
    }

    // MARK: Structure

    /// Where the central directory starts and how many entries it lists, from the record at the end.
    private static func endOfCentralDirectory(_ bytes: [UInt8]) -> (offset: Int, count: Int)? {
        guard bytes.count >= 22 else { return nil }
        // The record is 22 bytes plus a comment of up to 65,535 bytes, at the very end.
        let lowest = max(0, bytes.count - 22 - 65_535)
        var index = bytes.count - 22
        while index >= lowest {
            if readUInt32(bytes, index) == 0x0605_4B50 {
                let count = Int(readUInt16(bytes, index + 10))
                let offset = Int(readUInt32(bytes, index + 16))
                return offset < bytes.count ? (offset, count) : nil
            }
            index -= 1
        }
        return nil
    }

    private static func contents(_ bytes: [UInt8], localOffset: Int, method: UInt16, compressedSize: Int, size: Int) -> Data? {
        guard localOffset + 30 <= bytes.count, readUInt32(bytes, localOffset) == 0x0403_4B50 else { return nil }
        let nameLength = Int(readUInt16(bytes, localOffset + 26))
        let extraLength = Int(readUInt16(bytes, localOffset + 28))
        let start = localOffset + 30 + nameLength + extraLength
        guard start + compressedSize <= bytes.count else { return nil }
        switch method {
        case 0:
            return Data(bytes[start..<(start + compressedSize)])
        case 8:
            return inflate(bytes, from: start, count: compressedSize, size: size)
        default:
            return nil
        }
    }

    /// Raw deflate data (what ZIP stores) unpacked to `size` bytes.
    private static func inflate(_ bytes: [UInt8], from start: Int, count: Int, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        guard count > 0 else { return nil }
        var output = [UInt8](repeating: 0, count: size)
        let written = bytes.withUnsafeBufferPointer { source -> Int in
            output.withUnsafeMutableBufferPointer { destination -> Int in
                guard let sourceBase = source.baseAddress, let destinationBase = destination.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, size, sourceBase + start, count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { return nil }
        return Data(output)
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}

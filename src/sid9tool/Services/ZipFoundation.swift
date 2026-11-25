import Foundation
#if canImport(zlib)
import zlib
#endif

/// Minimal self-contained ZIP archive reader (drop-in replacement for the subset of
/// ZipFoundation APIs used by sid9tool: `Archive(url:readOnly:)` + `extract(to:)`).
/// Supports stored + deflate (raw zlib) entries, directory entries, and ZIP64 fallback.
/// NOTE: lives inside the `sid9tool` module itself, so `import ZipFoundation`
/// statements in this module resolve to these in-module types (no SPM/network needed).
enum ZipError: LocalizedError {
    case notAZipArchive
    case badEndOfCentralDirectory
    case badCentralDirectory
    case inflateFailed
    case unreadableEntry

    var errorDescription: String? {
        switch self {
        case .notAZipArchive: return "Not a valid zip archive"
        case .badEndOfCentralDirectory: return "Bad end-of-central-directory record"
        case .badCentralDirectory: return "Bad central directory"
        case .inflateFailed: return "Failed to inflate entry"
        case .unreadableEntry: return "Unable to read entry"
        }
    }
}

final class Archive {
    private let url: URL
    private let data: Data
    private let cdOffset: Int

    /// - Parameter url: file URL of the zip
    /// - Parameter readOnly: kept for API compatibility (we are always read-only)
    init(url: URL, readOnly: Bool) throws {
        guard let fd = fopen(url.path, "rb") else { throw ZipError.unreadableEntry }
        defer { fclose(fd) }
        var statBuf = stat()
        guard fstat(fileno(fd), &statBuf) == 0, statBuf.st_size > 4 else { throw ZipError.notAZipArchive }
        let size = Int(statBuf.st_size)
        var buf = [UInt8](repeating: 0, count: size)
        guard fread(&buf, 1, buf.count, fd) == buf.count else { throw ZipError.unreadableEntry }
        let allData = Data(buf)
        guard let eocdOffset = Archive.findEOCD(allData) else { throw ZipError.badEndOfCentralDirectory }
        guard eocdOffset + 22 <= allData.count else { throw ZipError.badEndOfCentralDirectory }
        // Central directory offset (u32 at EOCD+16; ZIP64 => 0xFFFFFFFF, handled by CD scan)
        guard eocdOffset + 20 <= allData.count else { throw ZipError.badEndOfCentralDirectory }
        self.cdOffset = Int(Archive.u32(allData, eocdOffset + 16))
        self.url = url
        self.data = allData
    }

    /// Extracts all entries into the destination directory, preserving relative paths.
    func extract(to dest: URL) throws {
        let size = data.count
        let entries = Archive.parseCentralDirectory(at: cdOffset, in: data)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        for entry in entries {
            var name = entry.name
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: dest.appendingPathComponent(name), withIntermediateDirectories: true)
                continue
            }
            var pos = entry.localHeaderOffset
            guard pos + 30 <= size else { throw ZipError.badCentralDirectory }
            let header = data.subdata(in: pos..<pos + 30)
            let nameLen = Int(UInt16(header[26]) | (UInt16(header[27]) << 8))
            let extraLen = Int(UInt16(header[28]) | (UInt16(header[29]) << 8))
            guard nameLen < 4096 else { throw ZipError.badCentralDirectory }
            let dataStart = pos + 30 + nameLen + extraLen
            let rawLen = entry.compressedSize
            guard dataStart + rawLen <= size else { throw ZipError.badCentralDirectory }

            var out: Data
            if entry.compressionMethod == 0 {
                out = data.subdata(in: dataStart..<dataStart + rawLen)
            } else if entry.compressionMethod == 8 {
                if entry.uncompressedSize == 0 { continue }
                let raw = [UInt8](data.subdata(in: dataStart..<dataStart + rawLen))
                out = try Archive.inflate(raw, expectedLength: entry.uncompressedSize)
            } else {
                throw ZipError.inflateFailed // only stored + deflate are supported
            }

            let target = dest.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try out.write(to: target)
        }
    }

    // MARK: - ZIP parsing helpers

    struct Entry {
        var name: String
        var compressionMethod: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    private static func findEOCD(_ d: Data) -> Int? {
        let sig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let lowerBound = max(0, d.count - 65557)
        var i = d.count - 22
        while i >= lowerBound {
            if d[i] == sig[0] && d[i + 1] == sig[1] && d[i + 2] == sig[2] && d[i + 3] == sig[3] {
                return i
            }
            i -= 1
        }
        return nil
    }

    private static func u16(_ d: Data, _ o: Int) -> UInt16 {
        UInt16(d[o]) | (UInt16(d[o + 1]) << 8)
    }

    private static func u32(_ d: Data, _ o: Int) -> UInt32 {
        UInt32(d[o]) | (UInt32(d[o + 1]) << 8) | (UInt32(d[o + 2]) << 16) | (UInt32(d[o + 3]) << 24)
    }

    private static func u64(_ d: Data, _ o: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(d[o + i]) }
        return v
    }

    private static func parseCentralDirectory(at offset: Int, in d: Data) throws -> [Entry] {
        var entries: [Entry] = []
        guard offset + 4 <= d.count else { throw ZipError.badCentralDirectory }
        let sig: [UInt8] = [0x50, 0x4b, 0x01, 0x02]
        var i = offset
        while i + 46 <= d.count {
            guard d[i] == sig[0], d[i + 1] == sig[1], d[i + 2] == sig[2], d[i + 3] == sig[3] else { break }
            let method = u16(d, i + 10)
            var unc = Int(u32(d, i + 20))
            var comp = Int(u32(d, i + 24))
            var lfo = Int(u32(d, i + 42))
            let nameLen = Int(u16(d, i + 28))
            let extraLen = Int(u16(d, i + 30))
            let commentLen = Int(u16(d, i + 32))
            if (unc == 0xFFFFFFFF || lfo == 0xFFFFFFFF) {
                // ZIP64 extra field
                var j = i + 46 + nameLen
                let extraEnd = j + extraLen
                while j + 4 <= extraEnd {
                    let eSig = u16(d, j)
                    let eLen = Int(u16(d, j + 2))
                    if eSig == 0x0001, j + 4 + eLen <= extraEnd {
                        if unc == 0xFFFFFFFF { unc = Int(u64(d, j + 4)) }
                        if comp == 0xFFFFFFFF { comp = Int(u64(d, j + 4 + 8)) }
                        if lfo == 0xFFFFFFFF { lfo = Int(u64(d, j + 4 + 16)) }
                    }
                    j += 4 + eLen
                }
            }
            let name = String(bytes: d[(i + 46)..<(i + 46 + nameLen)], encoding: .utf8) ?? "entry_\(entries.count)"
            entries.append(Entry(name: name, compressionMethod: method, compressedSize: comp, uncompressedSize: unc, localHeaderOffset: lfo))
            i += 46 + nameLen + extraLen + commentLen
        }
        if entries.isEmpty { throw ZipError.badCentralDirectory }
        return entries
    }
    // MARK: - Raw inflate (zlib)

    private static func inflate(_ input: [UInt8], expectedLength: Int) throws -> Data {
        #if canImport(zlib)
        var strm = z_stream()
        strm.next_in = UnsafeMutablePointer<Bytef>(mutating: input)
        strm.avail_in = uInt(input.count)
        let outCap = max(expectedLength, 1024)
        var outBuf = [UInt8](repeating: 0, count: outCap)
        var total: Int = 0
        let ret = withUnsafeMutablePointer(to: &strm) { ptr in
            ptr.pointee.next_out = outBuf.withUnsafeMutableBytes { $0.baseAddress?.assumingMemoryBound(to: Bytef.self) }
            ptr.pointee.avail_out = uInt(outCap)
            guard inflateInit2_(&ptr.pointee, -15, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return Int32(-1) }
            let r = inflate(&ptr.pointee, Z_FINISH)
            deflateEnd(&ptr.pointee)
            return Int32(r)
        }
        if ret == Z_STREAM_END || ret == Z_OK {
            total = outCap - Int(strm.avail_out)
        }
        if total > 0, ret == Z_STREAM_END || ret == Z_OK || ret == Z_BUF_ERROR {
            return Data(outBuf[0..<total])
        }
        throw ZipError.inflateFailed
        #else
        throw ZipError.inflateFailed
        #endif
    }
}

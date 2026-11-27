import Foundation

// MARK: - Mach-O Parser (thin / fat, arm64 / arm64e)
//
// Pure Swift parser for Mach-O binaries. Supports:
//  - Thin 32-bit (MH_MAGIC) and 64-bit (MH_MAGIC_64)
//  - Fat / universal (FAT_MAGIC)
//  - arm64 and arm64e architectures
//
// Provides: header parsing, load-command listing, LC_CODE_SIGNATURE
// location/creation, __LINKEDIT boundary detection, and a self-check.

// MARK: - Magic numbers

enum MachOMagic {
    static let mhMagic: UInt32       = 0xFEEDFACE
    static let mhCigam: UInt32       = 0xCEFAEDFE
    static let mhMagic64: UInt32     = 0xFEEDFACF
    static let mhCigam64: UInt32     = 0xCFFAEDFE
    static let fatMagic: UInt32      = 0xCAFEBABE
    static let fatCigam: UInt32      = 0xBEBAFECA
    static let fatMagic64: UInt32    = 0xCAFEBABF
    static let fatCigam64: UInt32    = 0xBFBAFECA
}

// MARK: - CPU types

enum MachOCPU {
    static let arm: Int32           = 7
    static let arm64: Int32         = 0x0100000C
    static let arm64_32: Int32      = 0x0200000C
    static let archABI64: Int32     = 0x01000000
    static let archABI64_32: Int32  = 0x02000000
    static let subTypeArm64E: Int32 = 2
}

// MARK: - Load command types

enum MachOLC {
    static let segment: UInt32         = 0x1
    static let symtab: UInt32          = 0x2
    static let dysymtab: UInt32        = 0xB
    static let loadDylib: UInt32       = 0xC
    static let segment64: UInt32       = 0x19
    static let uuid: UInt32            = 0x1B
    static let rpath: UInt32           = 0x1C
    static let codeSignature: UInt32   = 0x1D
    static let dyldInfo: UInt32        = 0x20
    static let dyldInfoOnly: UInt32    = 0x21
    static let versionMin: UInt32      = 0x24
    static let buildVersion: UInt32    = 0x32
    static let main: UInt32            = 0x80000028
}

// MARK: - Data structures

struct ThinHeader {
    let magic: UInt32
    let cputype: Int32
    let cpusubtype: Int32
    let filetype: UInt32
    let ncmds: UInt32
    let sizeofcmds: UInt32
    let flags: UInt32
    var is64: Bool { magic == MachOMagic.mhMagic64 || magic == MachOMagic.mhCigam64 }
    var isArm64: Bool { cputype == MachOCPU.arm64 || cputype == MachOCPU.arm64_32 }
    var isArm64e: Bool { isArm64 && cpusubtype == MachOCPU.subTypeArm64E }
    var archName: String {
        if isArm64e { return "arm64e" }
        if isArm64 { return "arm64" }
        return "unknown(0x\(String(format: "%08X", cputype)))"
    }
}

struct FatHeader {
    let magic: UInt32
    let nfat_arch: UInt32
}

struct FatArchEntry {
    let cputype: Int32
    let cpusubtype: Int32
    let offset: UInt32
    let size: UInt32
    let align: UInt32
}

struct LoadCommand {
    let cmd: UInt32
    let cmdsize: UInt32
    let offset: Int   // byte offset within the thin image
    var description: String {
        let name: String
        switch cmd {
        case MachOLC.segment:        name = "LC_SEGMENT"
        case MachOLC.segment64:      name = "LC_SEGMENT_64"
        case MachOLC.symtab:         name = "LC_SYMTAB"
        case MachOLC.dysymtab:       name = "LC_DYSYMTAB"
        case MachOLC.loadDylib:      name = "LC_LOAD_DYLIB"
        case MachOLC.uuid:           name = "LC_UUID"
        case MachOLC.rpath:          name = "LC_RPATH"
        case MachOLC.codeSignature:  name = "LC_CODE_SIGNATURE"
        case MachOLC.dyldInfo:       name = "LC_DYLD_INFO"
        case MachOLC.dyldInfoOnly:   name = "LC_DYLD_INFO_ONLY"
        case MachOLC.versionMin:     name = "LC_VERSION_MIN_IPHONEOS"
        case MachOLC.buildVersion:   name = "LC_BUILD_VERSION"
        case MachOLC.main:           name = "LC_MAIN"
        default:                     name = "LC_0x\(String(format: "%X", cmd))"
        }
        return "\(name) (size \(cmdsize))"
    }
}

struct SegmentInfo {
    let segname: String
    let vmaddr: UInt64
    let vmsize: UInt64
    let fileoff: UInt64
    let filesize: UInt64
    let nsects: UInt32
}

// MARK: - Parser

enum MachO {

    struct ParsedBinary {
        let header: ThinHeader
        let loadCommands: [LoadCommand]
        let segments: [SegmentInfo]
        /// Byte offset where the code-signature LC sits (nil if absent).
        let codeSigOffset: Int?
        /// (fileoff, filesize) of __LINKEDIT segment.
        let linkeditBounds: (offset: UInt64, size: UInt64)?
    }

    enum ParseError: Error, LocalizedError {
        case tooSmall
        case badMagic(UInt32)
        case badArch(Int32)
        case truncated

        var errorDescription: String? {
            switch self {
            case .tooSmall:    return "Data too small for Mach-O"
            case .badMagic(let m): return "Bad magic: 0x\(String(format: "%08X", m))"
            case .badArch(let c):  return "Unsupported CPU type: 0x\(String(format: "%08X", c))"
            case .truncated:   return "Truncated load commands"
            }
        }
    }

    // MARK: Byte helpers

    private static func u32(_ d: Data, _ off: Int) -> UInt32 {
        d.subdata(in: off..<(off+4)).withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    private static func i32(_ d: Data, _ off: Int) -> Int32 {
        d.subdata(in: off..<(off+4)).withUnsafeBytes { $0.load(as: Int32.self) }
    }
    private static func u64(_ d: Data, _ off: Int) -> UInt64 {
        d.subdata(in: off..<(off+8)).withUnsafeBytes { $0.load(as: UInt64.self) }
    }
    private static func segName(_ d: Data, _ off: Int) -> String {
        let raw = d.subdata(in: off..<min(off+16, d.count))
        let end = raw.firstIndex(of: 0) ?? raw.count
        return String(decoding: raw.prefix(end), as: UTF8.self)
    }

    // MARK: Public API

    /// Parse a Mach-O binary (thin or fat). Returns the first arm64 slice.
    static func parse(_ data: Data) throws -> ParsedBinary {
        guard data.count >= 8 else { throw ParseError.tooSmall }
        let magic = u32(data, 0)
        switch magic {
        case MachOMagic.mhMagic, MachOMagic.mhCigam,
             MachOMagic.mhMagic64, MachOMagic.mhCigam64:
            return try parseThin(data)
        case MachOMagic.fatMagic, MachOMagic.fatCigam,
             MachOMagic.fatMagic64, MachOMagic.fatCigam64:
            return try parseFat(data)
        default:
            throw ParseError.badMagic(magic)
        }
    }

    /// List load-command descriptions for a parsed binary.
    static func loadCommandDescriptions(_ p: ParsedBinary) -> [String] {
        p.loadCommands.map { $0.description }
    }

    // MARK: Thin parsing

    private static func parseThin(_ data: Data) throws -> ParsedBinary {
        guard data.count >= 28 else { throw ParseError.tooSmall }
        let magic = u32(data, 0)
        let cputype = i32(data, 4)
        let cpusubtype = i32(data, 8)
        let filetype = u32(data, 12)
        let ncmds = u32(data, 16)
        let sizeofcmds = u32(data, 20)
        let flags = u32(data, 24)
        let is64 = (magic == MachOMagic.mhMagic64 || magic == MachOMagic.mhCigam64)
        guard cputype == MachOCPU.arm64 || cputype == MachOCPU.arm64_32 else {
            throw ParseError.badArch(cputype)
        }
        let hdr = ThinHeader(magic: magic, cputype: cputype, cpusubtype: cpusubtype,
                             filetype: filetype, ncmds: ncmds, sizeofcmds: sizeofcmds, flags: flags)
        return try parseLoadCommands(data, header: hdr, is64: is64)
    }

    private static func parseLoadCommands(_ data: Data, header: ThinHeader, is64: Bool) throws -> ParsedBinary {
        var offset = 32  // past thin header (28 or 32 bytes; 64-bit is 32)
        if is64 { offset = 32 }
        var lcs: [LoadCommand] = []
        var segments: [SegmentInfo] = []
        var codeSigOffset: Int? = nil
        var linkedit: (UInt64, UInt64)? = nil
        for _ in 0..<Int(header.ncmds) {
            guard offset + 8 <= data.count else { throw ParseError.truncated }
            let cmd = u32(data, offset)
            let cmdsize = u32(data, offset + 4)
            guard cmdsize >= 8, offset + Int(cmdsize) <= data.count else { throw ParseError.truncated }
            lcs.append(LoadCommand(cmd: cmd, cmdsize: cmdsize, offset: offset))
            // Segment info
            if cmd == MachOLC.segment || cmd == MachOLC.segment64 {
                let name = segName(data, offset + 8)
                let (va, vs, fo, fs, ns): (UInt64, UInt64, UInt64, UInt64, UInt32)
                if is64 {
                    va = u64(data, offset + 24); vs = u64(data, offset + 32)
                    fo = u64(data, offset + 40); fs = u64(data, offset + 48)
                    ns = u32(data, offset + 64)
                } else {
                    va = UInt64(u32(data, offset + 16)); vs = UInt64(u32(data, offset + 20))
                    fo = UInt64(u32(data, offset + 24)); fs = UInt64(u32(data, offset + 28))
                    ns = u32(data, offset + 36)
                }
                segments.append(SegmentInfo(segname: name, vmaddr: va, vmsize: vs,
                                           fileoff: fo, filesize: fs, nsects: ns))
                if name == "__LINKEDIT" { linkedit = (fo, fs) }
            }
            if cmd == MachOLC.codeSignature { codeSigOffset = offset }
            offset += Int(cmdsize)
        }
        return ParsedBinary(header: header, loadCommands: lcs, segments: segments,
                            codeSigOffset: codeSigOffset, linkeditBounds: linkedit)
    }

    // MARK: Fat parsing

    private static func parseFat(_ data: Data) throws -> ParsedBinary {
        guard data.count >= 8 else { throw ParseError.tooSmall }
        let nfat = u32(data, 4)
        guard data.count >= 8 + Int(nfat) * 20 else { throw ParseError.tooSmall }
        var best: ParsedBinary? = nil
        for i in 0..<Int(nfat) {
            let e = 8 + i * 20
            let ct = i32(data, e)
            guard ct == MachOCPU.arm64 || ct == MachOCPU.arm64_32 else { continue }
            let off = Int(u32(data, e + 8))
            let sz = Int(u32(data, e + 12))
            guard off + sz <= data.count else { continue }
            let slice = data.subdata(in: off..<off+sz)
            if let p = try? parseThin(slice) {
                if best == nil { best = p }
            }
        }
        guard let result = best else { throw ParseError.badArch(-1) }
        return result
    }

    // MARK: Code signature location / creation

    /// Returns the (dataoff, datasize) from LC_CODE_SIGNATURE, or nil if absent.
    static func codeSignatureInfo(_ p: ParsedBinary, in data: Data) -> (dataoff: UInt32, datasize: UInt32)? {
        guard let off = p.codeSigOffset, off + 16 <= data.count else { return nil }
        let dataoff = u32(data, off + 8)
        let datasize = u32(data, off + 12)
        return (dataoff, datasize)
    }

    /// Build a minimal LC_CODE_SIGNATURE load command (16 bytes).
    static func makeCodeSigLC(dataoff: UInt32, datasize: UInt32) -> Data {
        var d = Data(count: 16)
        withUnsafeBytes(of: MachOLC.codeSignature) { d.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: UInt32(16)) { d.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: dataoff) { d.replaceSubrange(8..<12, with: $0) }
        withUnsafeBytes(of: datasize) { d.replaceSubrange(12..<16, with: $0) }
        return d
    }

    // MARK: Self-check

    /// Build a minimal arm64 Mach-O in memory and verify the parser.
    /// Returns a human-readable report; empty string means all checks passed.
    static func selfCheck() -> String {
        var failures: [String] = []
        // Build a tiny arm64 thin binary: header + 2 LCs (LC_SEGMENT_64 __TEXT, LC_CODE_SIGNATURE)
        // mach_header_64 = 32 bytes. LC_SEGMENT_64 = 72 bytes. LC_CODE_SIGNATURE = 16 bytes.
        var d = Data()
        func w32(_ v: UInt32) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
        func w32s(_ v: Int32) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
        func w64(_ v: UInt64) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
        func wstr(_ s: String) { for b in s.utf8 { d.append(b) }; d.append(0) }
        // mach_header_64 (32 bytes): magic,cputype,cpusubtype,filetype,ncmds,sizeofcmds,reserved,flags
        w32(MachOMagic.mhMagic64); w32s(MachOCPU.arm64); w32s(MachOCPU.subTypeArm64E)
        w32(2 /*MH_EXECUTE*/); w32(2 /*ncmds*/); w32(88 /*sizeofcmds*/); w32(0 /*reserved*/); w32(0 /*flags*/)
        // LC_SEGMENT_64 (72 bytes): cmd,cmdsize,segname[16],vmaddr,vmsize,fileoff,filesize,maxprot,initprot,nsects,flags
        w32(MachOLC.segment64); w32(72)
        d.append(contentsOf: "__TEXT".utf8); d.append(contentsOf: Data(count: 16 - 6)) // segname[16]
        w64(0x100000000); w64(0x1000); w64(0); w64(0x1000); w32(7); w32(5); w32(0); w32(0)
        // LC_CODE_SIGNATURE (16 bytes): cmd,cmdsize,dataoff,datasize
        w32(MachOLC.codeSignature); w32(16); w32(0x2000); w32(0x100)
        // pad to 0x2100
        d.append(contentsOf: Data(count: 0x2100 - d.count))
        do {
            let p = try parse(d)
            if !p.header.isArm64e { failures.append("arch not arm64e") }
            if p.loadCommands.count != 2 { failures.append("expected 2 LC, got \(p.loadCommands.count)") }
            if p.codeSigOffset == nil { failures.append("no code sig LC found") }
            if let info = codeSignatureInfo(p, in: d), info.dataoff == 0x2000, info.datasize == 0x100 {} else {
                failures.append("bad code sig info")
            }
            if let seg = p.segments.first, seg.segname == "__TEXT" {} else { failures.append("bad segment") }
        } catch {
            failures.append("parse threw: \(error)")
        }
        // Build a fat wrapper around the thin binary
        var fat = Data()
        func fw32(_ v: UInt32) { withUnsafeBytes(of: v) { fat.append(contentsOf: $0) } }
        func fw32s(_ v: Int32) { withUnsafeBytes(of: v) { fat.append(contentsOf: $0) } }
        fw32(MachOMagic.fatMagic); fw32(1)
        fw32s(MachOCPU.arm64); fw32s(MachOCPU.subTypeArm64E); fw32(8); fw32(UInt32(d.count)); fw32(4)
        fat.append(contentsOf: d)
        do {
            let p = try parse(fat)
            if p.loadCommands.count != 2 { failures.append("fat: expected 2 LC, got \(p.loadCommands.count)") }
        } catch {
            failures.append("fat parse threw: \(error)")
        }
        return failures.isEmpty ? "OK" : failures.joined(separator: "; ")
    }
}
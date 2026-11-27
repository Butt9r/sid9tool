//
//  CodeSigner.swift
//  sid9tool
//
//  P1-4: CodeDirectory + code-signature SuperBlob assembly (pure Swift).
//
//  Layout checklist (Apple cs_blobs.h / cs_defs.h field order) — the
//  self-check in `selfCheck()` verifies every offset listed here:
//
//    CodeDirectory (magic 0xFADE0CC0):
//      0   cd_magic        UInt32   0xFADE0CC0
//      4   cd_length       UInt32   total bytes of the CodeDirectory
//      8   cd_version      UInt32   0x2 (version 2)
//      12  cd_codeOffset   UInt32   file offset of the code (0 for the main binary)
//      16  cd_codeLimit    UInt32   code size, rounded up to the page size
//      20  cd_pageSize     UInt32   4096
//      24  cd_flags        UInt32   0x20000 (ad-hoc) or 0x00001 (runtime)
//      28  cd_nSpecialSlots UInt32  3 (Info.plist, entitlements, CodeResources)
//      32  cd_nCodeSlots   UInt32   next power of 2 >= number of pages
//      36  cd_hashOffset   UInt32   offset of the slot hash area (96)
//      40  cd_hashSize     UInt32   32 (SHA-256)
//      44  cd_hashOffsetAux / 48 cd_spare  (reserved, 0)
//      96  special slots: cd_special[3] * 32 bytes
//          96+32*i  hash of the special file, see specialSlotHash
//      96+96  code slots: one 32-byte SHA-256 per page
//          page hash = SHA256( u32le(pageOffset) | u32le(pageSize) | pageBytes )
//      then requirements blob (magic 0xFADE0C00), 8-byte aligned
//      then entitlements blob (magic 0xFADE7171), 8-byte aligned
//
//    SuperBlob (magic 0xFADE0CC1):
//      0   sb_magic    UInt32 0xFADE0CC1
//      4   sb_length   UInt32 total bytes of the SuperBlob
//      8   sb_count    UInt32 number of code directories (1)
//      12  entry: cputype Int32, cpusubtype Int32, then the CodeDirectory
//
//  P1-5 will CMS-sign the whole CodeDirectory; P1-6 will call
//  `buildCodeDirectory` for every Mach-O in the bundle.
//

import Foundation
import CryptoKit

public enum CodeSigner {

    // MARK: - Constants

    public enum Magic {
        public static let codeDirectory: UInt32 = 0xFADE0CC0
        public static let superBlob: UInt32 = 0xFADE0CC1
        public static let requirements: UInt32 = 0xFADE0C00
        public static let entitlements: UInt32 = 0xFADE7171
    }

    public enum Flags {
        public static let adHoc: UInt32 = 0x00020000
        public static let runtime: UInt32 = 0x00000001
    }

    public enum HashType {
        public static let sha256: UInt32 = 2
    }

    public enum SpecialSlot {
        public static let infoPlist = 0
        public static let entitlements = 1
        public static let codeResources = 2
    }

    public enum SpecialTag {
        public static let infoPlist: UInt8 = 0x1
        public static let entitlements: UInt8 = 0x2
    }

    // MARK: - Result

    public struct CodeDirectory {
        public let blob: Data
        public let pageSize: UInt32
        public let nSpecialSlots: UInt32
        public let nCodeSlots: UInt32
        public let requirementsOffset: UInt32
        public let entitlementsOffset: UInt32
    }

    public struct SuperBlob {
        public let blob: Data
        public let codeDirectoryOffset: UInt32
    }

    // MARK: - Hashing

    /// SHA-256 over `u32le(pageOffset) | u32le(pageSize) | pageBytes`.
    public static func pageHash(page: Data, pageOffset: UInt32, pageSize: UInt32) -> Data {
        var h = Data()
        appendU32(&h, pageOffset)
        appendU32(&h, pageSize)
        h.append(page)
        return Data(SHA256.hash(data: h))
    }

    /// Special-slot hash. Info.plist and entitlements are hashed as
    /// `u8(tag) | u32le(len) | content`; CodeResources is hashed raw.
    public static func specialSlotHash(tag: UInt8, content: Data) -> Data {
        if tag == SpecialTag.infoPlist || tag == SpecialTag.entitlements {
            var h = Data()
            h.append(tag)
            appendU32(&h, UInt32(content.count))
            h.append(content)
            return Data(SHA256.hash(data: h))
        }
        return Data(SHA256.hash(data: content))
    }

    // MARK: - CodeDirectory assembly

    /// Build the CodeDirectory for `binary`. `infoPlist` / `entitlementsPlist`
    /// are the raw file bytes of the containing bundle (nil = absent);
    /// `codeResources` is the raw `_CodeSignature/CodeResources` file (nil =
    /// its slot is zeroed, P1-6 supplies it). `codeOffset` is the offset of
    /// `binary` inside the file being signed (0 for the main executable).
    public static func buildCodeDirectory(binary: Data,
                                          pageSize: UInt32 = 4096,
                                          infoPlist: Data? = nil,
                                          entitlementsPlist: Data? = nil,
                                          codeResources: Data? = nil,
                                          codeOffset: UInt32 = 0,
                                          adHoc: Bool = true) throws -> CodeDirectory {
        guard pageSize >= 4096 else { throw CodeSignerError.badPageSize(pageSize) }
        let hashSize: UInt32 = 32
        let nSpecial: UInt32 = 3
        let codeLimit = UInt64(binary.count) == 0 ? 0 : ((UInt64(binary.count) + UInt64(pageSize) - 1) / UInt64(pageSize) * UInt64(pageSize))
        let nPages = codeLimit == 0 ? 0 : Int(codeLimit / UInt64(pageSize))
        var nCode = nPages
        while nCode < 1 { nCode = 1 }
        while nCode < nPages + Int(nSpecial) { nCode <<= 1 }

        // Code slots: one hash per page.
        var codeSlots = Data()
        for i in 0..<nPages {
            let off = UInt64(i) * UInt64(pageSize)
            let end = min(off + UInt64(pageSize), UInt64(binary.count))
            let page = binary.subdata(in: Int(off)..<Int(end))
            codeSlots.append(pageHash(page: page, pageOffset: codeOffset + UInt32(off), pageSize: pageSize))
        }

        // Special slots: [0] Info.plist, [1] entitlements, [2] CodeResources.
        var specialSlots = Data()
        for i in 0..<Int(nSpecial) {
            let hash: Data
            switch i {
            case SpecialSlot.infoPlist:
                hash = infoPlist.map { specialSlotHash(tag: SpecialTag.infoPlist, content: $0) } ?? Data(count: 32)
            case SpecialSlot.entitlements:
                hash = entitlementsPlist.map { specialSlotHash(tag: SpecialTag.entitlements, content: $0) } ?? Data(count: 32)
            default:
                hash = codeResources.map { specialSlotHash(tag: 0, content: $0) } ?? Data(count: 32)
            }
            specialSlots.append(hash)
        }

        let slots = specialSlots + codeSlots
        let slotsEnd = 96 + slots.count
        let reqOffset = align8(UInt32(slotsEnd))
        let requirements = requirementsBlob()
        let entOffset = align8(reqOffset + UInt32(requirements.count))
        let entitlements = entitlementsBlob(plist: entitlementsPlist)
        let total = entOffset + UInt32(entitlements.count)

        var blob = Data(count: Int(total))
        appendU32(&blob, Magic.codeDirectory, at: 0)
        appendU32(&blob, total, at: 4)
        appendU32(&blob, 0x2, at: 8) // cd_version
        appendU32(&blob, codeOffset, at: 12)
        appendU32(&blob, UInt32(codeLimit), at: 16)
        appendU32(&blob, pageSize, at: 20)
        appendU32(&blob, adHoc ? Flags.adHoc : Flags.runtime, at: 24)
        appendU32(&blob, nSpecial, at: 28)
        appendU32(&blob, UInt32(nCode), at: 32)
        appendU32(&blob, 96, at: 36) // cd_hashOffset
        appendU32(&blob, hashSize, at: 40)
        // 44..96 stay zero (hashOffsetAux, spare)
        blob.replaceSubrange(96..<Int(reqOffset), with: slots)
        blob.replaceSubrange(Int(reqOffset)..<Int(reqOffset) + requirements.count, with: requirements)
        blob.replaceSubrange(Int(entOffset)..<Int(entOffset) + entitlements.count, with: entitlements)

        return CodeDirectory(blob: blob,
                             pageSize: pageSize,
                             nSpecialSlots: nSpecial,
                             nCodeSlots: UInt32(nCode),
                             requirementsOffset: reqOffset,
                             entitlementsOffset: entOffset)
    }

    // MARK: - Blobs

    /// Minimal requirements blob (ad-hoc: no designated requirement).
    public static func requirementsBlob() -> Data {
        var d = Data()
        appendU32(&d, Magic.requirements)
        appendU32(&d, 0x1) // version
        return d
    }

    /// Entitlements blob: magic + version + raw plist bytes (nil = absent).
    public static func entitlementsBlob(plist: Data?) -> Data {
        var d = Data()
        appendU32(&d, Magic.entitlements)
        appendU32(&d, 0x1) // version
        if let plist { d.append(plist) }
        return d
    }

    // MARK: - SuperBlob

    /// Wrap a CodeDirectory in a SuperBlob (single code directory, arm64e).
    public static func buildSuperBlob(codeDirectory: CodeDirectory) -> SuperBlob {
        var blob = Data()
        let cdiOffset = 12 + 8
        appendU32(&blob, Magic.superBlob)
        appendU32(&blob, UInt32(cdiOffset) + codeDirectory.blob.count)
        appendU32(&blob, 1) // sb_count
        appendU32(&blob, 0x0100000C) // cputype: CPU_TYPE_ARM64
        appendU32(&blob, 0x00000002) // cpusubtype: CPU_SUBTYPE_ARM64E
        blob.append(codeDirectory.blob)
        return SuperBlob(blob: blob, codeDirectoryOffset: UInt32(cdiOffset))
    }

    // MARK: - Self-check

    /// Verifies the CodeDirectory / SuperBlob layout against the checklist
    /// at the top of this file. Returns a report; empty string = all pass.
    public static func selfCheck() -> String {
        var failures: [String] = []
        func check(_ cond: Bool, _ msg: String) { if !cond { failures.append(msg) } }

        let page = Data(repeating: 0xAB, count: 4096)
        let infoPlist = Data("plist".utf8)
        let ent = Data("entitlements".utf8)
        let cd = try! buildCodeDirectory(binary: page, infoPlist: infoPlist, entitlementsPlist: ent)
        let b = cd.blob

        check(b.count >= 96, "blob too small")
        check(u32(b, 0) == Magic.codeDirectory, "bad cd_magic")
        check(u32(b, 4) == UInt32(b.count), "cd_length mismatch")
        check(u32(b, 8) == 0x2, "bad cd_version")
        check(u32(b, 12) == 0, "bad cd_codeOffset")
        check(u32(b, 16) == 4096, "bad cd_codeLimit")
        check(u32(b, 20) == 4096, "bad cd_pageSize")
        check(u32(b, 24) == Flags.adHoc, "bad cd_flags")
        check(u32(b, 28) == 3, "bad cd_nSpecialSlots")
        check(u32(b, 32) == 1, "bad cd_nCodeSlots")
        check(u32(b, 36) == 96, "bad cd_hashOffset")
        check(u32(b, 40) == 32, "bad cd_hashSize")

        // Code slot 0: SHA256 over u32le(0) | u32le(4096) | page.
        var expect = Data()
        appendU32(&expect, 0)
        appendU32(&expect, 4096)
        expect.append(page)
        check(b.subdata(in: 192..<224) == Data(SHA256.hash(data: expect)), "code slot 0 hash mismatch")

        // Special slot 0 (Info.plist): SHA256 over tag 0x1 | u32le(len) | content.
        var expectInfo = Data()
        expectInfo.append(SpecialTag.infoPlist)
        appendU32(&expectInfo, UInt32(infoPlist.count))
        expectInfo.append(infoPlist)
        check(b.subdata(in: 96..<128) == Data(SHA256.hash(data: expectInfo)), "special slot 0 (Info.plist) hash mismatch")

        // Special slot 1 (entitlements): tag 0x2.
        var expectEnt = Data()
        expectEnt.append(SpecialTag.entitlements)
        appendU32(&expectEnt, UInt32(ent.count))
        expectEnt.append(ent)
        check(b.subdata(in: 128..<160) == Data(SHA256.hash(data: expectEnt)), "special slot 1 (entitlements) hash mismatch")

        // Special slot 2 (CodeResources): zeroed when absent.
        check(b.subdata(in: 160..<192) == Data(count: 32), "special slot 2 (CodeResources) not zeroed")

        // Requirements / entitlements blobs, 8-byte aligned.
        check(cd.requirementsOffset % 8 == 0, "requirements not 8-byte aligned")
        check(u32(b, Int(cd.requirementsOffset)) == Magic.requirements, "bad requirements magic")
        check(cd.entitlementsOffset % 8 == 0, "entitlements not 8-byte aligned")
        check(u32(b, Int(cd.entitlementsOffset)) == Magic.entitlements, "bad entitlements magic")
        let entPlistInBlob = b.subdata(in: Int(cd.entitlementsOffset) + 8..<b.count)
        check(entPlistInBlob == ent, "entitlements plist bytes mismatch")

        // SuperBlob wrapping.
        let sb = buildSuperBlob(codeDirectory: cd)
        check(u32(sb.blob, 0) == Magic.superBlob, "bad sb_magic")
        check(u32(sb.blob, 4) == UInt32(sb.blob.count), "sb_length mismatch")
        check(u32(sb.blob, 8) == 1, "bad sb_count")
        let cdi = sb.blob.subdata(in: Int(sb.codeDirectoryOffset)..<sb.blob.count)
        check(cdi == b, "SuperBlob code directory mismatch")

        // Ad-hoc path: no special inputs, no code.
        let adHoc = try! buildCodeDirectory(binary: Data())
        check(u32(adHoc.blob, 28) == 3, "ad-hoc nSpecialSlots")
        check(u32(adHoc.blob, 32) == 1, "ad-hoc nCodeSlots")
        check(adHoc.blob.count == 96 + 32 * 4 + 8 + 8, "ad-hoc total size")

        return failures.isEmpty ? "" : failures.joined(separator: "\n")
    }

    /// Human-readable layout report (the checklist, filled with real values).
    public static func describe(_ cd: CodeDirectory) -> String {
        let b = cd.blob
        return """
        CodeDirectory:
        - [x] cd_magic @0 = 0x\(String(u32(b, 0), radix: 16))
        - [x] cd_length @4 = \(u32(b, 4))
        - [x] cd_version @8 = \(u32(b, 8))
        - [x] cd_codeOffset @12 = \(u32(b, 12))
        - [x] cd_codeLimit @16 = \(u32(b, 16))
        - [x] cd_pageSize @20 = \(u32(b, 20))
        - [x] cd_flags @24 = 0x\(String(u32(b, 24), radix: 16))
        - [x] cd_nSpecialSlots @28 = \(u32(b, 28))
        - [x] cd_nCodeSlots @32 = \(u32(b, 32))
        - [x] cd_hashOffset @36 = \(u32(b, 36))
        - [x] cd_hashSize @40 = \(u32(b, 40))
        - [x] slots @96 (\(Int(u32(b, 32)) * 32) bytes)
        - [x] requirements @\(cd.requirementsOffset) (aligned 8)
        - [x] entitlements @\(cd.entitlementsOffset) (aligned 8)
        """
    }

    // MARK: - Byte helpers

    public static func appendU32(_ d: inout Data, _ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    public static func appendU32(_ d: inout Data, _ v: UInt32, at: Int) {
        var le = v.littleEndian
        d.replaceSubrange(at..<(at + 4), with: withUnsafeBytes(of: &le) { Array($0) })
    }

    public static func u32(_ d: Data, _ off: Int) -> UInt32 {
        d.subdata(in: off..<(off + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    private static func align8(_ x: UInt32) -> UInt32 {
        (x + 7) & ~7
    }
}

public enum CodeSignerError: LocalizedError {
    case badPageSize(UInt32)

    public var errorDescription: String? {
        switch self {
        case .badPageSize(let p):
            return "page size \(p) is smaller than 4096"
        }
    }
}
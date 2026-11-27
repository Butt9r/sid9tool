//
// main.swift — CI self-check entry point (P1-3 / P1-4).
// Run on the CI macOS runner:
//   swiftc -o selfcheck main.swift src/sid9tool/Services/MachO.swift src/sid9tool/Services/CodeSigner.swift && ./selfcheck
// Exits non-zero if any check fails.
//
import Foundation

let machReport = MachO.selfCheck()
if machReport != "OK" {
    print("MachO self-check FAILED: \(machReport)")
    exit(1)
}
print("MachO self-check: OK")

let csReport = CodeSigner.selfCheck()
if !csReport.isEmpty {
    print("CodeSigner self-check FAILED:\n\(csReport)")
    exit(1)
}
print("CodeSigner self-check: OK")

// P1-3: list load commands of a synthetic thin arm64e binary.
var d = Data()
func w32(_ v: UInt32) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
func w32s(_ v: Int32) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
func w64(_ v: UInt64) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
func wstr(_ s: String) { for c in s.utf8 { d.append(c) }; d.append(0) }
w32(MachOMagic.mhMagic64); w32s(MachOCPU.arm64); w32s(MachOCPU.subTypeArm64E)
w32(2); w32(2); w32(88); w32(0); w32(0)
w32(MachOLC.segment64); w32(72)
d.append(Array("__TEXT".utf8)); d.append(Data(count: 16 - 6)) // segname[16]
w64(0x100000000); w64(0x1000); w64(0); w64(0x1000); w32(7); w32(5); w32(0); w32(0)
w32(MachOLC.codeSignature); w32(16); w32(0x2000); w32(0x100)
do {
    let p = try MachO.parse(d)
    print("Load commands of synthetic arm64e binary:")
    for line in MachO.loadCommandDescriptions(p) { print("  \(line)") }
} catch {
    print("MachO parse of synthetic binary failed: \(error)")
    exit(1)
}
print("selfcheck: all OK")

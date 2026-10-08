//
//  s256mTests.swift
//  s256mTests
//
//  Created by Marko Kucher on 8/10/26.
//

import Testing
import Foundation
@testable import s256m

struct ChecksumEngineTests {

    @Test func testEmptyDataVectors() async throws {
        let engine = ChecksumEngine()
        let result = await engine.computeChecksums(for: Data())

        #expect(result.sha256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(result.md5 == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(result.fileByteCount == 0)
    }

    @Test func testStandardKnownTestVector() async throws {
        let engine = ChecksumEngine()
        let sampleString = "The quick brown fox jumps over the lazy dog"
        let data = Data(sampleString.utf8)

        let result = await engine.computeChecksums(for: data)

        #expect(result.sha256 == "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")
        #expect(result.md5 == "9e107d9d372bb6826bd81d3542a419d6")
        #expect(result.fileByteCount == Int64(data.count))
    }

    @Test func testStreamingFromFileAcrossMultipleChunks() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("s256m_test_\(UUID().uuidString).bin")

        // Create a 2.5 MB test file
        let chunkSize = 512 * 1024
        let totalSize = 5 * chunkSize // 2.5 MB
        var pseudoRandomData = Data(count: totalSize)
        for i in 0..<totalSize {
            pseudoRandomData[i] = UInt8(i % 251)
        }
        try pseudoRandomData.write(to: fileURL)

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let engine = ChecksumEngine()
        var progressCallbacks = 0
        var lastReportedBytes: Int64 = 0

        // Use a small buffer size (256 KB) to force multiple streaming chunk reads
        let result = try await engine.computeChecksums(
            for: fileURL,
            bufferSize: 256 * 1024
        ) { progress in
            progressCallbacks += 1
            lastReportedBytes = progress.bytesProcessed
        }

        let expectedInMemoryResult = await engine.computeChecksums(for: pseudoRandomData)

        #expect(result.sha256 == expectedInMemoryResult.sha256)
        #expect(result.md5 == expectedInMemoryResult.md5)
        #expect(result.fileByteCount == Int64(totalSize))
        #expect(lastReportedBytes == Int64(totalSize))
        #expect(progressCallbacks > 0)
    }

    @Test func testHashMatchingLogic() {
        let result = ChecksumResult(
            sha256: "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592",
            md5: "9e107d9d372bb6826bd81d3542a419d6",
            fileByteCount: 1024,
            duration: 0.1,
            throughputBytesPerSecond: 10240
        )

        // Exact match
        #expect(result.matches(candidate: "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592") == .sha256)
        // Uppercase and whitespace
        #expect(result.matches(candidate: "  D7A8FBB307D7809469CA9ABCB0082E4F8D5651E46D3CDB762D02D0BF37C9E592 \n") == .sha256)
        // Prefix "sha256:"
        #expect(result.matches(candidate: "SHA256: d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592") == .sha256)
        // Prefix "sha256="
        #expect(result.matches(candidate: "sha256=d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592") == .sha256)
        // MD5 match
        #expect(result.matches(candidate: "9e107d9d372bb6826bd81d3542a419d6") == .md5)
        #expect(result.matches(candidate: "MD5: 9E107D9D372BB6826BD81D3542A419D6") == .md5)
        // Mismatch
        #expect(result.matches(candidate: "deadbeef") == .none)
        #expect(result.matches(candidate: "") == .none)
    }

    @Test func testTargetDriveProperties() {
        let drive = TargetDrive(
            bsdName: "disk3",
            mediaName: "Ultra Luxe",
            vendor: "SanDisk",
            model: "Ultra Luxe USB 3.1",
            protocolName: "USB",
            totalBytes: 32_000_000_000,
            isRemovable: true,
            isEjectable: true,
            isInternal: false,
            isWritable: true,
            volumeNames: ["INSTALLER"]
        )

        #expect(drive.id == "disk3")
        #expect(drive.rawDevicePath == "/dev/rdisk3")
        #expect(drive.blockDevicePath == "/dev/disk3")
        #expect(drive.isInternal == false)
        #expect(drive.displayName.contains("disk3"))
        #expect(drive.displayName.contains("INSTALLER"))
    }
}

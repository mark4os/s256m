//
//  s256mTests.swift
//  s256mTests
//
//  Created by Marko Kucher on 8/10/26.
//

import Testing
import Foundation
@preconcurrency import DiskArbitration
@testable import s256m

// MARK: - Thread-Safe Test Synchronization Primitives

private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _callbackCount: Int = 0
    private var _lastBytes: Int64 = 0

    var callbackCount: Int {
        lock.withLock { _callbackCount }
    }

    var lastBytes: Int64 {
        lock.withLock { _lastBytes }
    }

    func record(bytes: Int64) {
        lock.withLock {
            _callbackCount += 1
            _lastBytes = bytes
        }
    }
}

private final class WritePhaseTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var _sawWriting: Bool = false
    private var _sawVerifying: Bool = false
    private var _sawCompleted: Bool = false

    var sawWriting: Bool {
        lock.withLock { _sawWriting }
    }

    var sawVerifying: Bool {
        lock.withLock { _sawVerifying }
    }

    var sawCompleted: Bool {
        lock.withLock { _sawCompleted }
    }

    func record(_ state: WriteState) {
        lock.withLock {
            switch state {
            case .writing:
                _sawWriting = true
            case .verifying:
                _sawVerifying = true
            case .completed:
                _sawCompleted = true
            default:
                break
            }
        }
    }
}

// MARK: - Test Suites

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
        let tracker = ProgressTracker()

        // Use a small buffer size (256 KB) to force multiple streaming chunk reads
        let result = try await engine.computeChecksums(
            for: fileURL,
            bufferSize: 256 * 1024
        ) { progress in
            tracker.record(bytes: progress.bytesProcessed)
        }

        let expectedInMemoryResult = await engine.computeChecksums(for: pseudoRandomData)

        #expect(result.sha256 == expectedInMemoryResult.sha256)
        #expect(result.md5 == expectedInMemoryResult.md5)
        #expect(result.fileByteCount == Int64(totalSize))
        #expect(tracker.lastBytes == Int64(totalSize))
        #expect(tracker.callbackCount > 0)
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

struct DiskSafetyTests {

    @Test func testExtractWholeDiskBSDName() {
        #expect(DiskSafetyValidator.extractWholeDiskBSDName(from: "/dev/disk3s1s1") == "disk3")
        #expect(DiskSafetyValidator.extractWholeDiskBSDName(from: "/dev/rdisk4") == "disk4")
        #expect(DiskSafetyValidator.extractWholeDiskBSDName(from: "disk12s2") == "disk12")
        #expect(DiskSafetyValidator.extractWholeDiskBSDName(from: "disk0") == "disk0")
        #expect(DiskSafetyValidator.extractWholeDiskBSDName(from: "/dev/disk5") == "disk5")
    }

    @Test func testSystemDiskDetectionFindsBootDrive() {
        let systemDisks = DiskSafetyValidator.querySystemDisks()
        // The host machine must have at least one detected system disk (e.g. disk3 or disk1)
        #expect(!systemDisks.isEmpty)
    }

    @Test func testEvaluationBlocksInternalDisks() {
        let internalDesc: [String: Any] = [
            kDADiskDescriptionMediaBSDNameKey as String: "disk0",
            kDADiskDescriptionMediaWholeKey as String: true,
            kDADiskDescriptionDeviceInternalKey as String: true,
            kDADiskDescriptionMediaWritableKey as String: true,
            kDADiskDescriptionMediaSizeKey as String: NSNumber(value: 1_000_000_000_000),
            kDADiskDescriptionDeviceProtocolKey as String: "Apple Fabric"
        ]

        let (isSafe, reason) = DiskSafetyValidator.evaluateDisk(
            description: internalDesc,
            systemDiskBlacklist: []
        )
        #expect(isSafe == false)
        #expect(reason?.contains("internal") == true)
    }

    @Test func testEvaluationBlocksSystemDisksInBlacklist() {
        let targetDesc: [String: Any] = [
            kDADiskDescriptionMediaBSDNameKey as String: "disk2",
            kDADiskDescriptionMediaWholeKey as String: true,
            kDADiskDescriptionDeviceInternalKey as String: false,
            kDADiskDescriptionMediaWritableKey as String: true,
            kDADiskDescriptionMediaSizeKey as String: NSNumber(value: 32_000_000_000),
            kDADiskDescriptionDeviceProtocolKey as String: "USB",
            kDADiskDescriptionMediaRemovableKey as String: true
        ]

        let (isSafe, reason) = DiskSafetyValidator.evaluateDisk(
            description: targetDesc,
            systemDiskBlacklist: ["disk2"]
        )
        #expect(isSafe == false)
        #expect(reason?.contains("system or boot") == true)
    }

    @Test func testEvaluationBlocksPartitions() {
        let partitionDesc: [String: Any] = [
            kDADiskDescriptionMediaBSDNameKey as String: "disk4s1",
            kDADiskDescriptionMediaWholeKey as String: false,
            kDADiskDescriptionDeviceInternalKey as String: false,
            kDADiskDescriptionMediaWritableKey as String: true,
            kDADiskDescriptionMediaSizeKey as String: NSNumber(value: 16_000_000_000),
            kDADiskDescriptionDeviceProtocolKey as String: "USB"
        ]

        let (isSafe, reason) = DiskSafetyValidator.evaluateDisk(
            description: partitionDesc,
            systemDiskBlacklist: []
        )
        #expect(isSafe == false)
        #expect(reason?.contains("partition") == true)
    }

    @Test func testEvaluationBlocksVirtualAndFabricProtocols() {
        let virtualDesc: [String: Any] = [
            kDADiskDescriptionMediaBSDNameKey as String: "disk7",
            kDADiskDescriptionMediaWholeKey as String: true,
            kDADiskDescriptionDeviceInternalKey as String: false,
            kDADiskDescriptionMediaWritableKey as String: true,
            kDADiskDescriptionMediaSizeKey as String: NSNumber(value: 20_000_000_000),
            kDADiskDescriptionDeviceProtocolKey as String: "Virtual Interface",
            kDADiskDescriptionMediaRemovableKey as String: true
        ]

        let (isSafe, reason) = DiskSafetyValidator.evaluateDisk(
            description: virtualDesc,
            systemDiskBlacklist: []
        )
        #expect(isSafe == false)
        #expect(reason?.contains("Virtual Interface") == true)
    }

    @Test func testEvaluationAcceptsValidExternalUSBFlashDrive() {
        let usbDesc: [String: Any] = [
            kDADiskDescriptionMediaBSDNameKey as String: "disk4",
            kDADiskDescriptionMediaWholeKey as String: true,
            kDADiskDescriptionDeviceInternalKey as String: false,
            kDADiskDescriptionMediaWritableKey as String: true,
            kDADiskDescriptionMediaSizeKey as String: NSNumber(value: 64_000_000_000),
            kDADiskDescriptionDeviceProtocolKey as String: "USB",
            kDADiskDescriptionMediaRemovableKey as String: true,
            kDADiskDescriptionDeviceVendorKey as String: "SanDisk",
            kDADiskDescriptionDeviceModelKey as String: "Ultra Flair",
            kDADiskDescriptionMediaNameKey as String: "SanDisk Media"
        ]

        let (isSafe, reason) = DiskSafetyValidator.evaluateDisk(
            description: usbDesc,
            systemDiskBlacklist: ["disk1", "disk3"]
        )
        #expect(isSafe == true)
        #expect(reason == nil)

        let drive = DiskSafetyValidator.parseTargetDrive(
            description: usbDesc,
            volumeNames: ["ARCH_LINUX", "EFI"]
        )
        #expect(drive != nil)
        #expect(drive?.bsdName == "disk4")
        #expect(drive?.vendor == "SanDisk")
        #expect(drive?.model == "Ultra Flair")
        #expect(drive?.volumeNames == ["ARCH_LINUX", "EFI"])
        #expect(drive?.displayName.contains("disk4") == true)
    }
}

struct DiskWriterTests {

    @Test func testWriteAndVerifyToVirtualFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("s256m_source_\(UUID().uuidString).iso")
        let destURL = tempDir.appendingPathComponent("s256m_dest_\(UUID().uuidString).img")

        // 1.5 MB test payload
        let payloadSize = 1536 * 1024
        var testData = Data(count: payloadSize)
        for i in 0..<payloadSize {
            testData[i] = UInt8((i * 17 + 3) % 256)
        }
        try testData.write(to: sourceURL)

        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }

        let writer = DiskWriter()
        let phaseTracker = WritePhaseTracker()

        let result = try await writer.writeAndVerify(
            imageURL: sourceURL,
            destinationPath: destURL.path,
            expectedCapacity: Int64(payloadSize * 2),
            verify: true,
            chunkSize: 256 * 1024
        ) { progress in
            phaseTracker.record(progress)
        }

        #expect(phaseTracker.sawWriting)
        #expect(phaseTracker.sawVerifying)
        #expect(phaseTracker.sawCompleted)
        #expect(result.fileByteCount == Int64(payloadSize))

        // Read destination file back and check byte-for-byte equality
        let writtenData = try Data(contentsOf: destURL)
        #expect(writtenData == testData)

        let engine = ChecksumEngine()
        let expectedResult = await engine.computeChecksums(for: testData)
        #expect(result.sha256 == expectedResult.sha256)
        #expect(result.md5 == expectedResult.md5)
    }

    @Test func testCapacityCheckBlocksUndersizedDestinations() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("s256m_cap_\(UUID().uuidString).iso")
        let destURL = tempDir.appendingPathComponent("s256m_dest_\(UUID().uuidString).img")

        let payload = Data(repeating: 0xAA, count: 1024 * 1024) // 1 MB
        try payload.write(to: sourceURL)

        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }

        let writer = DiskWriter()
        do {
            // Target capacity is 512 KB, but image is 1 MB
            try await writer.writeAndVerify(
                imageURL: sourceURL,
                destinationPath: destURL.path,
                expectedCapacity: 512 * 1024,
                verify: false
            )
            #expect(Bool(false), "Should have thrown insufficientCapacity error")
        } catch let error as DiskWriterError {
            switch error {
            case .insufficientCapacity(let req, let avail):
                #expect(req == 1024 * 1024)
                #expect(avail == 512 * 1024)
            default:
                #expect(Bool(false), "Unexpected error: \(error)")
            }
        }
    }
}

// MARK: - Tier 3: Authenticity Tests

struct AuthenticityTests {

    @Test func testSignatureStatusEnumProperties() {
        let noneStatus = SignatureStatus.none
        #expect(noneStatus.isVerified == false)
        #expect(noneStatus.publisher == nil)
        #expect(noneStatus.teamID == nil)
        #expect(noneStatus.isNotarized == false)

        let checkingStatus = SignatureStatus.checking
        #expect(checkingStatus.isVerified == false)

        let verifiedStatus = SignatureStatus.verified(
            publisher: "Developer ID Application: Acorn Ltd",
            teamID: "876XYZ4321",
            isNotarized: true
        )
        #expect(verifiedStatus.isVerified == true)
        #expect(verifiedStatus.publisher == "Developer ID Application: Acorn Ltd")
        #expect(verifiedStatus.teamID == "876XYZ4321")
        #expect(verifiedStatus.isNotarized == true)
        #expect(verifiedStatus.displayTitle == "Developer ID Application: Acorn Ltd")

        let unsignedStatus = SignatureStatus.unsigned
        #expect(unsignedStatus.isVerified == false)
        #expect(unsignedStatus.displayTitle == "Unsigned Media")

        let invalidStatus = SignatureStatus.invalid(reason: "Root certificate revoked")
        #expect(invalidStatus.isVerified == false)
        #expect(invalidStatus.displayTitle.contains("Root certificate revoked"))
    }

    @Test func testEvaluateUnsignedTempFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let rawIsoURL = tempDir.appendingPathComponent("s256m_raw_\(UUID().uuidString).iso")
        try "RAW LINUX DISK IMAGE DATA".data(using: .utf8)?.write(to: rawIsoURL)

        defer {
            try? FileManager.default.removeItem(at: rawIsoURL)
        }

        let engine = AuthenticityEngine()
        let status = await engine.evaluate(url: rawIsoURL)

        #expect(status == .unsigned)
    }

    @Test func testEvaluateSystemSignedApp() async {
        let calcURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        guard FileManager.default.fileExists(atPath: calcURL.path) else { return }

        let engine = AuthenticityEngine()
        let status = await engine.evaluate(url: calcURL)

        #expect(status.isVerified == true)
        if case .verified(let publisher, _, _) = status {
            #expect(!publisher.isEmpty)
        }
    }
}

@MainActor
struct AppStateTests {

    @Test func testInitialAppState() {
        let appState = AppState(autoStartMonitoring: false)
        #expect(appState.selectedImageURL == nil)
        #expect(appState.imageByteCount == 0)
        #expect(appState.checksumResult == nil)
        #expect(appState.isCalculatingChecksum == false)
        #expect(appState.signatureStatus == .none)
        #expect(appState.selectedDrive == nil)
        #expect(appState.canStartWrite == false)
    }

    @Test func testSelectImageAndClear() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let sampleURL = tempDir.appendingPathComponent("s256m_ui_test_\(UUID().uuidString).iso")
        let sampleData = Data("Small Test ISO Content".utf8)
        try sampleData.write(to: sampleURL)

        defer {
            try? FileManager.default.removeItem(at: sampleURL)
        }

        let appState = AppState(autoStartMonitoring: false)
        appState.selectImage(url: sampleURL)

        #expect(appState.selectedImageURL == sampleURL)
        #expect(appState.imageByteCount == Int64(sampleData.count))

        // Wait briefly for streaming hashing and authenticity to complete
        for _ in 0..<30 {
            if appState.checksumResult != nil && appState.signatureStatus != .checking { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(appState.checksumResult != nil)
        #expect(appState.isCalculatingChecksum == false)
        #expect(appState.checksumProgressFraction == 1.0)
        #expect(appState.signatureStatus == .unsigned)

        // Clear image
        appState.clearSelectedImage()
        #expect(appState.selectedImageURL == nil)
        #expect(appState.checksumResult == nil)
        #expect(appState.signatureStatus == .none)
    }

    @Test func testCanStartWriteConditions() {
        let appState = AppState(autoStartMonitoring: false)

        // No image, no drive
        #expect(appState.canStartWrite == false)

        // Setup mock image
        appState.selectedImageURL = URL(fileURLWithPath: "/tmp/fake.iso")
        appState.imageByteCount = 4_000_000_000 // 4 GB

        // No drive yet
        #expect(appState.canStartWrite == false)

        // Drive with insufficient capacity (2 GB)
        appState.selectedDrive = TargetDrive(
            bsdName: "disk4",
            mediaName: "Small Flash",
            totalBytes: 2_000_000_000,
            isRemovable: true,
            isEjectable: true,
            isInternal: false,
            isWritable: true
        )
        #expect(appState.canStartWrite == false)

        // Drive with ample capacity (32 GB)
        appState.selectedDrive = TargetDrive(
            bsdName: "disk4",
            mediaName: "Large Flash",
            totalBytes: 32_000_000_000,
            isRemovable: true,
            isEjectable: true,
            isInternal: false,
            isWritable: true
        )
        #expect(appState.canStartWrite == true)
    }
}

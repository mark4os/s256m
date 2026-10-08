//
//  DiskWriter.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation
@preconcurrency import DiskArbitration
import CryptoKit

/// Errors that may occur during unmounting, block writing, or verification.
public enum DiskWriterError: LocalizedError, Sendable, Equatable {
    case fileNotFound(URL)
    case unreadableSource(String)
    case insufficientCapacity(required: Int64, available: Int64)
    case unmountFailed(String)
    case deviceOpenFailed(path: String, errorCode: Int32, reason: String)
    case writeFailed(errorCode: Int32, reason: String)
    case readBackFailed(errorCode: Int32, reason: String)
    case verificationMismatch(expected: String, actual: String)
    case ejectFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Source image file not found at: \(url.path)"
        case .unreadableSource(let reason):
            return "Cannot read source image: \(reason)"
        case .insufficientCapacity(let req, let avail):
            let reqStr = ByteCountFormatter.string(fromByteCount: req, countStyle: .file)
            let availStr = ByteCountFormatter.string(fromByteCount: avail, countStyle: .file)
            return "Insufficient target drive capacity. Image requires \(reqStr), but drive only has \(availStr)."
        case .unmountFailed(let reason):
            return "Failed to unmount target drive partitions: \(reason)"
        case .deviceOpenFailed(let path, let code, let reason):
            return "Could not open target device '\(path)' (errno \(code): \(reason))."
        case .writeFailed(let code, let reason):
            return "Write operation failed (errno \(code): \(reason))."
        case .readBackFailed(let code, let reason):
            return "Verification read failed (errno \(code): \(reason))."
        case .verificationMismatch(let expected, let actual):
            return "Verification failed! Checksum mismatch.\nExpected: \(expected)\nActual:   \(actual)"
        case .ejectFailed(let reason):
            return "Failed to eject target drive: \(reason)"
        case .cancelled:
            return "Operation was cancelled."
        }
    }
}

/// Actor responsible for safely unmounting target storage, streaming disk image blocks,
/// synchronizing hardware write buffers, and verifying block integrity.
public actor DiskWriter {

    /// Default chunk size for block streaming (1 MB page-aligned).
    public static let defaultChunkSize: Int = 1 * 1024 * 1024

    public init() {}

    /// Writes an image to a raw device path or file, computing checksum and verifying in a single workflow.
    ///
    /// - Parameters:
    ///   - imageURL: The source disk image (ISO, DMG, etc.).
    ///   - destinationPath: The raw device path (e.g. "/dev/rdisk4") or file path for testing.
    ///   - expectedCapacity: Total capacity of the target destination in bytes.
    ///   - targetBSDName: The BSD name if targeting a physical disk (e.g. "disk4"), or nil for testing.
    ///   - verify: Whether to read back written blocks and verify SHA-256 integrity.
    ///   - onProgress: Callback for real-time progress updates.
    /// - Returns: The verified `ChecksumResult`.
    @discardableResult
    public func writeAndVerify(
        imageURL: URL,
        destinationPath: String,
        expectedCapacity: Int64,
        targetBSDName: String? = nil,
        verify: Bool = true,
        chunkSize: Int = defaultChunkSize,
        onProgress: (@Sendable (WriteState) -> Void)? = nil
    ) async throws -> ChecksumResult {
        let isSecurityScoped = imageURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                imageURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: imageURL.path) else {
            throw DiskWriterError.fileNotFound(imageURL)
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: imageURL.path)
        } catch {
            throw DiskWriterError.unreadableSource(error.localizedDescription)
        }

        let imageByteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard imageByteCount > 0 else {
            throw DiskWriterError.unreadableSource("Source image is empty (0 bytes).")
        }

        if expectedCapacity > 0 && imageByteCount > expectedCapacity {
            throw DiskWriterError.insufficientCapacity(
                required: imageByteCount,
                available: expectedCapacity
            )
        }

        // Phase 1: Unmount target drive if a BSD name is provided
        if let targetBSDName {
            onProgress?(.unmounting(targetDrive: targetBSDName))
            try await unmountDisk(bsdName: targetBSDName)
        }

        // Phase 2: Open source file
        let sourceHandle: FileHandle
        do {
            sourceHandle = try FileHandle(forReadingFrom: imageURL)
        } catch {
            throw DiskWriterError.unreadableSource(error.localizedDescription)
        }
        defer {
            try? sourceHandle.close()
        }

        // Phase 3: Open destination for writing
        // Using POSIX open with O_WRONLY | O_SYNC (or O_CREAT for regular files)
        let openFlags: Int32
        let fileMode: mode_t
        if destinationPath.hasPrefix("/dev/") {
            openFlags = O_WRONLY | O_SYNC
            fileMode = 0
        } else {
            openFlags = O_WRONLY | O_CREAT | O_TRUNC | O_SYNC
            fileMode = 0o666
        }

        let destFD = open(destinationPath, openFlags, fileMode)
        guard destFD >= 0 else {
            let err = errno
            let reason = String(cString: strerror(err))
            throw DiskWriterError.deviceOpenFailed(path: destinationPath, errorCode: err, reason: reason)
        }

        var sourceHasher256 = SHA256()
        var sourceHasherMD5 = Insecure.MD5()

        let writeStartTime = ContinuousClock.now
        var lastWriteReport = ContinuousClock.now
        var bytesWritten: Int64 = 0

        // Streaming block write loop
        do {
            while bytesWritten < imageByteCount {
                try Task.checkCancellation()

                let chunk: Data?
                do {
                    chunk = try sourceHandle.read(upToCount: chunkSize)
                } catch {
                    close(destFD)
                    throw DiskWriterError.unreadableSource(error.localizedDescription)
                }

                guard let chunk, !chunk.isEmpty else { break }

                // Update hashers
                chunk.withUnsafeBytes { rawBuffer in
                    sourceHasher256.update(bufferPointer: rawBuffer)
                    sourceHasherMD5.update(bufferPointer: rawBuffer)
                }

                // Direct write to target descriptor
                let written = chunk.withUnsafeBytes { rawBuffer -> Int in
                    write(destFD, rawBuffer.baseAddress, rawBuffer.count)
                }

                if written < 0 {
                    let err = errno
                    let reason = String(cString: strerror(err))
                    close(destFD)
                    throw DiskWriterError.writeFailed(errorCode: err, reason: reason)
                }

                bytesWritten += Int64(written)

                let now = ContinuousClock.now
                let elapsed = writeStartTime.duration(to: now)
                let elapsedSec = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

                let sinceLast = lastWriteReport.duration(to: now)
                let sinceLastSec = Double(sinceLast.components.seconds) + Double(sinceLast.components.attoseconds) * 1e-18

                if sinceLastSec >= 0.033 || bytesWritten >= imageByteCount {
                    let speed = elapsedSec > 0 ? Double(bytesWritten) / elapsedSec : 0
                    let fraction = imageByteCount > 0 ? min(1.0, Double(bytesWritten) / Double(imageByteCount)) : 1.0
                    let remainingBytes = max(0, imageByteCount - bytesWritten)
                    let eta = speed > 0 ? Double(remainingBytes) / speed : nil

                    onProgress?(.writing(
                        bytesWritten: bytesWritten,
                        totalBytes: imageByteCount,
                        fraction: fraction,
                        speedBytesPerSecond: speed,
                        etaSeconds: eta
                    ))
                    lastWriteReport = now
                }
            }

            // Hardware flush
            fsync(destFD)
            close(destFD)
        } catch is CancellationError {
            close(destFD)
            onProgress?(.cancelled)
            throw DiskWriterError.cancelled
        } catch {
            close(destFD)
            throw error
        }

        let writeDuration = writeStartTime.duration(to: ContinuousClock.now)
        let writeDurationSec = max(0.0001, Double(writeDuration.components.seconds) +
            Double(writeDuration.components.attoseconds) * 1e-18)

        let expectedSHA256 = ChecksumEngine.hexString(from: sourceHasher256.finalize())
        let expectedMD5 = ChecksumEngine.hexString(from: sourceHasherMD5.finalize())

        // Phase 4: Verification (if requested)
        if verify {
            try Task.checkCancellation()

            let verifyFD = open(destinationPath, O_RDONLY)
            guard verifyFD >= 0 else {
                let err = errno
                let reason = String(cString: strerror(err))
                throw DiskWriterError.deviceOpenFailed(path: destinationPath, errorCode: err, reason: reason)
            }

            var verifyHasher = SHA256()
            var bytesVerified: Int64 = 0
            let verifyStartTime = ContinuousClock.now
            var lastVerifyReport = ContinuousClock.now

            var verifyBuffer = [UInt8](repeating: 0, count: chunkSize)

            do {
                while bytesVerified < imageByteCount {
                    try Task.checkCancellation()

                    let bytesToRead = min(Int64(chunkSize), imageByteCount - bytesVerified)
                    let readCount = read(verifyFD, &verifyBuffer, Int(bytesToRead))

                    if readCount < 0 {
                        let err = errno
                        let reason = String(cString: strerror(err))
                        close(verifyFD)
                        throw DiskWriterError.readBackFailed(errorCode: err, reason: reason)
                    }

                    if readCount == 0 { break }

                    verifyBuffer.withUnsafeBytes { rawBuffer in
                        let sub = UnsafeRawBufferPointer(rebasing: rawBuffer.prefix(readCount))
                        verifyHasher.update(bufferPointer: sub)
                    }

                    bytesVerified += Int64(readCount)

                    let now = ContinuousClock.now
                    let elapsed = verifyStartTime.duration(to: now)
                    let elapsedSec = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18

                    let sinceLast = lastVerifyReport.duration(to: now)
                    let sinceLastSec = Double(sinceLast.components.seconds) + Double(sinceLast.components.attoseconds) * 1e-18

                    if sinceLastSec >= 0.033 || bytesVerified >= imageByteCount {
                        let speed = elapsedSec > 0 ? Double(bytesVerified) / elapsedSec : 0
                        let fraction = imageByteCount > 0 ? min(1.0, Double(bytesVerified) / Double(imageByteCount)) : 1.0
                        let remaining = max(0, imageByteCount - bytesVerified)
                        let eta = speed > 0 ? Double(remaining) / speed : nil

                        onProgress?(.verifying(
                            bytesVerified: bytesVerified,
                            totalBytes: imageByteCount,
                            fraction: fraction,
                            speedBytesPerSecond: speed,
                            etaSeconds: eta
                        ))
                        lastVerifyReport = now
                    }
                }

                close(verifyFD)
            } catch is CancellationError {
                close(verifyFD)
                onProgress?(.cancelled)
                throw DiskWriterError.cancelled
            } catch {
                close(verifyFD)
                throw error
            }

            let actualSHA256 = ChecksumEngine.hexString(from: verifyHasher.finalize())
            guard actualSHA256 == expectedSHA256 else {
                let mismatchError = DiskWriterError.verificationMismatch(
                    expected: expectedSHA256,
                    actual: actualSHA256
                )
                onProgress?(.failed(message: mismatchError.localizedDescription))
                throw mismatchError
            }
        }

        // Phase 5: Eject target drive if physical
        if let targetBSDName {
            try? await ejectDisk(bsdName: targetBSDName)
        }

        onProgress?(.completed(totalBytes: bytesWritten, totalDuration: writeDurationSec))

        return ChecksumResult(
            sha256: expectedSHA256,
            md5: expectedMD5,
            fileByteCount: bytesWritten,
            duration: writeDurationSec,
            throughputBytesPerSecond: Double(bytesWritten) / writeDurationSec
        )
    }

    // MARK: - DiskArbitration Unmount & Eject Helpers

    private func unmountDisk(bsdName: String) async throws {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw DiskWriterError.unmountFailed("Could not create DiskArbitration session.")
        }

        let queue = DispatchQueue(label: "com.s256m.unmount")
        DASessionSetDispatchQueue(session, queue)
        defer {
            DASessionSetDispatchQueue(session, nil)
        }

        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            throw DiskWriterError.unmountFailed("Could not resolve DADisk for '\(bsdName)'.")
        }

        final class Box<T>: @unchecked Sendable {
            var value: T
            init(_ value: T) { self.value = value }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let boxed = Unmanaged.passRetained(Box(continuation)).toOpaque()

            DADiskUnmount(
                disk,
                DADiskUnmountOptions(kDADiskUnmountOptionWhole),
                { disk, dissenter, context in
                    guard let context else { return }
                    let box = Unmanaged<Box<CheckedContinuation<Void, Error>>>.fromOpaque(context).takeRetainedValue()

                    if let dissenter {
                        let status = DADissenterGetStatus(dissenter)
                        let str = DADissenterGetStatusString(dissenter) as String? ?? "Status \(status)"
                        box.value.resume(throwing: DiskWriterError.unmountFailed(str))
                    } else {
                        box.value.resume(returning: ())
                    }
                },
                boxed
            )
        }
    }

    private func ejectDisk(bsdName: String) async throws {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            throw DiskWriterError.ejectFailed("Could not create DiskArbitration session.")
        }

        let queue = DispatchQueue(label: "com.s256m.eject")
        DASessionSetDispatchQueue(session, queue)
        defer {
            DASessionSetDispatchQueue(session, nil)
        }

        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            throw DiskWriterError.ejectFailed("Could not resolve DADisk for '\(bsdName)'.")
        }

        final class Box<T>: @unchecked Sendable {
            var value: T
            init(_ value: T) { self.value = value }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let boxed = Unmanaged.passRetained(Box(continuation)).toOpaque()

            DADiskEject(
                disk,
                DADiskEjectOptions(kDADiskEjectOptionDefault),
                { disk, dissenter, context in
                    guard let context else { return }
                    let box = Unmanaged<Box<CheckedContinuation<Void, Error>>>.fromOpaque(context).takeRetainedValue()

                    if let dissenter {
                        let status = DADissenterGetStatus(dissenter)
                        let str = DADissenterGetStatusString(dissenter) as String? ?? "Status \(status)"
                        box.value.resume(throwing: DiskWriterError.ejectFailed(str))
                    } else {
                        box.value.resume(returning: ())
                    }
                },
                boxed
            )
        }
    }
}

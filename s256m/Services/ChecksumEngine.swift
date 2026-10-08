//
//  ChecksumEngine.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation
import CryptoKit

/// Errors encountered during checksum computation.
public enum ChecksumEngineError: LocalizedError, Sendable {
    case fileNotFound(URL)
    case unreadableFile(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File could not be found at path: \(url.path)"
        case .unreadableFile(let reason):
            return "Unable to read file: \(reason)"
        case .cancelled:
            return "Checksum calculation was cancelled."
        }
    }
}

/// A high-performance, actor-isolated engine that computes SHA-256 and MD5 checksums
/// in a single streaming pass using Apple's CryptoKit framework.
public actor ChecksumEngine {
    /// Live progress event during computation.
    public struct ProgressUpdate: Sendable, Equatable {
        public let bytesProcessed: Int64
        public let totalBytes: Int64
        public let fractionCompleted: Double
        public let speedBytesPerSecond: Double

        public init(
            bytesProcessed: Int64,
            totalBytes: Int64,
            fractionCompleted: Double,
            speedBytesPerSecond: Double
        ) {
            self.bytesProcessed = bytesProcessed
            self.totalBytes = totalBytes
            self.fractionCompleted = fractionCompleted
            self.speedBytesPerSecond = speedBytesPerSecond
        }
    }

    /// Default streaming buffer size (4 MB), aligned with typical storage block sizes.
    public static let defaultBufferSize: Int = 4 * 1024 * 1024

    public init() {}

    /// Computes both SHA-256 and MD5 checksums for the file at the given URL in a single pass.
    ///
    /// - Parameters:
    ///   - url: The file URL to read from.
    ///   - bufferSize: The chunk size to read into memory per iteration. Defaults to 4 MB.
    ///   - onProgress: An optional callback invoked periodically with progress metrics.
    /// - Returns: A `ChecksumResult` containing the computed digests, duration, and throughput.
    public func computeChecksums(
        for url: URL,
        bufferSize: Int = defaultBufferSize,
        onProgress: (@Sendable (ProgressUpdate) -> Void)? = nil
    ) async throws -> ChecksumResult {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw ChecksumEngineError.fileNotFound(url)
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw ChecksumEngineError.unreadableFile(error.localizedDescription)
        }

        let totalBytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forReadingFrom: url)
        } catch {
            throw ChecksumEngineError.unreadableFile(error.localizedDescription)
        }
        defer {
            try? fileHandle.close()
        }

        var hasher256 = SHA256()
        var hasherMD5 = Insecure.MD5()

        var bytesProcessed: Int64 = 0
        let startTime = ContinuousClock.now
        var lastProgressReportTime = ContinuousClock.now

        // Handle empty file case
        if totalBytes == 0 {
            let digest256 = hasher256.finalize()
            let digestMD5 = hasherMD5.finalize()
            return ChecksumResult(
                sha256: Self.hexString(from: digest256),
                md5: Self.hexString(from: digestMD5),
                fileByteCount: 0,
                duration: 0.0001,
                throughputBytesPerSecond: 0
            )
        }

        while bytesProcessed < totalBytes {
            try Task.checkCancellation()

            let chunk: Data?
            do {
                chunk = try fileHandle.read(upToCount: bufferSize)
            } catch {
                throw ChecksumEngineError.unreadableFile(error.localizedDescription)
            }

            guard let chunk, !chunk.isEmpty else { break }

            chunk.withUnsafeBytes { rawBuffer in
                hasher256.update(bufferPointer: rawBuffer)
                hasherMD5.update(bufferPointer: rawBuffer)
            }

            bytesProcessed += Int64(chunk.count)

            let now = ContinuousClock.now
            let elapsedTotal = startTime.duration(to: now)
            let elapsedTotalSeconds = Double(elapsedTotal.components.seconds) +
                Double(elapsedTotal.components.attoseconds) * 1e-18

            let sinceLastReport = lastProgressReportTime.duration(to: now)
            let sinceLastReportSeconds = Double(sinceLastReport.components.seconds) +
                Double(sinceLastReport.components.attoseconds) * 1e-18

            // Throttle progress updates to ~30 Hz or upon completion
            if sinceLastReportSeconds >= 0.033 || bytesProcessed >= totalBytes {
                let speed = elapsedTotalSeconds > 0 ? Double(bytesProcessed) / elapsedTotalSeconds : 0
                let fraction = totalBytes > 0 ? min(1.0, Double(bytesProcessed) / Double(totalBytes)) : 1.0

                onProgress?(ProgressUpdate(
                    bytesProcessed: bytesProcessed,
                    totalBytes: totalBytes,
                    fractionCompleted: fraction,
                    speedBytesPerSecond: speed
                ))
                lastProgressReportTime = now
            }
        }

        try Task.checkCancellation()

        let totalDuration = startTime.duration(to: ContinuousClock.now)
        let totalDurationSeconds = max(0.0001, Double(totalDuration.components.seconds) +
            Double(totalDuration.components.attoseconds) * 1e-18)

        let digest256 = hasher256.finalize()
        let digestMD5 = hasherMD5.finalize()

        return ChecksumResult(
            sha256: Self.hexString(from: digest256),
            md5: Self.hexString(from: digestMD5),
            fileByteCount: bytesProcessed,
            duration: totalDurationSeconds,
            throughputBytesPerSecond: Double(bytesProcessed) / totalDurationSeconds
        )
    }

    /// Computes checksums directly for an in-memory `Data` payload (convenience and testing).
    public func computeChecksums(for data: Data) -> ChecksumResult {
        let startTime = ContinuousClock.now

        var hasher256 = SHA256()
        var hasherMD5 = Insecure.MD5()

        data.withUnsafeBytes { rawBuffer in
            hasher256.update(bufferPointer: rawBuffer)
            hasherMD5.update(bufferPointer: rawBuffer)
        }

        let totalDuration = startTime.duration(to: ContinuousClock.now)
        let totalDurationSeconds = max(0.00001, Double(totalDuration.components.seconds) +
            Double(totalDuration.components.attoseconds) * 1e-18)

        let digest256 = hasher256.finalize()
        let digestMD5 = hasherMD5.finalize()

        return ChecksumResult(
            sha256: Self.hexString(from: digest256),
            md5: Self.hexString(from: digestMD5),
            fileByteCount: Int64(data.count),
            duration: totalDurationSeconds,
            throughputBytesPerSecond: Double(data.count) / totalDurationSeconds
        )
    }

    /// Formats any byte sequence conforming to `Sequence<UInt8>` into a lowercased hex string.
    public static func hexString(from digest: some Sequence<UInt8>) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

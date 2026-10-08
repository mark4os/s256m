//
//  WriteProgress.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation

/// State progression of a disk write and verification pipeline.
nonisolated public enum WriteState: Sendable, Equatable {
    /// Initial or reset state, waiting for user confirmation.
    case idle

    /// Unmounting partitions from the target device.
    case unmounting(targetDrive: String)

    /// Writing blocks to raw disk device.
    case writing(
        bytesWritten: Int64,
        totalBytes: Int64,
        fraction: Double,
        speedBytesPerSecond: Double,
        etaSeconds: Double?
    )

    /// Verifying written data via SHA-256 read-back from raw disk device.
    case verifying(
        bytesVerified: Int64,
        totalBytes: Int64,
        fraction: Double,
        speedBytesPerSecond: Double,
        etaSeconds: Double?
    )

    /// Successfully flashed and verified.
    case completed(totalBytes: Int64, totalDuration: Double)

    /// Operation failed with error description.
    case failed(message: String)

    /// Operation was cancelled by user.
    case cancelled

    /// Whether this state represents a completed or stopped operation.
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    /// Normalized progress fraction between 0.0 and 1.0.
    public var progressFraction: Double {
        switch self {
        case .idle, .unmounting:
            return 0.0
        case .writing(_, _, let fraction, _, _):
            return fraction * 0.5 // First half is writing
        case .verifying(_, _, let fraction, _, _):
            return 0.5 + (fraction * 0.5) // Second half is verifying
        case .completed:
            return 1.0
        case .failed, .cancelled:
            return 0.0
        }
    }

    /// Formatted status summary suitable for UI subtitles.
    public var statusDescription: String {
        switch self {
        case .idle:
            return "Ready to flash"
        case .unmounting(let drive):
            return "Unmounting partitions on \(drive)..."
        case .writing(let written, let total, let fraction, let speed, let eta):
            let percent = Int(fraction * 100)
            let writtenStr = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
            let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            let speedStr = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
            let etaStr = eta.map { String(format: " (ETA: %.0fs)", $0) } ?? ""
            return "Writing: \(percent)% (\(writtenStr) of \(totalStr) at \(speedStr)/s)\(etaStr)"
        case .verifying(let verified, let total, let fraction, let speed, let eta):
            let percent = Int(fraction * 100)
            let verStr = ByteCountFormatter.string(fromByteCount: verified, countStyle: .file)
            let totalStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            let speedStr = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
            let etaStr = eta.map { String(format: " (ETA: %.0fs)", $0) } ?? ""
            return "Verifying: \(percent)% (\(verStr) of \(totalStr) at \(speedStr)/s)\(etaStr)"
        case .completed(_, let duration):
            let timeStr = String(format: "%.1fs", duration)
            return "Flashing & verification completed in \(timeStr)."
        case .failed(let message):
            return "Error: \(message)"
        case .cancelled:
            return "Flashing was cancelled."
        }
    }
}

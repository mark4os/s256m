//
//  ChecksumResult.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation

/// Represents the comparison result of a user-supplied hash against computed hashes.
nonisolated public enum HashMatchType: Sendable, Equatable {
    case sha256
    case md5
    case none
}

/// The immutable result of a completed checksum calculation.
nonisolated public struct ChecksumResult: Sendable, Equatable {
    /// Lowercased hex-encoded SHA-256 digest string.
    public let sha256: String

    /// Lowercased hex-encoded MD5 digest string.
    public let md5: String

    /// Total byte count of the processed file.
    public let fileByteCount: Int64

    /// Duration of the hashing operation in seconds.
    public let duration: TimeInterval

    /// Average throughput in bytes per second.
    public let throughputBytesPerSecond: Double

    public init(
        sha256: String,
        md5: String,
        fileByteCount: Int64,
        duration: TimeInterval,
        throughputBytesPerSecond: Double
    ) {
        self.sha256 = sha256.lowercased()
        self.md5 = md5.lowercased()
        self.fileByteCount = fileByteCount
        self.duration = duration
        self.throughputBytesPerSecond = throughputBytesPerSecond
    }

    /// Formats the file size in human-readable binary units (e.g. 4.29 GB).
    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileByteCount, countStyle: .file)
    }

    /// Formats the hashing throughput (e.g. "1.45 GB/s" or "820 MB/s").
    public var formattedSpeed: String {
        let speed = throughputBytesPerSecond
        if speed >= 1_000_000_000 {
            return String(format: "%.2f GB/s", speed / 1_000_000_000)
        } else if speed >= 1_000_000 {
            return String(format: "%.1f MB/s", speed / 1_000_000)
        } else if speed >= 1_000 {
            return String(format: "%.1f KB/s", speed / 1_000)
        } else {
            return String(format: "%.0f B/s", speed)
        }
    }

    /// Compares a user-provided candidate string (trimmed of whitespace and normalized)
    /// to determine whether it matches either computed digest.
    public func matches(candidate: String) -> HashMatchType {
        let cleaned = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !cleaned.isEmpty else { return .none }

        // Remove possible prefixes like "sha256:", "md5:", or "sha256="
        let normalized: String
        if cleaned.hasPrefix("sha256:") || cleaned.hasPrefix("sha256=") {
            normalized = String(cleaned.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        } else if cleaned.hasPrefix("md5:") || cleaned.hasPrefix("md5=") {
            normalized = String(cleaned.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        } else {
            normalized = cleaned
        }

        if normalized == sha256 {
            return .sha256
        } else if normalized == md5 {
            return .md5
        } else {
            return .none
        }
    }
}

//
//  WriteProgress.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation

/// Progress status and metrics for an in-flight raw block write or verification operation.
public enum WriteState: Sendable, Equatable {
    case idle
    case unmounting(targetDrive: String)
    case writing(
        bytesWritten: Int64,
        totalBytes: Int64,
        fraction: Double,
        speedBytesPerSecond: Double,
        etaSeconds: TimeInterval?
    )
    case verifying(
        bytesVerified: Int64,
        totalBytes: Int64,
        fraction: Double,
        speedBytesPerSecond: Double,
        etaSeconds: TimeInterval?
    )
    case completed(totalBytes: Int64, totalDuration: TimeInterval)
    case failed(message: String)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    public var progressFraction: Double {
        switch self {
        case .idle:
            return 0.0
        case .unmounting:
            return 0.02
        case .writing(_, _, let fraction, _, _):
            // Writing represents 0% - 80% of the overall workflow
            return fraction * 0.8
        case .verifying(_, _, let fraction, _, _):
            // Verifying represents 80% - 100% of the overall workflow
            return 0.8 + (fraction * 0.2)
        case .completed:
            return 1.0
        case .failed, .cancelled:
            return 0.0
        }
    }
}

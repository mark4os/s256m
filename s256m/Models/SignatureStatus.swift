//
//  SignatureStatus.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation

/// Represents the digital signature and authenticity state of a disk image or installer.
nonisolated public enum SignatureStatus: Sendable, Equatable {
    /// No file has been selected yet.
    case none

    /// Authenticity evaluation is currently in progress.
    case checking

    /// The file possesses a cryptographically valid digital signature.
    case verified(publisher: String, teamID: String? = nil, isNotarized: Bool = false)

    /// The file does not contain a digital signature (typical for generic raw ISO/IMG files).
    case unsigned

    /// The file contains an invalid, corrupt, or revoked digital signature.
    case invalid(reason: String)

    /// Whether this status represents a verified publisher.
    public var isVerified: Bool {
        if case .verified = self { return true }
        return false
    }

    /// Extracted publisher name, if verified.
    public var publisher: String? {
        if case .verified(let pub, _, _) = self { return pub }
        return nil
    }

    /// Extracted Apple Developer Team ID, if available.
    public var teamID: String? {
        if case .verified(_, let team, _) = self { return team }
        return nil
    }

    /// Whether an Apple Notarization ticket was validated.
    public var isNotarized: Bool {
        if case .verified(_, _, let notarized) = self { return notarized }
        return false
    }

    /// Human-readable title suitable for UI badges.
    public var displayTitle: String {
        switch self {
        case .none:
            return "Awaiting File"
        case .checking:
            return "Evaluating Signature & Notarization..."
        case .verified(let publisher, _, _):
            return publisher
        case .unsigned:
            return "Unsigned Media"
        case .invalid(let reason):
            return "Invalid Signature: \(reason)"
        }
    }
}

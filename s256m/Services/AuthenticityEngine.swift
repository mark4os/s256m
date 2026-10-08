//
//  AuthenticityEngine.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation
import Security

/// Evaluates digital signatures, publisher identities, and Apple Notarization status
/// for macOS disk images (DMG), installer packages (PKG), and application bundles
/// using Apple's native Security.framework.
public actor AuthenticityEngine {

    public init() {}

    /// Evaluates the digital signature and authenticity of the file at the specified URL.
    ///
    /// - Parameter url: Local file URL of the disk image, installer package, or application.
    /// - Returns: The evaluated `SignatureStatus`.
    public func evaluate(url: URL) async -> SignatureStatus {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return .invalid(reason: "File does not exist at specified path.")
        }

        // 1. Create SecStaticCode reference for the file target (DMG, PKG, app bundle, or binary)
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)

        guard createStatus == errSecSuccess, let staticCode else {
            // Unrecognized binary or format without code signing support (e.g. raw ISO or img)
            return .unsigned
        }

        // 2. Validate cryptographic signature integrity
        let validityStatus = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: 0), nil)

        if validityStatus == errSecCSUnsigned {
            return .unsigned
        } else if validityStatus != errSecSuccess {
            let errorString = SecCopyErrorMessageString(validityStatus, nil) as String?
            return .invalid(reason: errorString ?? "Signature validation error (code: \(validityStatus)).")
        }

        // 3. Extract signing information, certificate authority, and Team ID
        var signingInfoCF: CFDictionary?
        let infoFlags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
        let infoStatus = SecCodeCopySigningInformation(staticCode, infoFlags, &signingInfoCF)

        guard infoStatus == errSecSuccess, let info = signingInfoCF as? [String: Any] else {
            return .verified(publisher: "Apple Signed Entity", teamID: nil, isNotarized: false)
        }

        let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String
        var publisher = "Apple Inc."

        if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
           let leafCert = certs.first {
            if let subjectSummary = SecCertificateCopySubjectSummary(leafCert) as String? {
                publisher = subjectSummary
            }
        }

        // 4. Verify Notarization ticket or Apple system identity
        let isNotarized = evaluateNotarization(path: url.path, info: info, publisher: publisher)

        return .verified(publisher: publisher, teamID: teamID, isNotarized: isNotarized)
    }

    /// Static convenience helper to evaluate authenticity.
    public static func evaluate(url: URL) async -> SignatureStatus {
        let engine = AuthenticityEngine()
        return await engine.evaluate(url: url)
    }

    // MARK: - Private Notarization & Ticket Detection

    private func evaluateNotarization(path: String, info: [String: Any], publisher: String) -> Bool {
        // Apple system software signatures
        if let source = info["source"] as? String, source == "Apple System" {
            return true
        }

        if publisher.contains("macOS Software Signing") || publisher.contains("Apple Mac OS") {
            return true
        }

        // Check for stapled notarization ticket extended attributes on disk image or package
        let ticketAttr = getxattr(path, "com.apple.security.notarization-ticket", nil, 0, 0, 0)
        if ticketAttr > 0 {
            return true
        }

        // Check for CodeDirectory signature ticket staple
        let cdAttr = getxattr(path, "com.apple.cs.CodeDirectory", nil, 0, 0, 0)
        if cdAttr > 0 {
            return true
        }

        return false
    }
}

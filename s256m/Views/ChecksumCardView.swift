//
//  ChecksumCardView.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import SwiftUI
import AppKit

/// Card displaying the 3-tier verification architecture:
/// 1. Level 1: SHA-256 (Bit-level cryptographic integrity & official hash matching).
/// 2. Level 2: MD5 (Legacy hardware and firmware compatibility).
/// 3. Level 3: Digital Signature & Authenticity (Apple code signature, publisher identity, notarization).
struct ChecksumCardView: View {
    @Bindable var appState: AppState
    @State private var copiedSHA256: Bool = false
    @State private var copiedMD5: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerView

            // Tier 3: Digital Signature & Authenticity
            AuthenticityBadgeView(status: appState.signatureStatus)

            if appState.isCalculatingChecksum {
                calculatingProgressView
            } else if let result = appState.checksumResult {
                completedHashesView(result: result)
                Divider()
                verificationInputView(result: result)
            } else {
                Text("Select or drop a disk image above to calculate checksums.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Label("Verification Architecture", systemImage: "shield.checkered")
                .font(.headline)

            Spacer()

            if let result = appState.checksumResult, !appState.isCalculatingChecksum {
                HStack(spacing: 8) {
                    Text(result.formattedSpeed)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text(String(format: "%.2fs", result.duration))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Calculation Progress

    private var calculatingProgressView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Streaming image blocks...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(formattedSpeed(appState.checksumSpeedBytesPerSecond))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Text(String(format: "%.0f%%", appState.checksumProgressFraction * 100))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: appState.checksumProgressFraction, total: 1.0)
                .progressViewStyle(.linear)

            HStack {
                Spacer()
                Button("Cancel Hashing") {
                    appState.cancelChecksumCalculation()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Completed Hashes (Tier 1 & Tier 2)

    private func completedHashesView(result: ChecksumResult) -> some View {
        VStack(spacing: 10) {
            hashRow(
                tierLabel: "Tier 1: SHA-256 (Bit-level Integrity)",
                hash: result.sha256,
                isCopied: copiedSHA256,
                isMatch: appState.hashMatch == .sha256
            ) {
                copyToClipboard(text: result.sha256)
                withAnimation { copiedSHA256 = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copiedSHA256 = false }
                }
            }

            hashRow(
                tierLabel: "Tier 2: MD5 (Legacy Hardware Compatibility)",
                hash: result.md5,
                isCopied: copiedMD5,
                isMatch: appState.hashMatch == .md5
            ) {
                copyToClipboard(text: result.md5)
                withAnimation { copiedMD5 = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copiedMD5 = false }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func hashRow(
        tierLabel: String,
        hash: String,
        isCopied: Bool,
        isMatch: Bool,
        copyAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tierLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isMatch ? Color.green : Color.secondary)

                if isMatch {
                    Text("✓ VERIFIED MATCH")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                Button(action: copyAction) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.caption)
                    }
                    .foregroundStyle(isCopied ? Color.green : Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            Text(hash)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isMatch ? Color.green.opacity(0.08) : Color(nsColor: .textBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isMatch ? Color.green.opacity(0.4) : Color.secondary.opacity(0.15), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Verification Input

    private func verificationInputView(result: ChecksumResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Verify Against Official Hash")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                matchStatusBadge
            }

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("Paste expected SHA-256 or MD5 hash here...", text: $appState.candidateHash)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity)

                if !appState.candidateHash.isEmpty {
                    Button(action: { appState.candidateHash = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderForMatchStatus, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var matchStatusBadge: some View {
        let trimmed = appState.candidateHash.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            EmptyView()
        } else {
            switch appState.hashMatch {
            case .sha256:
                Label("Matches SHA-256 (Tier 1)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            case .md5:
                Label("Matches MD5 (Tier 2)", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            case .none:
                Label("Checksum Mismatch", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
    }

    private var borderForMatchStatus: Color {
        let trimmed = appState.candidateHash.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return Color.secondary.opacity(0.2)
        }
        switch appState.hashMatch {
        case .sha256, .md5:
            return Color.green
        case .none:
            return Color.red
        }
    }

    // MARK: - Helpers

    private func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func formattedSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000_000 {
            return String(format: "%.2f GB/s", bytesPerSec / 1_000_000_000)
        } else if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSec / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }
}

//
//  AuthenticityBadgeView.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import SwiftUI

/// Dedicated view displaying Tier 3: Digital Signature & Authenticity status.
struct AuthenticityBadgeView: View {
    let status: SignatureStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Tier 3: Digital Signature & Authenticity")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(headerColor)

                Spacer()

                tierIndicatorChip
            }

            contentBody
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    // MARK: - Header & Badge Components

    @ViewBuilder
    private var tierIndicatorChip: some View {
        switch status {
        case .none:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Verifying...")
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
        case .verified:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                Text("Signed")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.15))
            .clipShape(Capsule())
        case .unsigned:
            HStack(spacing: 4) {
                Image(systemName: "shield.slash")
                Text("Unsigned")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
        case .invalid:
            HStack(spacing: 4) {
                Image(systemName: "xmark.seal.fill")
                Text("Invalid")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    // MARK: - Main Body

    @ViewBuilder
    private var contentBody: some View {
        switch status {
        case .none:
            Text("Select an image to inspect developer code signature.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Inspecting static code signature and notarization tickets...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .verified(let publisher, let teamID, let isNotarized):
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(publisher)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)

                        if let teamID, !teamID.isEmpty {
                            Text("Team ID: \(teamID)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if isNotarized {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                                .font(.caption)
                            Text("Apple Notarized")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }
            }

        case .unsigned:
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unsigned Media")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("This disk image does not contain an Apple Developer digital signature (common for raw Linux/firmware ISOs).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .invalid(let reason):
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Digital Signature Corrupt or Unrecognized")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)

                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Styling Helpers

    private var headerColor: Color {
        switch status {
        case .verified:
            return .green
        case .invalid:
            return .red
        default:
            return .secondary
        }
    }

    private var cardBackgroundColor: Color {
        switch status {
        case .verified:
            return Color.green.opacity(0.06)
        case .invalid:
            return Color.red.opacity(0.06)
        default:
            return Color(nsColor: .controlBackgroundColor).opacity(0.6)
        }
    }

    private var cardBorderColor: Color {
        switch status {
        case .verified:
            return Color.green.opacity(0.3)
        case .invalid:
            return Color.red.opacity(0.4)
        default:
            return Color.secondary.opacity(0.15)
        }
    }
}

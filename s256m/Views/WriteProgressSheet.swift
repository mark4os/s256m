//
//  WriteProgressSheet.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import SwiftUI

/// Modal confirmation sheet and real-time write/verify progress monitor.
struct WriteProgressSheet: View {
    @Bindable var appState: AppState
    @State private var hasConfirmedBurn: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            if !hasConfirmedBurn && appState.writeState == .idle {
                confirmationView
            } else {
                progressView
            }
        }
        .padding(28)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Confirmation View

    private var confirmationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            VStack(spacing: 6) {
                Text("Confirm Drive Overwrite")
                    .font(.title2.weight(.bold))

                Text("All existing data and partitions on this drive will be permanently erased. This operation cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let drive = appState.selectedDrive {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Target Drive:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(drive.displayName)
                            .font(.caption.weight(.bold))
                    }

                    if let imageURL = appState.selectedImageURL {
                        HStack {
                            Text("Source Image:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(imageURL.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }

                    HStack {
                        Text("Verification:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(appState.shouldVerifyAfterWrite ? "Read-back SHA-256 verification enabled" : "Disabled")
                            .font(.caption)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    appState.dismissWriteSheet()
                }
                .keyboardShortcut(.cancelAction)

                Button("Erase & Flash") {
                    hasConfirmedBurn = true
                    appState.startWriteOperation()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - In-Flight Progress View

    private var progressView: some View {
        VStack(spacing: 20) {
            statusIcon

            VStack(spacing: 6) {
                Text(phaseTitle)
                    .font(.title3.weight(.bold))

                Text(phaseSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ProgressView(value: appState.writeState.progressFraction, total: 1.0)
                .progressViewStyle(.linear)

            HStack {
                Text(String(format: "%.0f%%", appState.writeState.progressFraction * 100))
                    .font(.caption.monospacedDigit().weight(.semibold))

                Spacer()

                if let speedText {
                    Text(speedText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let etaText {
                    Text("• \(etaText)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                if appState.writeState.isTerminal {
                    Button("Done") {
                        appState.dismissWriteSheet()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel Operation") {
                        appState.cancelWriteOperation()
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Dynamic State Descriptions

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.writeState {
        case .idle, .unmounting:
            ProgressView()
                .controlSize(.large)
        case .writing:
            Image(systemName: "bolt.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
        case .verifying:
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
        }
    }

    private var phaseTitle: String {
        switch appState.writeState {
        case .idle:
            return "Preparing..."
        case .unmounting(let bsd):
            return "Unmounting \(bsd)..."
        case .writing:
            return "Flashing Image..."
        case .verifying:
            return "Verifying Integrity..."
        case .completed:
            return "Flashing Complete!"
        case .failed:
            return "Flashing Failed"
        case .cancelled:
            return "Operation Cancelled"
        }
    }

    private var phaseSubtitle: String {
        switch appState.writeState {
        case .idle:
            return "Initializing device stream."
        case .unmounting:
            return "Safely unmounting active partitions so raw blocks can be written."
        case .writing(let written, let total, _, _, _):
            let wStr = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
            let tStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "Direct streaming raw blocks: \(wStr) of \(tStr)"
        case .verifying(let verified, let total, _, _, _):
            let vStr = ByteCountFormatter.string(fromByteCount: verified, countStyle: .file)
            let tStr = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            return "Reading back physical blocks: \(vStr) of \(tStr)"
        case .completed(let bytes, let duration):
            let bStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return "\(bStr) written and verified in \(String(format: "%.1f", duration)) seconds. Media has been safely ejected."
        case .failed(let message):
            return message
        case .cancelled:
            return "The writing task was cancelled before completion."
        }
    }

    private var speedText: String? {
        switch appState.writeState {
        case .writing(_, _, _, let speed, _),
             .verifying(_, _, _, let speed, _):
            return formattedSpeed(speed)
        default:
            return nil
        }
    }

    private var etaText: String? {
        switch appState.writeState {
        case .writing(_, _, _, _, let eta),
             .verifying(_, _, _, _, let eta):
            if let eta, eta > 0 {
                if eta < 60 {
                    return String(format: "ETA: %.0fs", eta)
                } else {
                    return String(format: "ETA: %.0fm %.0fs", eta / 60, eta.truncatingRemainder(dividingBy: 60))
                }
            }
            return nil
        default:
            return nil
        }
    }

    private func formattedSpeed(_ speed: Double) -> String {
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
}

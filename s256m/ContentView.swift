//
//  ContentView.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                appHeader
                    .frame(maxWidth: .infinity)

                // Step 1: Disk Image Drop & Selection
                VStack(alignment: .leading, spacing: 8) {
                    stepLabel(number: 1, title: "Select Disk Image (ISO / DMG / RAW)")
                    DropZoneView(appState: appState)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Step 2: Checksum & Integrity Verification
                VStack(alignment: .leading, spacing: 8) {
                    stepLabel(number: 2, title: "Cryptographic Verification")
                    ChecksumCardView(appState: appState)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Step 3: Safe Removable Drive Target
                VStack(alignment: .leading, spacing: 8) {
                    stepLabel(number: 3, title: "Target Drive Selection")
                    DriveSelectorView(appState: appState)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 540, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $appState.isWriteSheetPresented) {
            WriteProgressSheet(appState: appState)
        }
    }

    // MARK: - App Header

    private var appHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)

                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Smart Checksum & Disk Helper")
                        .font(.title2.weight(.bold))

                    Text("v1.0")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text("Fast single-pass CryptoKit integrity verification and guarded raw block flashing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            safetyStatusBadge
        }
        .padding(.bottom, 6)
    }

    private var safetyStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)

            Text("System Drives Protected")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            Capsule()
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func stepLabel(number: Int, title: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    ContentView()
}

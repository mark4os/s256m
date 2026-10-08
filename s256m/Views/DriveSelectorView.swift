//
//  DriveSelectorView.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import SwiftUI

/// Drive selection view filtering for safe, external removable media and presenting
/// device specifications, capacity, and write triggers.
struct DriveSelectorView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerView

            if appState.diskMonitor.availableDrives.isEmpty {
                noDrivesConnectedView
            } else {
                drivePickerView
                if let drive = appState.selectedDrive {
                    driveDetailsView(drive: drive)
                }
            }

            Divider()

            footerActionView
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
            Label("Target Removable Drive", systemImage: "externaldrive.badge.wifi")
                .font(.headline)

            Spacer()

            Button(action: {
                withAnimation {
                    appState.diskMonitor.refresh()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Scan for newly connected drives")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Drive Picker

    private var drivePickerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select Destination")
                .font(.subheadline.weight(.semibold))

            Picker("Target Drive", selection: $appState.selectedDrive) {
                Text("Select a drive...").tag(TargetDrive?.none)
                ForEach(appState.diskMonitor.availableDrives) { drive in
                    Text(drive.displayName).tag(TargetDrive?.some(drive))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Drive Details

    private func driveDetailsView(drive: TargetDrive) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                detailBadge(title: "DEVICE", value: drive.bsdName)
                detailBadge(title: "CAPACITY", value: drive.formattedCapacity)
                detailBadge(title: "PROTOCOL", value: drive.protocolName ?? "External")
            }

            if !drive.volumeNames.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Text("Existing Volumes:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(drive.volumeNames.joined(separator: ", "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            }

            // Capacity validation warning
            if appState.imageByteCount > 0 && drive.totalBytes < appState.imageByteCount {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)

                    Text("Drive capacity (\(drive.formattedCapacity)) is smaller than image size (\(appState.formattedImageSize)).")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.4))
        )
    }

    private func detailBadge(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - No Drives Connected

    private var noDrivesConnectedView: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("No Removable Drives Detected")
                    .font(.subheadline.weight(.semibold))

                Text("Connect a USB flash drive or SD card. Internal and system drives are strictly excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer & Action

    private var footerActionView: some View {
        HStack {
            Toggle("Verify written data", isOn: $appState.shouldVerifyAfterWrite)
                .font(.subheadline)
                .toggleStyle(.checkbox)

            Spacer()

            Button(action: {
                appState.isWriteSheetPresented = true
            }) {
                Label("Flash to Drive...", systemImage: "bolt.fill")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.canStartWrite)
        }
        .frame(maxWidth: .infinity)
    }
}

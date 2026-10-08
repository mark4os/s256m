//
//  DropZoneView.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Drag-and-drop file target and open-panel file picker for ISO, DMG, and disk images.
struct DropZoneView: View {
    @Bindable var appState: AppState
    @State private var isTargeted: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            if let imageURL = appState.selectedImageURL {
                selectedFileCard(imageURL: imageURL)
            } else {
                emptyDropTarget
            }
        }
        .frame(maxWidth: .infinity)
        .dropDestination(for: URL.self) { items, _ in
            guard let firstURL = items.first else { return false }
            appState.selectImage(url: firstURL)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                isTargeted = targeted
            }
        }
    }

    // MARK: - Subviews

    private var emptyDropTarget: some View {
        Button(action: openFileDialog) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isTargeted ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                        .frame(width: 56, height: 56)

                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.doc")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
                }

                VStack(spacing: 4) {
                    Text("Drop ISO, DMG, or Disk Image here")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("or click to browse your files")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    badge(label: ".ISO")
                    badge(label: ".DMG")
                    badge(label: ".IMG")
                    badge(label: ".RAW")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [6, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    )
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func selectedFileCard(imageURL: URL) -> some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: imageURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(imageURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(appState.formattedImageSize)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(imageURL.pathExtension.uppercased())
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }

            Spacer()

            Button(action: {
                withAnimation {
                    appState.clearSelectedImage()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove selected image")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func badge(label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType.diskImage,
            UTType.rawImage,
            UTType(filenameExtension: "iso") ?? .data,
            UTType(filenameExtension: "img") ?? .data,
            UTType(filenameExtension: "bin") ?? .data
        ]

        if panel.runModal() == .OK, let url = panel.url {
            appState.selectImage(url: url)
        }
    }
}

//
//  TargetDrive.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation

/// Represents a validated, external removable storage device that is safe to target.
nonisolated public struct TargetDrive: Identifiable, Hashable, Sendable {
    /// BSD disk name, e.g. "disk4".
    public let bsdName: String

    /// Friendly media name, e.g. "SanDisk Ultra USB 3.0 Media".
    public let mediaName: String?

    /// Hardware vendor string, e.g. "SanDisk".
    public let vendor: String?

    /// Hardware model string, e.g. "Ultra USB 3.0".
    public let model: String?

    /// Connection protocol, e.g. "USB", "Secure Digital", "Thunderbolt".
    public let protocolName: String?

    /// Total storage capacity in bytes.
    public let totalBytes: Int64

    /// Whether macOS reports the device as removable.
    public let isRemovable: Bool

    /// Whether macOS reports the device as ejectable.
    public let isEjectable: Bool

    /// Whether macOS reports the device as internal (must be false).
    public let isInternal: Bool

    /// Whether the medium is writable.
    public let isWritable: Bool

    /// Volume names of currently mounted partitions on this physical disk.
    public let volumeNames: [String]

    public var id: String { bsdName }

    public init(
        bsdName: String,
        mediaName: String? = nil,
        vendor: String? = nil,
        model: String? = nil,
        protocolName: String? = nil,
        totalBytes: Int64,
        isRemovable: Bool = true,
        isEjectable: Bool = true,
        isInternal: Bool = false,
        isWritable: Bool = true,
        volumeNames: [String] = []
    ) {
        self.bsdName = bsdName
        self.mediaName = mediaName
        self.vendor = vendor
        self.model = model
        self.protocolName = protocolName
        self.totalBytes = totalBytes
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isInternal = isInternal
        self.isWritable = isWritable
        self.volumeNames = volumeNames
    }

    /// Path to raw disk character device, e.g. "/dev/rdisk4" (for fast raw block writes).
    public var rawDevicePath: String {
        "/dev/r\(bsdName)"
    }

    /// Path to block disk device, e.g. "/dev/disk4".
    public var blockDevicePath: String {
        "/dev/\(bsdName)"
    }

    /// Human-friendly display title combining vendor/model and BSD identifier.
    public var displayName: String {
        var components: [String] = []

        if let vendor = vendor, !vendor.isEmpty {
            components.append(vendor)
        }
        if let model = model, !model.isEmpty, model != vendor {
            components.append(model)
        } else if let mediaName = mediaName, !mediaName.isEmpty, components.isEmpty {
            components.append(mediaName)
        }

        let name = components.isEmpty ? "Removable Drive" : components.joined(separator: " ")
        let volumes = volumeNames.isEmpty ? "" : " (\(volumeNames.joined(separator: ", ")))"
        return "\(name) - \(formattedCapacity) [\(bsdName)]\(volumes)"
    }

    /// Formatted total storage size in decimal or binary units.
    public var formattedCapacity: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

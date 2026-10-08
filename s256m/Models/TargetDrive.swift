//
//  TargetDrive.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation

/// Represents a validated, safe external or removable storage device candidate.
public struct TargetDrive: Identifiable, Sendable, Equatable, Hashable {
    /// Unique identifier matching the BSD whole-disk name (e.g., "disk4").
    public var id: String { bsdName }

    /// Whole disk BSD name (e.g., "disk4").
    public let bsdName: String

    /// POSIX path to the character device for direct raw block I/O (e.g., "/dev/rdisk4").
    public var rawDevicePath: String {
        "/dev/r\(bsdName)"
    }

    /// POSIX path to the block device (e.g., "/dev/disk4").
    public var blockDevicePath: String {
        "/dev/\(bsdName)"
    }

    /// Physical media or manufacturer name (e.g. "SanDisk Ultra Fit", "Generic Flash Disk").
    public let mediaName: String

    /// Optional hardware vendor string.
    public let vendor: String?

    /// Optional hardware model string.
    public let model: String?

    /// Interconnect protocol (e.g., "USB", "Secure Digital").
    public let protocolName: String?

    /// Total capacity in bytes.
    public let totalBytes: Int64

    /// Removable media flag according to DiskArbitration/IOKit.
    public let isRemovable: Bool

    /// Ejectable flag according to DiskArbitration/IOKit.
    public let isEjectable: Bool

    /// Hardware internal flag according to DiskArbitration.
    public let isInternal: Bool

    /// Media writable status.
    public let isWritable: Bool

    /// Volume/partition labels currently mounted from this disk.
    public let volumeNames: [String]

    public init(
        bsdName: String,
        mediaName: String,
        vendor: String? = nil,
        model: String? = nil,
        protocolName: String? = nil,
        totalBytes: Int64,
        isRemovable: Bool,
        isEjectable: Bool,
        isInternal: Bool,
        isWritable: Bool,
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

    /// Human-readable capacity formatted in binary units (e.g. 15.6 GB).
    public var formattedCapacity: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// Clean display title for UI pickers.
    public var displayName: String {
        let name: String
        if !mediaName.isEmpty && mediaName != bsdName {
            name = mediaName
        } else if let model, !model.isEmpty {
            name = model
        } else {
            name = "External Drive"
        }

        let volumesStr = volumeNames.isEmpty ? "" : " [\(volumeNames.joined(separator: ", "))]"
        return "\(name) (\(formattedCapacity)) — \(bsdName)\(volumesStr)"
    }
}

//
//  DiskSafetyValidator.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation
@preconcurrency import DiskArbitration

/// Validates storage devices to ensure that internal, system, and virtual drives
/// can never be targeted for destructive write operations.
nonisolated public struct DiskSafetyValidator: Sendable {

    /// Protocols that are explicitly blocked from being targeted.
    public static let blockedProtocols: Set<String> = [
        "Apple Fabric",
        "PCI-Express",
        "Virtual Interface",
        "Disk Image",
        "RAM Disk"
    ]

    /// Whitelisted protocols for removable/external storage.
    public static let allowedProtocols: Set<String> = [
        "USB",
        "Secure Digital",
        "FireWire",
        "Thunderbolt"
    ]

    /// Extracts the whole-disk BSD name (e.g., "disk4") from a partition BSD name or device path
    /// (e.g. "/dev/disk4s1", "disk4s1s2", "/dev/disk12").
    public static func extractWholeDiskBSDName(from devicePathOrBSDName: String) -> String {
        var str = devicePathOrBSDName.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("/dev/r") {
            str = String(str.dropFirst(6))
        } else if str.hasPrefix("/dev/") {
            str = String(str.dropFirst(5))
        }

        // Match "disk" followed by digits (e.g. disk0, disk12, disk4s1 -> disk4)
        if let match = str.range(of: "^disk\\d+", options: .regularExpression) {
            return String(str[match])
        }

        return str
    }

    /// Queries currently mounted filesystems to identify all physical whole disks
    /// hosting critical macOS system partitions (e.g. root "/", "/System/Volumes/*", Recovery).
    public static func querySystemDisks() -> Set<String> {
        var systemDisks = Set<String>()

        // Check root mount "/"
        var rootStat = statfs()
        if statfs("/", &rootStat) == 0 {
            let mntFrom = withUnsafePointer(to: &rootStat.f_mntfromname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            let whole = extractWholeDiskBSDName(from: mntFrom)
            if !whole.isEmpty {
                systemDisks.insert(whole)
            }
        }

        // Check all mounted volume URLs
        if let mountedURLs = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsInternalKey],
            options: []
        ) {
            for url in mountedURLs {
                var stat = statfs()
                if statfs(url.path, &stat) == 0 {
                    let mntFrom = withUnsafePointer(to: &stat.f_mntfromname) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                            String(cString: $0)
                        }
                    }
                    let whole = extractWholeDiskBSDName(from: mntFrom)
                    if !whole.isEmpty {
                        // Mark internal and system volumes as protected
                        let path = url.path
                        if path == "/" ||
                            path.hasPrefix("/System") ||
                            path.hasPrefix("/private/var") ||
                            path.contains("Recovery") {
                            systemDisks.insert(whole)
                        }
                    }
                }
            }
        }

        return systemDisks
    }

    /// Evaluates a disk description dictionary from DiskArbitration against all safety rules.
    ///
    /// - Parameters:
    ///   - description: The dictionary returned by `DADiskCopyDescription`.
    ///   - systemDiskBlacklist: Whole-disk BSD names containing system or root mounts.
    /// - Returns: A tuple `(isSafe, rejectionReason)` indicating eligibility.
    public static func evaluateDisk(
        description: [String: Any],
        systemDiskBlacklist: Set<String>
    ) -> (isSafe: Bool, rejectionReason: String?) {
        let bsdName = description[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? ""
        let wholeDiskName = extractWholeDiskBSDName(from: bsdName)

        // 1. Must be a whole disk (not a partition slice)
        let isWhole = description[kDADiskDescriptionMediaWholeKey as String] as? Bool ?? false
        guard isWhole else {
            return (false, "Device '\(bsdName)' is a partition, not a whole physical disk.")
        }

        // 2. Must not be internal hardware
        let isInternal = description[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? false
        guard !isInternal else {
            return (false, "Device '\(bsdName)' is an internal system disk.")
        }

        // 3. Must not be part of the system disk blacklist
        guard !systemDiskBlacklist.contains(wholeDiskName) else {
            return (false, "Device '\(bsdName)' hosts macOS system or boot volumes.")
        }

        // 4. Must be writable
        let isWritable = description[kDADiskDescriptionMediaWritableKey as String] as? Bool ?? false
        guard isWritable else {
            return (false, "Device '\(bsdName)' is read-only or write-protected.")
        }

        // 5. Must have positive capacity
        let size = (description[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            return (false, "Device '\(bsdName)' reports zero capacity.")
        }

        // 6. Protocol verification
        let proto = description[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
        if blockedProtocols.contains(proto) {
            return (false, "Device '\(bsdName)' uses unsupported or virtual protocol '\(proto)'.")
        }

        // 7. Must be removable or ejectable
        let isRemovable = description[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
        let isEjectable = description[kDADiskDescriptionMediaEjectableKey as String] as? Bool ?? false
        guard isRemovable || isEjectable || allowedProtocols.contains(proto) else {
            return (false, "Device '\(bsdName)' is neither removable nor ejectable.")
        }

        return (true, nil)
    }

    /// Converts a valid disk description dictionary into a `TargetDrive` model.
    public static func parseTargetDrive(
        description: [String: Any],
        volumeNames: [String] = []
    ) -> TargetDrive? {
        guard let bsdName = description[kDADiskDescriptionMediaBSDNameKey as String] as? String else {
            return nil
        }

        let mediaName = description[kDADiskDescriptionMediaNameKey as String] as? String ?? bsdName
        let vendor = description[kDADiskDescriptionDeviceVendorKey as String] as? String
        let model = description[kDADiskDescriptionDeviceModelKey as String] as? String
        let proto = description[kDADiskDescriptionDeviceProtocolKey as String] as? String
        let size = (description[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.int64Value ?? 0
        let isRemovable = description[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
        let isEjectable = description[kDADiskDescriptionMediaEjectableKey as String] as? Bool ?? false
        let isInternal = description[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? false
        let isWritable = description[kDADiskDescriptionMediaWritableKey as String] as? Bool ?? false

        return TargetDrive(
            bsdName: bsdName,
            mediaName: mediaName,
            vendor: vendor?.trimmingCharacters(in: .whitespaces),
            model: model?.trimmingCharacters(in: .whitespaces),
            protocolName: proto,
            totalBytes: size,
            isRemovable: isRemovable,
            isEjectable: isEjectable,
            isInternal: isInternal,
            isWritable: isWritable,
            volumeNames: volumeNames
        )
    }
}

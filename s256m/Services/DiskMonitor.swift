//
//  DiskMonitor.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import Foundation
@preconcurrency import DiskArbitration
import Observation

/// Thread-safe coordinator bridging DiskArbitration C callbacks to DiskMonitor with weak ownership.
nonisolated private final class MonitorCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private weak var _monitor: DiskMonitor?
    private var _session: DASession?

    var monitor: DiskMonitor? {
        lock.withLock { _monitor }
    }

    func setSession(_ session: DASession?, monitor: DiskMonitor?) {
        lock.withLock {
            self._session = session
            self._monitor = monitor
        }
    }

    func invalidate() {
        lock.withLock {
            if let session = _session {
                DASessionSetDispatchQueue(session, nil)
                self._session = nil
            }
            _monitor = nil
        }
    }
}

/// Observes disk attachment and detachment events in real-time using Apple's DiskArbitration framework,
/// presenting an automatically updated list of safe, removable target drives.
@Observable
@MainActor
public final class DiskMonitor {

    /// The list of currently attached external/removable drives that are safe to target.
    public private(set) var availableDrives: [TargetDrive] = []

    /// Current set of whole-disk BSD names protected by system and boot volume rules.
    public private(set) var systemDisks: Set<String> = []

    /// Whether real-time monitoring is currently running.
    public private(set) var isMonitoring: Bool = false

    /// Background queue for DiskArbitration event handling.
    nonisolated private let monitorQueue = DispatchQueue(label: "com.s256m.diskmonitor", qos: .userInitiated)

    /// Bridge coordinator ensuring C callbacks never dereference a deallocated monitor.
    nonisolated private let coordinator = MonitorCoordinator()

    /// In-memory cache of disk descriptions keyed by BSD name.
    private var diskDescriptions: [String: [String: Any]] = [:]

    /// Mapping from whole-disk BSD name to mounted partition volume names.
    private var wholeDiskVolumes: [String: Set<String>] = [:]

    public init() {}

    deinit {
        coordinator.invalidate()
    }

    /// Starts real-time observation of storage device changes.
    public func startMonitoring() {
        guard !isMonitoring else { return }

        // Refresh system disk blacklist
        systemDisks = DiskSafetyValidator.querySystemDisks()

        guard let newSession = DASessionCreate(kCFAllocatorDefault) else {
            return
        }

        DASessionSetDispatchQueue(newSession, monitorQueue)
        coordinator.setSession(newSession, monitor: self)

        let context = Unmanaged.passUnretained(coordinator).toOpaque()

        DARegisterDiskAppearedCallback(newSession, nil, { disk, context in
            guard let context else { return }
            let coord = Unmanaged<MonitorCoordinator>.fromOpaque(context).takeUnretainedValue()
            let description = DADiskCopyDescription(disk) as? [String: Any]
            let wholeDisk = DADiskCopyWholeDisk(disk)
            let wholeBsd = wholeDisk.flatMap { DADiskGetBSDName($0) }.map { String(cString: $0) }
            Task { @MainActor in
                coord.monitor?.handleDiskAppeared(description: description, wholeBsdName: wholeBsd)
            }
        }, context)

        DARegisterDiskDisappearedCallback(newSession, nil, { disk, context in
            guard let context else { return }
            let coord = Unmanaged<MonitorCoordinator>.fromOpaque(context).takeUnretainedValue()
            guard let bsdName = DADiskGetBSDName(disk) else { return }
            let name = String(cString: bsdName)
            Task { @MainActor in
                coord.monitor?.handleDiskDisappeared(bsdName: name)
            }
        }, context)

        DARegisterDiskDescriptionChangedCallback(newSession, nil, nil, { disk, _, context in
            guard let context else { return }
            let coord = Unmanaged<MonitorCoordinator>.fromOpaque(context).takeUnretainedValue()
            let description = DADiskCopyDescription(disk) as? [String: Any]
            let wholeDisk = DADiskCopyWholeDisk(disk)
            let wholeBsd = wholeDisk.flatMap { DADiskGetBSDName($0) }.map { String(cString: $0) }
            Task { @MainActor in
                coord.monitor?.handleDiskAppeared(description: description, wholeBsdName: wholeBsd)
            }
        }, context)

        isMonitoring = true
    }

    /// Stops observation and releases the DiskArbitration session.
    public func stopMonitoring() {
        guard isMonitoring else { return }

        coordinator.invalidate()
        isMonitoring = false
    }

    /// Manually triggers a re-query of system disks and rebuilds the drive list.
    public func refresh() {
        systemDisks = DiskSafetyValidator.querySystemDisks()
        recomputeAvailableDrives()
    }

    // MARK: - Internal MainActor Event Handlers

    @MainActor
    private func handleDiskAppeared(description: [String: Any]?, wholeBsdName: String?) {
        guard let description,
              let bsdName = description[kDADiskDescriptionMediaBSDNameKey as String] as? String else { return }

        diskDescriptions[bsdName] = description

        let isWhole = description[kDADiskDescriptionMediaWholeKey as String] as? Bool ?? false
        if !isWhole {
            if let parentBsd = wholeBsdName,
               let volName = description[kDADiskDescriptionVolumeNameKey as String] as? String,
               !volName.isEmpty {
                var existing = wholeDiskVolumes[parentBsd] ?? []
                existing.insert(volName)
                wholeDiskVolumes[parentBsd] = existing
            }
        } else if let volName = description[kDADiskDescriptionVolumeNameKey as String] as? String,
                  !volName.isEmpty {
            var existing = wholeDiskVolumes[bsdName] ?? []
            existing.insert(volName)
            wholeDiskVolumes[bsdName] = existing
        }

        recomputeAvailableDrives()
    }

    @MainActor
    private func handleDiskDisappeared(bsdName: String) {
        diskDescriptions.removeValue(forKey: bsdName)
        wholeDiskVolumes.removeValue(forKey: bsdName)
        recomputeAvailableDrives()
    }

    // MARK: - Drive List Recomputation

    @MainActor
    private func recomputeAvailableDrives() {
        var result: [TargetDrive] = []

        for (_, desc) in diskDescriptions {
            let (isSafe, _) = DiskSafetyValidator.evaluateDisk(
                description: desc,
                systemDiskBlacklist: systemDisks
            )

            guard isSafe else { continue }

            let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? ""
            let volumes = Array(wholeDiskVolumes[bsdName] ?? []).sorted()

            if let drive = DiskSafetyValidator.parseTargetDrive(
                description: desc,
                volumeNames: volumes
            ) {
                result.append(drive)
            }
        }

        // Sort by BSD name ascending (e.g. disk4, disk5)
        self.availableDrives = result.sorted { $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending }
    }
}

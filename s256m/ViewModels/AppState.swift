//
//  AppState.swift
//  s256m
//
//  Created by Marko Kucher on 8/10/26.
//

import SwiftUI
import Observation

/// Central application state coordinator managing image selection, checksum jobs,
/// live drive monitoring, and block writing workflows.
@Observable
@MainActor
public final class AppState {

    // MARK: - Source Image State

    /// Currently selected disk image file URL.
    public var selectedImageURL: URL?

    /// Size in bytes of the selected image.
    public var imageByteCount: Int64 = 0

    /// Calculated or calculating checksum results.
    public var checksumResult: ChecksumResult?

    /// Whether a checksum computation task is currently active.
    public var isCalculatingChecksum: Bool = false

    /// Progress of the active checksum calculation (0.0 ... 1.0).
    public var checksumProgressFraction: Double = 0.0

    /// Live throughput of active checksum calculation in bytes per second.
    public var checksumSpeedBytesPerSecond: Double = 0.0

    /// User-supplied hash candidate string to compare against computed digests.
    public var candidateHash: String = ""

    // MARK: - Drive Selection State

    /// The hardware disk monitor observing external/removable storage.
    public let diskMonitor: DiskMonitor

    /// Currently selected target drive.
    public var selectedDrive: TargetDrive?

    // MARK: - Write & Verification Pipeline State

    /// Current execution state of the writing/verifying pipeline.
    public var writeState: WriteState = .idle

    /// Flag controlling the write confirmation & progress sheet.
    public var isWriteSheetPresented: Bool = false

    /// Whether verification read-back should be performed after writing.
    public var shouldVerifyAfterWrite: Bool = true

    /// Active writing task reference for cancellation.
    private var writeTask: Task<Void, Never>?

    /// Active checksum computation task for cancellation.
    private var checksumTask: Task<Void, Never>?

    /// Services
    private let checksumEngine = ChecksumEngine()
    private let diskWriter = DiskWriter()

    public init(diskMonitor: DiskMonitor? = nil, autoStartMonitoring: Bool = true) {
        let monitor = diskMonitor ?? DiskMonitor()
        self.diskMonitor = monitor
        if autoStartMonitoring {
            monitor.startMonitoring()
        }
    }

    // MARK: - Image Selection & Checksum Computation

    /// Selects a disk image and starts single-pass SHA-256 + MD5 calculation.
    public func selectImage(url: URL) {
        cancelChecksumCalculation()

        selectedImageURL = url
        checksumResult = nil
        candidateHash = ""

        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        imageByteCount = (attr?[.size] as? NSNumber)?.int64Value ?? 0

        startChecksumCalculation(for: url)
    }

    /// Resets the selected image and cancels any ongoing hashing.
    public func clearSelectedImage() {
        cancelChecksumCalculation()
        selectedImageURL = nil
        imageByteCount = 0
        checksumResult = nil
        candidateHash = ""
    }

    /// Initiates streaming checksum computation with real-time progress callbacks.
    public func startChecksumCalculation(for url: URL) {
        guard !isCalculatingChecksum else { return }

        isCalculatingChecksum = true
        checksumProgressFraction = 0.0
        checksumSpeedBytesPerSecond = 0.0

        checksumTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.checksumEngine.computeChecksums(for: url) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.checksumProgressFraction = progress.fractionCompleted
                        self?.checksumSpeedBytesPerSecond = progress.speedBytesPerSecond
                    }
                }

                self.checksumResult = result
                self.isCalculatingChecksum = false
                self.checksumProgressFraction = 1.0
            } catch is CancellationError {
                self.isCalculatingChecksum = false
            } catch {
                self.isCalculatingChecksum = false
            }
        }
    }

    /// Cancels any active checksum computation.
    public func cancelChecksumCalculation() {
        checksumTask?.cancel()
        checksumTask = nil
        isCalculatingChecksum = false
    }

    // MARK: - Write Pipeline Execution

    /// Starts unmounting, raw block writing, verification, and ejection on the selected drive.
    public func startWriteOperation() {
        guard let imageURL = selectedImageURL, let target = selectedDrive else { return }
        guard !isWritingActive else { return }

        writeState = .unmounting(targetDrive: target.bsdName)
        isWriteSheetPresented = true

        let verify = shouldVerifyAfterWrite

        writeTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.diskWriter.writeAndVerify(
                    imageURL: imageURL,
                    destinationPath: target.rawDevicePath,
                    expectedCapacity: target.totalBytes,
                    targetBSDName: target.bsdName,
                    verify: verify
                ) { [weak self] state in
                    Task { @MainActor [weak self] in
                        self?.writeState = state
                    }
                }
            } catch is CancellationError {
                self.writeState = .cancelled
            } catch let error as DiskWriterError {
                self.writeState = .failed(message: error.localizedDescription)
            } catch {
                self.writeState = .failed(message: error.localizedDescription)
            }
        }
    }

    /// Cancels active write or verification operation.
    public func cancelWriteOperation() {
        writeTask?.cancel()
        writeTask = nil
        writeState = .cancelled
    }

    /// Dismisses the write modal sheet and resets write state.
    public func dismissWriteSheet() {
        if isWritingActive {
            cancelWriteOperation()
        }
        isWriteSheetPresented = false
        writeState = .idle
    }

    // MARK: - Computed Convenience Properties

    public var isWritingActive: Bool {
        switch writeState {
        case .unmounting, .writing, .verifying:
            return true
        default:
            return false
        }
    }

    public var formattedImageSize: String {
        ByteCountFormatter.string(fromByteCount: imageByteCount, countStyle: .file)
    }

    public var canStartWrite: Bool {
        guard selectedImageURL != nil, let drive = selectedDrive else { return false }
        guard !isWritingActive else { return false }
        guard drive.totalBytes >= imageByteCount else { return false }
        return true
    }

    public var hashMatch: HashMatchType {
        guard let checksumResult else { return .none }
        return checksumResult.matches(candidate: candidateHash)
    }
}

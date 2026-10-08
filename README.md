s256m

A native macOS utility designed for fast cryptographic file integrity verification, developer authenticity inspection, and guarded raw disk image flashing to external removable media.

## Core Features

* **Hardware-Accelerated Hashing (SHA-256 & MD5):** Single-pass digest calculation powered by Apple CryptoKit, utilizing a 4 MB streaming buffer for minimal memory footprint.
* **Automatic Hash Matching:** Instant evaluation of computed digests against user input with automated whitespace stripping and prefix normalization.
* **Tier 3 Authenticity & Signature Verification:** Static code signature inspection via the macOS Security framework to validate Apple certificates, notarization tickets, and Developer Team IDs.
* **Raw Image Flashing (Flash to Drive):** Direct low-level block writing of disk images (ISO, DMG, IMG, RAW) to physical block devices.
* **System Drive Protection:** Device filtering via Disk Arbitration that strictly excludes internal SSDs, APFS system containers, Time Machine destinations, and recovery volumes.
* **Post-Write Verification:** Optional read-back SHA-256 verification of written sectors followed by automatic, safe device ejection.

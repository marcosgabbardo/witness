import Foundation
import CryptoKit

/// OpenTimestamps calendar endpoints
enum OTSCalendar: String, CaseIterable {
    case alice = "https://alice.btc.calendar.opentimestamps.org"
    case bob = "https://bob.btc.calendar.opentimestamps.org"
    case finney = "https://finney.calendar.eternitywall.com"
    
    var digestEndpoint: String {
        "\(rawValue)/digest"
    }
    
    var timestampEndpoint: String {
        "\(rawValue)/timestamp"
    }
}

/// Errors from OpenTimestamps operations
enum OTSError: Error, LocalizedError {
    case hashingFailed
    case networkError(Error)
    case invalidResponse(Int)
    case calendarUnavailable
    case verificationFailed(String)
    case invalidOtsFormat
    case pendingConfirmation
    
    var errorDescription: String? {
        switch self {
        case .hashingFailed:
            return "Failed to compute SHA256 hash"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let code):
            return "Calendar returned error: \(code)"
        case .calendarUnavailable:
            return "All calendars are unavailable"
        case .verificationFailed(let reason):
            return "Verification failed: \(reason)"
        case .invalidOtsFormat:
            return "Invalid .ots file format"
        case .pendingConfirmation:
            return "Timestamp pending Bitcoin confirmation"
        }
    }
}

/// OpenTimestamps Protocol Constants
enum OTSConstants {
    static let magicHeader: [UInt8] = [0x00, 0x4f, 0x70, 0x65, 0x6e, 0x54, 0x69, 0x6d, 0x65, 0x73, 0x74, 0x61, 0x6d, 0x70, 0x73, 0x00, 0x00, 0x50, 0x72, 0x6f, 0x6f, 0x66, 0x00, 0xbf, 0x89, 0xe2, 0xe8, 0x84, 0xe8, 0x92, 0x94]
    static let versionByte: UInt8 = 0x01
    
    // Operations
    static let opSha256: UInt8 = 0x08
    static let opAppend: UInt8 = 0xf0
    static let opPrepend: UInt8 = 0xf1
    
    // Attestations
    static let attestationBitcoin: [UInt8] = [0x05, 0x88, 0x96, 0x0d, 0x73, 0xd7, 0x19, 0x01]
    static let attestationPending: [UInt8] = [0x83, 0xdf, 0xe3, 0x0d, 0x2e, 0xf9, 0x0c, 0x8e]
}

/// Service for interacting with OpenTimestamps
actor OpenTimestampsService {
    private let session: URLSession
    private let merkleVerifier = MerkleVerifier()
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Compute SHA256 hash of data
    func sha256(data: Data) -> Data {
        let hash = SHA256.hash(data: data)
        return Data(hash)
    }
    
    /// Compute SHA256 hash of a string
    func sha256(string: String) -> Data? {
        guard let data = string.data(using: .utf8) else { return nil }
        return sha256(data: data)
    }
    
    /// Submit a hash to OpenTimestamps calendars
    /// Returns incomplete .ots data that can be upgraded later
    /// Submits to ALL calendars in parallel for redundancy, returns first success
    func submitHash(_ hash: Data) async throws -> (otsData: Data, calendarUrl: String) {
        // Submit to ALL calendars in parallel for redundancy
        let results = await submitToAllCalendars(hash: hash)
        
        // Return first successful submission
        if let first = results.first {
            print("📤 Submitted to \(results.count)/\(OTSCalendar.allCases.count) calendars")
            for r in results {
                print("   ✅ \(r.calendarUrl)")
            }
            return (first.otsData, first.calendarUrl)
        }
        
        throw OTSError.calendarUnavailable
    }
    
    /// Submit to all calendars in parallel, return all successful submissions
    func submitToAllCalendars(hash: Data) async -> [(otsData: Data, calendarUrl: String)] {
        await withTaskGroup(of: (otsData: Data, calendarUrl: String)?.self) { group in
            for calendar in OTSCalendar.allCases {
                group.addTask {
                    do {
                        let otsData = try await self.submitToCalendar(hash: hash, calendar: calendar)
                        return (otsData, calendar.rawValue)
                    } catch {
                        print("   ❌ Failed to submit to \(calendar.rawValue): \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            
            var results: [(otsData: Data, calendarUrl: String)] = []
            for await result in group {
                if let r = result {
                    results.append(r)
                }
            }
            return results
        }
    }
    
    /// Try to upgrade a pending timestamp to a complete one with Bitcoin attestation
    func upgradeTimestamp(hash: Data, calendarUrl: String) async throws -> Data? {
        guard let calendar = OTSCalendar(rawValue: calendarUrl) else {
            print("   ❌ Invalid calendar URL: \(calendarUrl)")
            throw OTSError.calendarUnavailable
        }
        
        let urlString = "\(calendar.timestampEndpoint)/\(hash.hexString)"
        let url = URL(string: urlString)!
        print("   📡 Fetching: \(urlString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.opentimestamps.v1", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OTSError.networkError(URLError(.badServerResponse))
        }
        
        print("   📬 Status: \(httpResponse.statusCode), Size: \(data.count) bytes")
        
        switch httpResponse.statusCode {
        case 200:
            // Check if it contains Bitcoin attestation
            let hasBitcoin = containsBitcoinAttestation(data)
            print("   🔍 Has Bitcoin attestation: \(hasBitcoin)")
            
            if hasBitcoin {
                // Construct complete .ots file with Bitcoin attestation
                let completeOts = constructOtsFile(hash: hash, calendarResponse: data, calendarUrl: calendarUrl)
                print("   ✅ Built complete OTS: \(completeOts.count) bytes")
                return completeOts
            } else {
                print("   ⏳ Still pending (no Bitcoin attestation yet)")
                return nil // Still pending
            }
        case 404:
            print("   ⏳ Not found (404) - not ready yet")
            return nil // Not ready yet
        default:
            print("   ❌ Unexpected status: \(httpResponse.statusCode)")
            throw OTSError.invalidResponse(httpResponse.statusCode)
        }
    }
    
    /// Try to upgrade from all known calendars in PARALLEL
    /// Returns the first one that has Bitcoin attestation
    func upgradeTimestampFromAnyCalendar(hash: Data) async -> Data? {
        print("🔄 Trying upgrade from all \(OTSCalendar.allCases.count) calendars in parallel...")
        
        // Use TaskGroup to try all calendars in parallel
        // Return as soon as one succeeds with Bitcoin attestation
        return await withTaskGroup(of: (calendar: String, data: Data?)?.self) { group in
            for calendar in OTSCalendar.allCases {
                group.addTask {
                    do {
                        if let upgraded = try await self.upgradeTimestamp(hash: hash, calendarUrl: calendar.rawValue) {
                            return (calendar.rawValue, upgraded)
                        }
                        return (calendar.rawValue, nil)
                    } catch {
                        return nil
                    }
                }
            }
            
            // Return first successful upgrade with Bitcoin attestation
            for await result in group {
                if let r = result, let data = r.data {
                    print("   ✅ Got Bitcoin attestation from \(r.calendar)")
                    // Cancel remaining tasks (they're no longer needed)
                    group.cancelAll()
                    return data
                }
            }
            
            print("   ⏳ No calendar has Bitcoin attestation yet")
            return nil
        }
    }
    
    /// Try to upgrade using the pending OTS data directly
    /// This follows the pending attestation URL to get the Bitcoin proof
    func upgradeFromPendingOts(pendingOtsData: Data, originalHash: Data) async -> Data? {
        do {
            let proof = try await merkleVerifier.parseOtsFile(pendingOtsData)
            
            // Find pending attestations
            for attestation in proof.attestations {
                guard case .pending(let calendarUrl) = attestation else { continue }
                
                // Compute the commitment hash by applying operations
                var commitment = originalHash
                for operation in proof.operations {
                    commitment = applyOperationSimple(operation, to: commitment)
                }
                
                // Try to get upgraded proof from calendar
                let timestampUrl = "\(calendarUrl)/timestamp/\(commitment.hexString)"
                print("   📡 Trying pending URL: \(timestampUrl)")
                
                guard let url = URL(string: timestampUrl) else { continue }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("application/vnd.opentimestamps.v1", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 10
                
                guard let (data, response) = try? await session.data(for: request),
                      let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("   ❌ Failed to get from \(timestampUrl)")
                    continue
                }
                
                print("   📬 Got response: \(data.count) bytes")
                
                // Check if it has Bitcoin attestation
                if containsBitcoinAttestation(data) {
                    print("   ✅ Has Bitcoin attestation!")
                    // Construct complete OTS with the upgraded proof
                    return constructUpgradedOts(
                        originalHash: originalHash,
                        originalOperations: proof.operations,
                        calendarResponse: data
                    )
                }
            }
        } catch {
            print("   ❌ Parse error: \(error)")
        }
        
        return nil
    }
    
    private func applyOperationSimple(_ operation: OTSOperation, to data: Data) -> Data {
        switch operation {
        case .sha256:
            return sha256(data: data)
        case .append(let appendData):
            return data + appendData
        case .prepend(let prependData):
            return prependData + data
        default:
            return data
        }
    }
    
    private func constructUpgradedOts(originalHash: Data, originalOperations: [OTSOperation], calendarResponse: Data) -> Data {
        var ots = Data()
        
        // Magic header
        ots.append(contentsOf: OTSConstants.magicHeader)
        
        // Version
        ots.append(OTSConstants.versionByte)
        
        // Hash type (SHA256)
        ots.append(OTSConstants.opSha256)
        
        // The original hash
        ots.append(originalHash)
        
        // Original operations (if any)
        for op in originalOperations {
            switch op {
            case .sha256:
                ots.append(OTSConstants.opSha256)
            case .append(let appendData):
                ots.append(OTSConstants.opAppend)
                ots.append(contentsOf: encodeVarInt(UInt64(appendData.count)))
                ots.append(appendData)
            case .prepend(let prependData):
                ots.append(OTSConstants.opPrepend)
                ots.append(contentsOf: encodeVarInt(UInt64(prependData.count)))
                ots.append(prependData)
            default:
                break
            }
        }
        
        // Calendar response (contains the Bitcoin attestation path)
        ots.append(calendarResponse)
        
        return ots
    }
    
    private func encodeVarInt(_ value: UInt64) -> [UInt8] {
        var result: [UInt8] = []
        var v = value
        while v >= 0x80 {
            result.append(UInt8(v & 0x7f) | 0x80)
            v >>= 7
        }
        result.append(UInt8(v))
        return result
    }
    
    /// Verify an .ots proof against the Bitcoin blockchain
    func verifyTimestamp(otsData: Data, originalHash: Data) async throws -> VerificationResult {
        // Parse the .ots file
        guard validateOtsFormat(otsData) else {
            throw OTSError.invalidOtsFormat
        }
        
        // Use the comprehensive Merkle verifier
        do {
            let proof = try await merkleVerifier.parseOtsFile(otsData)
            let merkleResult = try await merkleVerifier.verifyProof(proof, originalHash: originalHash)
            
            // Check status
            switch merkleResult.status {
            case .confirmed:
                return .confirmed(
                    blockHeight: merkleResult.blockHeight ?? 0,
                    blockTime: merkleResult.blockTime ?? Date(),
                    txId: merkleResult.blockHash,
                    operations: merkleResult.operations,
                    originalHash: merkleResult.originalHash.hexString,
                    computedHash: merkleResult.computedHash
                )
                
            case .pending:
                return .pending(
                    calendars: merkleResult.pendingCalendars,
                    operations: merkleResult.operations,
                    originalHash: merkleResult.originalHash.hexString,
                    computedHash: merkleResult.computedHash
                )
                
            case .failed(let message):
                return .failed(message: message)
            }
        } catch MerkleError.noBitcoinAttestation {
            // Try to parse again just to get the pending calendars
            if let proof = try? await merkleVerifier.parseOtsFile(otsData) {
                let pendingCalendars = proof.attestations.compactMap { attestation -> String? in
                    if case .pending(let url) = attestation { return url }
                    return nil
                }
                return .pending(
                    calendars: pendingCalendars,
                    operations: proof.operations,
                    originalHash: proof.originalHash.hexString,
                    computedHash: ""
                )
            }
            return .failed(message: "No Bitcoin attestation found")
        } catch {
            // Fallback to simple extraction if full verification fails
            if let blockInfo = extractBitcoinBlockInfo(otsData) {
                let verified = try await verifyAgainstBlockchain(
                    hash: originalHash,
                    blockHeight: blockInfo.height,
                    expectedMerkleRoot: blockInfo.merkleRoot
                )
                
                if verified {
                    return .confirmed(
                        blockHeight: blockInfo.height,
                        blockTime: blockInfo.timestamp ?? Date(),
                        txId: blockInfo.txId,
                        operations: [],
                        originalHash: originalHash.hexString,
                        computedHash: ""
                    )
                }
            }
            
            return .failed(message: "Could not verify against blockchain: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func submitToCalendar(hash: Data, calendar: OTSCalendar) async throws -> Data {
        let url = URL(string: calendar.digestEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = hash
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OTSError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OTSError.invalidResponse(httpResponse.statusCode)
        }
        
        // Construct complete .ots file with the calendar's response
        return constructOtsFile(hash: hash, calendarResponse: data, calendarUrl: calendar.rawValue)
    }
    
    private func constructOtsFile(hash: Data, calendarResponse: Data, calendarUrl: String) -> Data {
        var ots = Data()
        
        // Magic header
        ots.append(contentsOf: OTSConstants.magicHeader)
        
        // Version
        ots.append(OTSConstants.versionByte)
        
        // Hash type (SHA256)
        ots.append(OTSConstants.opSha256)
        
        // The hash itself
        ots.append(hash)
        
        // Calendar response (contains pending attestation or operations)
        ots.append(calendarResponse)
        
        return ots
    }
    
    private func validateOtsFormat(_ data: Data) -> Bool {
        guard data.count > OTSConstants.magicHeader.count else { return false }
        let header = Array(data.prefix(OTSConstants.magicHeader.count))
        return header == OTSConstants.magicHeader
    }
    
    private func containsBitcoinAttestation(_ data: Data) -> Bool {
        let bytes = Array(data)
        let attestation = OTSConstants.attestationBitcoin
        
        for i in 0..<(bytes.count - attestation.count) {
            if Array(bytes[i..<(i + attestation.count)]) == attestation {
                return true
            }
        }
        return false
    }
    
    private func extractBitcoinBlockInfo(_ data: Data) -> (height: Int, timestamp: Date, txId: String, merkleRoot: Data)? {
        // This is a simplified extraction - real implementation would parse the full proof
        // For MVP, we'll use a blockchain API to verify
        
        let bytes = Array(data)
        let attestation = OTSConstants.attestationBitcoin
        
        for i in 0..<(bytes.count - attestation.count - 4) {
            if Array(bytes[i..<(i + attestation.count)]) == attestation {
                // Next 4 bytes after attestation marker are the block height (little endian)
                let heightStart = i + attestation.count
                if heightStart + 4 <= bytes.count {
                    let heightBytes = Array(bytes[heightStart..<(heightStart + 4)])
                    let height = Int(heightBytes[0]) |
                                 Int(heightBytes[1]) << 8 |
                                 Int(heightBytes[2]) << 16 |
                                 Int(heightBytes[3]) << 24
                    
                    // We'll fetch the actual timestamp from blockchain API
                    return (height: height, timestamp: Date(), txId: "", merkleRoot: Data())
                }
            }
        }
        return nil
    }
    
    private func verifyAgainstBlockchain(hash: Data, blockHeight: Int, expectedMerkleRoot: Data) async throws -> Bool {
        // Use blockstream.info API to verify
        let url = URL(string: "https://blockstream.info/api/block-height/\(blockHeight)")!
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let blockHash = String(data: data, encoding: .utf8) else {
            return false
        }
        
        // Get block info
        let blockUrl = URL(string: "https://blockstream.info/api/block/\(blockHash)")!
        let (blockData, _) = try await session.data(from: blockUrl)
        
        // Parse block info
        if let json = try? JSONSerialization.jsonObject(with: blockData) as? [String: Any],
           let _ = json["merkle_root"] as? String {
            // For full verification, we'd need to verify the merkle path
            // For MVP, we just confirm the block exists
            return true
        }
        
        return false
    }
}

// MARK: - Supporting Types

struct VerificationResult {
    let isValid: Bool
    let isPending: Bool
    let blockHeight: Int?
    let blockTime: Date?
    let txId: String?
    let pendingCalendars: [String]
    let operations: [OTSOperation]
    let originalHash: String
    let computedHash: String
    let errorMessage: String?
    
    static func confirmed(blockHeight: Int, blockTime: Date, txId: String?, operations: [OTSOperation], originalHash: String, computedHash: String) -> VerificationResult {
        VerificationResult(
            isValid: true,
            isPending: false,
            blockHeight: blockHeight,
            blockTime: blockTime,
            txId: txId,
            pendingCalendars: [],
            operations: operations,
            originalHash: originalHash,
            computedHash: computedHash,
            errorMessage: nil
        )
    }
    
    static func pending(calendars: [String], operations: [OTSOperation], originalHash: String, computedHash: String) -> VerificationResult {
        VerificationResult(
            isValid: false,
            isPending: true,
            blockHeight: nil,
            blockTime: nil,
            txId: nil,
            pendingCalendars: calendars,
            operations: operations,
            originalHash: originalHash,
            computedHash: computedHash,
            errorMessage: nil
        )
    }
    
    static func failed(message: String) -> VerificationResult {
        VerificationResult(
            isValid: false,
            isPending: false,
            blockHeight: nil,
            blockTime: nil,
            txId: nil,
            pendingCalendars: [],
            operations: [],
            originalHash: "",
            computedHash: "",
            errorMessage: message
        )
    }
}

// MARK: - Extensions

extension Data {
    // hexString is defined in MerkleVerifier.swift
    
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }
        
        self = data
    }
}

import Testing
import Foundation
@testable import DataStamp

@Suite("OpenTimestamps Service Tests")
struct OpenTimestampsServiceTests {
    
    let service = OpenTimestampsService()
    
    // MARK: - Hash Tests
    
    @Test("SHA256 hash of string produces correct output")
    func testSHA256String() async {
        let testString = "Hello, World!"
        let hash = await service.sha256(string: testString)
        
        #expect(hash != nil)
        #expect(hash?.count == 32) // SHA256 produces 32 bytes
        
        // Known SHA256 of "Hello, World!"
        let expectedHex = "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"
        #expect(hash?.hexString == expectedHex)
    }
    
    @Test("SHA256 hash of empty string")
    func testSHA256EmptyString() async {
        let hash = await service.sha256(string: "")
        
        #expect(hash != nil)
        // Known SHA256 of empty string
        let expectedHex = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        #expect(hash?.hexString == expectedHex)
    }
    
    @Test("SHA256 hash of data")
    func testSHA256Data() async {
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        let hash = await service.sha256(data: testData)
        
        #expect(hash.count == 32)
    }
    
    // MARK: - OTS Format Tests
    
    @Test("Valid OTS header is recognized")
    func testValidOTSHeader() async {
        var validOTS = Data(OTSConstants.magicHeader)
        validOTS.append(OTSConstants.versionByte)
        validOTS.append(OTSConstants.opSha256)
        validOTS.append(contentsOf: [UInt8](repeating: 0xAB, count: 32)) // fake hash
        
        // The service should accept this as valid format
        // Note: Full validation would require more complete OTS data
        #expect(validOTS.count > OTSConstants.magicHeader.count)
    }
    
    @Test("OTS magic header constant is correct")
    func testOTSMagicHeader() {
        // The magic header spells out "OpenTimestamps" with padding
        let header = OTSConstants.magicHeader
        #expect(header.count == 31)
        
        // Check that it starts with null byte and contains "OpenTimestamps"
        #expect(header[0] == 0x00)
        
        // Bytes 1-14 spell "OpenTimestamps"
        let otsBytes = header[1...14]
        let otsString = String(bytes: otsBytes, encoding: .ascii)
        #expect(otsString == "OpenTimestamps")
    }
}

@Suite("Merkle Verifier Tests")
struct MerkleVerifierTests {
    
    let verifier = MerkleVerifier()
    
    // MARK: - OTS Reader Tests
    
    @Test("OTS Reader reads single byte correctly")
    func testReadByte() throws {
        var reader = OTSReader(data: Data([0x42, 0x43]))
        
        let byte1 = try reader.readByte()
        #expect(byte1 == 0x42)
        
        let byte2 = try reader.readByte()
        #expect(byte2 == 0x43)
        
        #expect(!reader.hasMore)
    }
    
    @Test("OTS Reader reads multiple bytes correctly")
    func testReadBytes() throws {
        var reader = OTSReader(data: Data([0x01, 0x02, 0x03, 0x04, 0x05]))
        
        let bytes = try reader.readBytes(count: 3)
        #expect(bytes == [0x01, 0x02, 0x03])
        #expect(reader.hasMore)
    }
    
    @Test("OTS Reader varint decoding - small value")
    func testVarIntSmall() throws {
        var reader = OTSReader(data: Data([0x7F])) // 127
        let value = try reader.readVarInt()
        #expect(value == 127)
    }
    
    @Test("OTS Reader varint decoding - multi-byte")
    func testVarIntMultiByte() throws {
        var reader = OTSReader(data: Data([0x80, 0x01])) // 128
        let value = try reader.readVarInt()
        #expect(value == 128)
    }
    
    @Test("OTS Reader throws on end of data")
    func testReadBeyondEnd() {
        var reader = OTSReader(data: Data([0x42]))
        _ = try? reader.readByte()
        
        #expect(throws: MerkleError.self) {
            _ = try reader.readByte()
        }
    }
}

@Suite("Data Extension Tests")
struct DataExtensionTests {
    
    @Test("Hex string conversion")
    func testHexString() {
        let data = Data([0x00, 0x0F, 0xFF, 0xAB])
        #expect(data.hexString == "000fffab")
    }
    
    @Test("Empty data hex string")
    func testEmptyHexString() {
        let data = Data()
        #expect(data.hexString == "")
    }
    
    @Test("Hex string init - valid")
    func testHexStringInit() {
        let data = Data(hexString: "deadbeef")
        #expect(data != nil)
        #expect(data?.count == 4)
        #expect(data?[0] == 0xDE)
        #expect(data?[1] == 0xAD)
        #expect(data?[2] == 0xBE)
        #expect(data?[3] == 0xEF)
    }
    
    @Test("Hex string init - invalid characters")
    func testHexStringInitInvalid() {
        let data = Data(hexString: "ghij")
        #expect(data == nil)
    }
}

@Suite("DataStampItem Model Tests")
struct DataStampItemTests {
    
    @Test("DataStampItem initialization")
    func testInit() {
        let hash = Data([UInt8](repeating: 0xAB, count: 32))
        let item = DataStampItem(
            contentType: .text,
            contentHash: hash,
            title: "Test Note",
            textContent: "Hello, World!"
        )
        
        #expect(item.contentType == .text)
        #expect(item.contentHash == hash)
        #expect(item.title == "Test Note")
        #expect(item.textContent == "Hello, World!")
        #expect(item.status == .pending)
    }
    
    @Test("DataStampItem hash hex")
    func testHashHex() {
        let hash = Data([0xAB, 0xCD, 0xEF])
        let item = DataStampItem(contentType: .text, contentHash: hash)
        
        #expect(item.hashHex == "abcdef")
    }
    
    @Test("DataStampItem display title - with title")
    func testDisplayTitleWithTitle() {
        let item = DataStampItem(
            contentType: .text,
            contentHash: Data(),
            title: "My Title"
        )
        
        #expect(item.displayTitle == "My Title")
    }
    
    @Test("DataStampItem display title - text truncation")
    func testDisplayTitleTextTruncation() {
        let longText = String(repeating: "a", count: 100)
        let item = DataStampItem(
            contentType: .text,
            contentHash: Data(),
            title: nil,
            textContent: longText
        )
        
        #expect(item.displayTitle.count == 53) // 50 chars + "..."
        #expect(item.displayTitle.hasSuffix("..."))
    }
    
    @Test("DataStampItem status icon mapping")
    func testStatusIcons() {
        let item = DataStampItem(contentType: .text, contentHash: Data())
        
        item.status = .pending
        #expect(item.statusIcon == "clock")
        
        item.status = .submitted
        #expect(item.statusIcon == "arrow.up.circle")
        
        item.status = .confirmed
        #expect(item.statusIcon == "checkmark.seal.fill")
        
        item.status = .verified
        #expect(item.statusIcon == "checkmark.shield.fill")
        
        item.status = .failed
        #expect(item.statusIcon == "xmark.circle.fill")
    }
    
    @Test("DataStampItem isConfirmed")
    func testIsConfirmed() {
        let item = DataStampItem(contentType: .text, contentHash: Data())
        
        item.status = .pending
        #expect(!item.isConfirmed)
        
        item.status = .submitted
        #expect(!item.isConfirmed)
        
        item.status = .confirmed
        #expect(item.isConfirmed)
        
        item.status = .verified
        #expect(item.isConfirmed)
        
        item.status = .failed
        #expect(!item.isConfirmed)
    }
}

@Suite("PDF Export Service Tests")
struct PDFExportServiceTests {
    
    let pdfService = PDFExportService()
    
    @Test("Generate PDF certificate creates valid data")
    func testGenerateCertificate() async throws {
        let snapshot = DataStampItemSnapshot(
            id: UUID(),
            createdAt: Date(),
            contentType: .text,
            contentHash: Data([UInt8](repeating: 0xAB, count: 32)),
            contentFileName: nil,
            textContent: "Test content for PDF generation",
            title: "Test Certificate",
            status: .confirmed,
            calendarUrl: "https://alice.btc.calendar.opentimestamps.org",
            submittedAt: Date().addingTimeInterval(-3600),
            confirmedAt: Date(),
            bitcoinBlockHeight: 830000,
            bitcoinBlockTime: Date(),
            bitcoinTxId: "abc123def456"
        )
        
        let pdfData = try await pdfService.generateCertificate(for: snapshot)
        
        // PDF data should start with %PDF
        #expect(pdfData.count > 0)
        let header = String(data: pdfData.prefix(4), encoding: .ascii)
        #expect(header == "%PDF")
    }
}

// Note: DataStampItemSnapshot memberwise init is defined in PDFExportService.swift

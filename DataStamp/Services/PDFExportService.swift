import Foundation
import UIKit
import PDFKit
import CoreImage.CIFilterBuiltins

/// Service for generating PDF certificates of timestamps
actor PDFExportService {
    
    // MARK: - Brand Colors
    
    private let bitcoinOrange = UIColor(red: 247/255, green: 147/255, blue: 26/255, alpha: 1.0)
    private let darkText = UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1.0)
    private let mediumText = UIColor(red: 80/255, green: 80/255, blue: 80/255, alpha: 1.0)
    private let lightText = UIColor(red: 140/255, green: 140/255, blue: 140/255, alpha: 1.0)
    private let borderGold = UIColor(red: 180/255, green: 150/255, blue: 80/255, alpha: 1.0)
    private let verifiedGreen = UIColor(red: 34/255, green: 139/255, blue: 34/255, alpha: 1.0)
    
    // MARK: - PDF Generation
    
    func generateCertificate(
        for item: DataStampItemSnapshot,
        contentImage: UIImage? = nil
    ) async throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let pdfData = renderer.pdfData { context in
            context.beginPage()
            
            // UIGraphicsPDFRenderer uses UIKit coordinates (origin top-left)
            // So we draw top-to-bottom naturally
            drawCertificateTopDown(context: context, pageRect: pageRect, item: item, contentImage: contentImage)
        }
        
        return pdfData
    }
    
    func saveCertificateToFile(data: Data, itemId: UUID) async throws -> URL {
        let filename = "DataStamp_Certificate_\(itemId.uuidString.prefix(8)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
    
    // MARK: - Main Drawing (Top-Down)
    
    private func drawCertificateTopDown(
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        item: DataStampItemSnapshot,
        contentImage: UIImage?
    ) {
        let margin: CGFloat = 45
        let contentWidth = pageRect.width - margin * 2
        var y: CGFloat = margin // Start from top
        
        // === DECORATIVE BORDER ===
        drawBorder(in: context.cgContext, rect: pageRect, margin: margin - 10)
        
        // === HEADER: DATASTAMP BRANDING ===
        y += 10
        let brandFont = UIFont.systemFont(ofSize: 11, weight: .bold)
        let brandAttr: [NSAttributedString.Key: Any] = [
            .font: brandFont,
            .foregroundColor: bitcoinOrange,
            .kern: 2.0
        ]
        "DATASTAMP".draw(at: CGPoint(x: margin, y: y), withAttributes: brandAttr)
        
        // Powered by Bitcoin (right side)
        let poweredFont = UIFont.systemFont(ofSize: 8, weight: .medium)
        let poweredAttr: [NSAttributedString.Key: Any] = [
            .font: poweredFont,
            .foregroundColor: lightText
        ]
        let poweredText = "Powered by Bitcoin"
        let poweredSize = poweredText.size(withAttributes: poweredAttr)
        poweredText.draw(at: CGPoint(x: pageRect.width - margin - poweredSize.width, y: y + 2), withAttributes: poweredAttr)
        
        y += 35
        
        // === BITCOIN SEAL ===
        let sealSize: CGFloat = 70
        let sealX = (pageRect.width - sealSize) / 2
        drawBitcoinSeal(in: context.cgContext, at: CGPoint(x: sealX, y: y), size: sealSize)
        
        y += sealSize + 20
        
        // === MAIN TITLE ===
        let titleFont = UIFont(name: "Georgia-Bold", size: 28) ?? UIFont.boldSystemFont(ofSize: 28)
        let title = "CERTIFICATE OF EXISTENCE"
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: darkText,
            .kern: 1.5
        ]
        let titleSize = title.size(withAttributes: titleAttr)
        title.draw(at: CGPoint(x: (pageRect.width - titleSize.width) / 2, y: y), withAttributes: titleAttr)
        
        y += titleSize.height + 8
        
        // === SUBTITLE ===
        let subtitleFont = UIFont(name: "Georgia-Italic", size: 12) ?? UIFont.italicSystemFont(ofSize: 12)
        let subtitle = "Cryptographic Proof Anchored to the Bitcoin Blockchain"
        let subtitleAttr: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: mediumText
        ]
        let subtitleSize = subtitle.size(withAttributes: subtitleAttr)
        subtitle.draw(at: CGPoint(x: (pageRect.width - subtitleSize.width) / 2, y: y), withAttributes: subtitleAttr)
        
        y += subtitleSize.height + 12
        
        // === DECORATIVE DIVIDER ===
        drawDivider(in: context.cgContext, y: y, pageRect: pageRect, margin: margin + 60)
        
        y += 20
        
        // === STATUS BADGE ===
        drawStatusBadge(in: context.cgContext, status: item.status, centerX: pageRect.width / 2, y: y)
        
        y += 40
        
        // === CERTIFICATE NUMBER ===
        let certFont = UIFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let certNum = "Certificate No. \(item.id.uuidString.prefix(8).uppercased())"
        let certAttr: [NSAttributedString.Key: Any] = [
            .font: certFont,
            .foregroundColor: lightText
        ]
        let certSize = certNum.size(withAttributes: certAttr)
        certNum.draw(at: CGPoint(x: (pageRect.width - certSize.width) / 2, y: y), withAttributes: certAttr)
        
        y += certSize.height + 25
        
        // === TWO COLUMN LAYOUT ===
        let colWidth = (contentWidth - 40) / 2
        let leftX = margin
        let rightX = margin + colWidth + 40
        
        // Left Column: DOCUMENT INFO
        var leftY = y
        leftY = drawSectionTitle("DOCUMENT", x: leftX, y: leftY, context: context.cgContext)
        leftY = drawInfoRow("Title", item.title ?? "Untitled", x: leftX, y: leftY, width: colWidth)
        leftY = drawInfoRow("Type", contentTypeString(item.contentType), x: leftX, y: leftY, width: colWidth)
        if let fileName = item.contentFileName {
            leftY = drawInfoRow("Filename", fileName, x: leftX, y: leftY, width: colWidth)
        }
        leftY = drawInfoRow("Created", formatDate(item.createdAt), x: leftX, y: leftY, width: colWidth)
        if let submitted = item.submittedAt {
            leftY = drawInfoRow("Submitted", formatDate(submitted), x: leftX, y: leftY, width: colWidth)
        }
        
        // Right Column: BLOCKCHAIN
        var rightY = y
        rightY = drawSectionTitle("BLOCKCHAIN ATTESTATION", x: rightX, y: rightY, context: context.cgContext)
        
        if let blockHeight = item.bitcoinBlockHeight {
            rightY = drawInfoRow("Block Height", "#\(formatNumber(blockHeight))", x: rightX, y: rightY, width: colWidth)
        } else {
            rightY = drawInfoRow("Block Height", "Pending...", x: rightX, y: rightY, width: colWidth)
        }
        
        if let blockTime = item.bitcoinBlockTime {
            rightY = drawInfoRow("Block Time", formatDate(blockTime), x: rightX, y: rightY, width: colWidth)
        }
        
        if let calendarUrl = item.calendarUrl {
            let calendarName = extractCalendarName(calendarUrl)
            rightY = drawInfoRow("Calendar", calendarName, x: rightX, y: rightY, width: colWidth)
        }
        
        if let blockHeight = item.bitcoinBlockHeight {
            let confirmations = max(0, 880000 - blockHeight)
            if confirmations > 0 {
                rightY = drawInfoRow("Confirmations", "~\(formatNumber(confirmations))+", x: rightX, y: rightY, width: colWidth)
            }
        }
        
        y = max(leftY, rightY) + 20
        
        // === SHA-256 HASH BOX ===
        y = drawHashBox(item.hashHex, x: margin, y: y, width: contentWidth, context: context.cgContext)
        
        y += 25
        
        // === QR CODE + VERIFICATION ===
        drawQRSection(in: context.cgContext, item: item, y: y, pageRect: pageRect, margin: margin)
        
        // === FOOTER ===
        drawFooter(in: context.cgContext, pageRect: pageRect, margin: margin)
    }
    
    // MARK: - Drawing Helpers
    
    private func drawBorder(in context: CGContext, rect: CGRect, margin: CGFloat) {
        // Outer gold border
        context.setStrokeColor(borderGold.cgColor)
        context.setLineWidth(2)
        context.stroke(rect.insetBy(dx: margin, dy: margin))
        
        // Inner orange line
        context.setStrokeColor(bitcoinOrange.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)
        context.stroke(rect.insetBy(dx: margin + 8, dy: margin + 8))
        
        // Corner accents
        let cornerLen: CGFloat = 20
        let inset = margin + 2
        context.setStrokeColor(borderGold.cgColor)
        context.setLineWidth(3)
        
        // Top-left
        context.move(to: CGPoint(x: inset, y: inset + cornerLen))
        context.addLine(to: CGPoint(x: inset, y: inset))
        context.addLine(to: CGPoint(x: inset + cornerLen, y: inset))
        context.strokePath()
        
        // Top-right
        context.move(to: CGPoint(x: rect.width - inset - cornerLen, y: inset))
        context.addLine(to: CGPoint(x: rect.width - inset, y: inset))
        context.addLine(to: CGPoint(x: rect.width - inset, y: inset + cornerLen))
        context.strokePath()
        
        // Bottom-left
        context.move(to: CGPoint(x: inset, y: rect.height - inset - cornerLen))
        context.addLine(to: CGPoint(x: inset, y: rect.height - inset))
        context.addLine(to: CGPoint(x: inset + cornerLen, y: rect.height - inset))
        context.strokePath()
        
        // Bottom-right
        context.move(to: CGPoint(x: rect.width - inset - cornerLen, y: rect.height - inset))
        context.addLine(to: CGPoint(x: rect.width - inset, y: rect.height - inset))
        context.addLine(to: CGPoint(x: rect.width - inset, y: rect.height - inset - cornerLen))
        context.strokePath()
    }
    
    private func drawBitcoinSeal(in context: CGContext, at point: CGPoint, size: CGFloat) {
        let centerX = point.x + size / 2
        let centerY = point.y + size / 2
        
        // Outer glow
        context.setFillColor(bitcoinOrange.withAlphaComponent(0.1).cgColor)
        context.fillEllipse(in: CGRect(x: point.x - 5, y: point.y - 5, width: size + 10, height: size + 10))
        
        // Main circle
        context.setFillColor(bitcoinOrange.cgColor)
        context.fillEllipse(in: CGRect(x: point.x, y: point.y, width: size, height: size))
        
        // Inner ring
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(2)
        context.strokeEllipse(in: CGRect(x: point.x + 6, y: point.y + 6, width: size - 12, height: size - 12))
        
        // Bitcoin symbol
        let btcFont = UIFont.systemFont(ofSize: size * 0.5, weight: .bold)
        let btcAttr: [NSAttributedString.Key: Any] = [
            .font: btcFont,
            .foregroundColor: UIColor.white
        ]
        let btc = "₿"
        let btcSize = btc.size(withAttributes: btcAttr)
        btc.draw(at: CGPoint(x: centerX - btcSize.width / 2, y: centerY - btcSize.height / 2), withAttributes: btcAttr)
    }
    
    private func drawDivider(in context: CGContext, y: CGFloat, pageRect: CGRect, margin: CGFloat) {
        let centerX = pageRect.width / 2
        
        context.setStrokeColor(borderGold.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1)
        
        // Left line
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(to: CGPoint(x: centerX - 15, y: y))
        context.strokePath()
        
        // Right line
        context.move(to: CGPoint(x: centerX + 15, y: y))
        context.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
        context.strokePath()
        
        // Center diamond
        context.setFillColor(bitcoinOrange.cgColor)
        context.move(to: CGPoint(x: centerX, y: y - 5))
        context.addLine(to: CGPoint(x: centerX + 5, y: y))
        context.addLine(to: CGPoint(x: centerX, y: y + 5))
        context.addLine(to: CGPoint(x: centerX - 5, y: y))
        context.closePath()
        context.fillPath()
    }
    
    private func drawStatusBadge(in context: CGContext, status: DataStampStatus, centerX: CGFloat, y: CGFloat) {
        let badgeHeight: CGFloat = 26
        let badgeWidth: CGFloat = 200
        let badgeX = centerX - badgeWidth / 2
        
        let (color, text): (UIColor, String)
        switch status {
        case .confirmed, .verified:
            color = verifiedGreen
            text = "✓  BLOCKCHAIN VERIFIED"
        case .submitted:
            color = bitcoinOrange
            text = "◐  PENDING CONFIRMATION"
        case .pending:
            color = UIColor.gray
            text = "○  DRAFT"
        case .failed:
            color = UIColor.red
            text = "✗  FAILED"
        }
        
        // Badge pill
        let badgeRect = CGRect(x: badgeX, y: y, width: badgeWidth, height: badgeHeight)
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeHeight / 2)
        context.setFillColor(color.cgColor)
        context.addPath(badgePath.cgPath)
        context.fillPath()
        
        // Text
        let font = UIFont.systemFont(ofSize: 10, weight: .bold)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: 1.0
        ]
        let textSize = text.size(withAttributes: attr)
        text.draw(at: CGPoint(x: centerX - textSize.width / 2, y: y + (badgeHeight - textSize.height) / 2), withAttributes: attr)
    }
    
    private func drawSectionTitle(_ title: String, x: CGFloat, y: CGFloat, context: CGContext) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 9, weight: .bold)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: bitcoinOrange,
            .kern: 1.5
        ]
        title.draw(at: CGPoint(x: x, y: y), withAttributes: attr)
        
        // Underline
        context.setStrokeColor(bitcoinOrange.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: y + 14))
        context.addLine(to: CGPoint(x: x + 150, y: y + 14))
        context.strokePath()
        
        return y + 22
    }
    
    private func drawInfoRow(_ label: String, _ value: String, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let labelFont = UIFont.systemFont(ofSize: 9, weight: .medium)
        let valueFont = UIFont.systemFont(ofSize: 9, weight: .regular)
        
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: mediumText
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: darkText
        ]
        
        label.draw(at: CGPoint(x: x, y: y), withAttributes: labelAttr)
        
        // Truncate value if needed
        let maxValueWidth = width - 80
        let valueRect = CGRect(x: x + 75, y: y, width: maxValueWidth, height: 14)
        value.draw(in: valueRect, withAttributes: valueAttr)
        
        return y + 16
    }
    
    private func drawHashBox(_ hash: String, x: CGFloat, y: CGFloat, width: CGFloat, context: CGContext) -> CGFloat {
        // Title
        let titleFont = UIFont.systemFont(ofSize: 9, weight: .bold)
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: bitcoinOrange,
            .kern: 1.5
        ]
        "SHA-256 DOCUMENT FINGERPRINT".draw(at: CGPoint(x: x, y: y), withAttributes: titleAttr)
        
        let boxY = y + 18
        let boxHeight: CGFloat = 36
        
        // Box background
        let boxRect = CGRect(x: x, y: boxY, width: width, height: boxHeight)
        let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 4)
        context.setFillColor(UIColor(white: 0.96, alpha: 1.0).cgColor)
        context.addPath(boxPath.cgPath)
        context.fillPath()
        
        // Box border
        context.setStrokeColor(borderGold.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(1)
        context.addPath(boxPath.cgPath)
        context.strokePath()
        
        // Hash text (two lines)
        let hashFont = UIFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        let hashAttr: [NSAttributedString.Key: Any] = [
            .font: hashFont,
            .foregroundColor: darkText
        ]
        
        let line1 = String(hash.prefix(32))
        let line2 = String(hash.suffix(32))
        
        line1.draw(at: CGPoint(x: x + 12, y: boxY + 6), withAttributes: hashAttr)
        line2.draw(at: CGPoint(x: x + 12, y: boxY + 19), withAttributes: hashAttr)
        
        return boxY + boxHeight
    }
    
    private func drawQRSection(in context: CGContext, item: DataStampItemSnapshot, y: CGFloat, pageRect: CGRect, margin: CGFloat) {
        guard let qrImage = generateQRCode(for: item) else { return }
        
        let qrSize: CGFloat = 80
        
        // QR Code
        context.setStrokeColor(borderGold.cgColor)
        context.setLineWidth(2)
        context.stroke(CGRect(x: margin - 2, y: y - 2, width: qrSize + 4, height: qrSize + 4))
        
        qrImage.draw(in: CGRect(x: margin, y: y, width: qrSize, height: qrSize))
        
        // Verification instructions
        let textX = margin + qrSize + 20
        let textWidth = pageRect.width - textX - margin
        
        let titleFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: darkText
        ]
        "Verify This Certificate".draw(at: CGPoint(x: textX, y: y), withAttributes: titleAttr)
        
        let instructionFont = UIFont.systemFont(ofSize: 8, weight: .regular)
        let instructionAttr: [NSAttributedString.Key: Any] = [
            .font: instructionFont,
            .foregroundColor: mediumText
        ]
        
        let instructions = """
        1. Scan QR code to view blockchain transaction
        2. Compare document hash with on-chain data
        3. Verify using opentimestamps.org with .ots file
        """
        
        let instructionRect = CGRect(x: textX, y: y + 18, width: textWidth, height: 50)
        instructions.draw(in: instructionRect, withAttributes: instructionAttr)
        
        // URL
        let urlFont = UIFont.monospacedSystemFont(ofSize: 7, weight: .medium)
        let urlAttr: [NSAttributedString.Key: Any] = [
            .font: urlFont,
            .foregroundColor: bitcoinOrange
        ]
        
        let url: String
        if let txId = item.bitcoinTxId, !txId.isEmpty {
            url = "blockstream.info/tx/\(txId.prefix(24))..."
        } else {
            url = "opentimestamps.org"
        }
        url.draw(at: CGPoint(x: textX, y: y + qrSize - 12), withAttributes: urlAttr)
    }
    
    private func drawFooter(in context: CGContext, pageRect: CGRect, margin: CGFloat) {
        let footerY = pageRect.height - margin - 25
        
        // Divider
        context.setStrokeColor(borderGold.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: footerY))
        context.addLine(to: CGPoint(x: pageRect.width - margin, y: footerY))
        context.strokePath()
        
        // Legal text
        let legalFont = UIFont.systemFont(ofSize: 7, weight: .regular)
        let legalAttr: [NSAttributedString.Key: Any] = [
            .font: legalFont,
            .foregroundColor: lightText
        ]
        
        let legal = "This certificate attests that the referenced document existed at the time indicated by the Bitcoin blockchain timestamp. The cryptographic proof is independently verifiable using the OpenTimestamps protocol. This certificate does not verify the content, accuracy, or legal validity of the document itself."
        
        let legalRect = CGRect(x: margin, y: footerY + 8, width: pageRect.width - margin * 2 - 80, height: 25)
        legal.draw(in: legalRect, withAttributes: legalAttr)
        
        // DataStamp brand
        let brandFont = UIFont.systemFont(ofSize: 9, weight: .bold)
        let brandAttr: [NSAttributedString.Key: Any] = [
            .font: brandFont,
            .foregroundColor: bitcoinOrange
        ]
        let brand = "DATASTAMP"
        let brandSize = brand.size(withAttributes: brandAttr)
        brand.draw(at: CGPoint(x: pageRect.width - margin - brandSize.width, y: footerY + 8), withAttributes: brandAttr)
    }
    
    // MARK: - Helpers
    
    private func generateQRCode(for item: DataStampItemSnapshot) -> UIImage? {
        var urlString: String
        
        if let txId = item.bitcoinTxId, !txId.isEmpty {
            urlString = "https://blockstream.info/tx/\(txId)"
        } else if let blockHeight = item.bitcoinBlockHeight {
            urlString = "https://blockstream.info/block-height/\(blockHeight)"
        } else {
            urlString = "https://opentimestamps.org"
        }
        
        guard let data = urlString.data(using: .utf8) else { return nil }
        
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "H"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    private func contentTypeString(_ type: ContentType) -> String {
        switch type {
        case .text: return "Text Document"
        case .photo: return "Photograph"
        case .file: return "File"
        }
    }
    
    private func extractCalendarName(_ url: String) -> String {
        if url.contains("alice") { return "Alice" }
        if url.contains("bob") { return "Bob" }
        if url.contains("finney") { return "Finney" }
        return "OpenTimestamps"
    }
}

// MARK: - Snapshot Model

struct DataStampItemSnapshot: Sendable {
    let id: UUID
    let createdAt: Date
    let contentType: ContentType
    let contentHash: Data
    let contentFileName: String?
    let textContent: String?
    let title: String?
    let status: DataStampStatus
    let calendarUrl: String?
    let submittedAt: Date?
    let confirmedAt: Date?
    let bitcoinBlockHeight: Int?
    let bitcoinBlockTime: Date?
    let bitcoinTxId: String?
    
    var hashHex: String {
        contentHash.map { String(format: "%02x", $0) }.joined()
    }
    
    init(from item: DataStampItem) {
        self.id = item.id
        self.createdAt = item.createdAt
        self.contentType = item.contentType
        self.contentHash = item.contentHash
        self.contentFileName = item.contentFileName
        self.textContent = item.textContent
        self.title = item.title
        self.status = item.status
        self.calendarUrl = item.calendarUrl
        self.submittedAt = item.submittedAt
        self.confirmedAt = item.confirmedAt
        self.bitcoinBlockHeight = item.bitcoinBlockHeight
        self.bitcoinBlockTime = item.bitcoinBlockTime
        self.bitcoinTxId = item.bitcoinTxId
    }
    
    init(
        id: UUID,
        createdAt: Date,
        contentType: ContentType,
        contentHash: Data,
        contentFileName: String?,
        textContent: String?,
        title: String?,
        status: DataStampStatus,
        calendarUrl: String?,
        submittedAt: Date?,
        confirmedAt: Date?,
        bitcoinBlockHeight: Int?,
        bitcoinBlockTime: Date?,
        bitcoinTxId: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.contentType = contentType
        self.contentHash = contentHash
        self.contentFileName = contentFileName
        self.textContent = textContent
        self.title = title
        self.status = status
        self.calendarUrl = calendarUrl
        self.submittedAt = submittedAt
        self.confirmedAt = confirmedAt
        self.bitcoinBlockHeight = bitcoinBlockHeight
        self.bitcoinBlockTime = bitcoinBlockTime
        self.bitcoinTxId = bitcoinTxId
    }
}

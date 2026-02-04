import Foundation
import UIKit
import PDFKit
import CoreImage.CIFilterBuiltins

/// Service for generating PDF certificates of timestamps
actor PDFExportService {
    
    // MARK: - PDF Generation
    
    /// Generate a PDF certificate for a timestamp
    func generateCertificate(
        for item: DataStampItemSnapshot,
        contentImage: UIImage? = nil
    ) async throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        
        let pdfData = renderer.pdfData { context in
            context.beginPage()
            drawCertificate(in: context.cgContext, pageRect: pageRect, item: item, contentImage: contentImage)
        }
        
        return pdfData
    }
    
    /// Save PDF certificate to a temporary file and return URL
    func saveCertificateToFile(
        data: Data,
        itemId: UUID
    ) async throws -> URL {
        let filename = "DataStamp_Certificate_\(itemId.uuidString.prefix(8)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
    
    // MARK: - Drawing
    
    private func drawCertificate(
        in context: CGContext,
        pageRect: CGRect,
        item: DataStampItemSnapshot,
        contentImage: UIImage?
    ) {
        let margin: CGFloat = 50
        let contentWidth = pageRect.width - (margin * 2)
        var yPosition: CGFloat = margin // Start from top
        
        // Colors
        let primaryColor = UIColor(red: 0.95, green: 0.6, blue: 0.1, alpha: 1.0) // Orange
        let textColor = UIColor.black
        let subtitleColor = UIColor.darkGray
        let borderColor = UIColor.lightGray
        
        // === TOP BORDER ===
        context.setStrokeColor(primaryColor.cgColor)
        context.setLineWidth(3)
        context.move(to: CGPoint(x: margin, y: pageRect.height - yPosition))
        context.addLine(to: CGPoint(x: pageRect.width - margin, y: pageRect.height - yPosition))
        context.strokePath()
        
        yPosition += 30
        
        // === TITLE ===
        let titleFont = UIFont.systemFont(ofSize: 28, weight: .bold)
        let title = "Timestamp Certificate"
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: textColor
        ]
        let titleSize = title.size(withAttributes: titleAttr)
        let titleX = (pageRect.width - titleSize.width) / 2
        let titleY = pageRect.height - yPosition - titleSize.height
        title.draw(at: CGPoint(x: titleX, y: titleY), withAttributes: titleAttr)
        
        yPosition += titleSize.height + 8
        
        // === SUBTITLE ===
        let subtitleFont = UIFont.systemFont(ofSize: 14, weight: .regular)
        let subtitle = "Powered by OpenTimestamps & Bitcoin"
        let subtitleAttr: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: subtitleColor
        ]
        let subtitleSize = subtitle.size(withAttributes: subtitleAttr)
        let subtitleX = (pageRect.width - subtitleSize.width) / 2
        let subtitleY = pageRect.height - yPosition - subtitleSize.height
        subtitle.draw(at: CGPoint(x: subtitleX, y: subtitleY), withAttributes: subtitleAttr)
        
        yPosition += subtitleSize.height + 25
        
        // === STATUS BADGE ===
        let badgeHeight: CGFloat = 32
        let badgeWidth: CGFloat = 160
        let badgeX = (pageRect.width - badgeWidth) / 2
        let badgeY = pageRect.height - yPosition - badgeHeight
        
        let badgeColor: UIColor
        let badgeText: String
        
        switch item.status {
        case .confirmed, .verified:
            badgeColor = UIColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0)
            badgeText = "✓ VERIFIED"
        case .submitted:
            badgeColor = UIColor(red: 0.95, green: 0.6, blue: 0.1, alpha: 1.0)
            badgeText = "⏳ PENDING"
        case .pending:
            badgeColor = UIColor.gray
            badgeText = "○ DRAFT"
        case .failed:
            badgeColor = UIColor.red
            badgeText = "✗ FAILED"
        }
        
        let badgePath = UIBezierPath(roundedRect: CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight), cornerRadius: badgeHeight / 2)
        context.setFillColor(badgeColor.cgColor)
        context.addPath(badgePath.cgPath)
        context.fillPath()
        
        let badgeFont = UIFont.systemFont(ofSize: 14, weight: .bold)
        let badgeAttr: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: UIColor.white
        ]
        let badgeTextSize = badgeText.size(withAttributes: badgeAttr)
        let badgeTextX = badgeX + (badgeWidth - badgeTextSize.width) / 2
        let badgeTextY = badgeY + (badgeHeight - badgeTextSize.height) / 2
        badgeText.draw(at: CGPoint(x: badgeTextX, y: badgeTextY), withAttributes: badgeAttr)
        
        yPosition += badgeHeight + 30
        
        // === CONTENT PREVIEW ===
        if let image = contentImage {
            let maxImageHeight: CGFloat = 120
            let maxImageWidth: CGFloat = contentWidth - 100
            let aspectRatio = image.size.width / image.size.height
            
            var imageWidth = maxImageWidth
            var imageHeight = imageWidth / aspectRatio
            
            if imageHeight > maxImageHeight {
                imageHeight = maxImageHeight
                imageWidth = imageHeight * aspectRatio
            }
            
            let imageX = (pageRect.width - imageWidth) / 2
            let imageY = pageRect.height - yPosition - imageHeight
            
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(1)
            context.stroke(CGRect(x: imageX - 2, y: imageY - 2, width: imageWidth + 4, height: imageHeight + 4))
            
            image.draw(in: CGRect(x: imageX, y: imageY, width: imageWidth, height: imageHeight))
            
            yPosition += imageHeight + 25
        } else if let textContent = item.textContent, !textContent.isEmpty {
            let textBoxHeight: CGFloat = 60
            let textBoxX = margin + 20
            let textBoxY = pageRect.height - yPosition - textBoxHeight
            let textBoxWidth = contentWidth - 40
            
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(1)
            context.stroke(CGRect(x: textBoxX, y: textBoxY, width: textBoxWidth, height: textBoxHeight))
            
            let contentFont = UIFont.systemFont(ofSize: 11, weight: .regular)
            let truncatedText = String(textContent.prefix(200)) + (textContent.count > 200 ? "..." : "")
            let contentAttr: [NSAttributedString.Key: Any] = [
                .font: contentFont,
                .foregroundColor: textColor
            ]
            
            let textRect = CGRect(x: textBoxX + 10, y: textBoxY + 8, width: textBoxWidth - 20, height: textBoxHeight - 16)
            truncatedText.draw(in: textRect, withAttributes: contentAttr)
            
            yPosition += textBoxHeight + 25
        }
        
        // === DOCUMENT INFORMATION SECTION ===
        yPosition = drawSectionHeader("Document Information", yPosition: yPosition, pageRect: pageRect, margin: margin, color: primaryColor)
        
        if let title = item.title, !title.isEmpty {
            yPosition = drawDetailRow("Title:", title, yPosition: yPosition, pageRect: pageRect, margin: margin)
        }
        
        let typeString: String
        switch item.contentType {
        case .text: typeString = "Text Document"
        case .photo: typeString = "Photograph"
        case .file: typeString = "File (\(item.contentFileName ?? "unknown"))"
        }
        yPosition = drawDetailRow("Type:", typeString, yPosition: yPosition, pageRect: pageRect, margin: margin)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .medium
        yPosition = drawDetailRow("Created:", dateFormatter.string(from: item.createdAt), yPosition: yPosition, pageRect: pageRect, margin: margin)
        
        yPosition += 15
        
        // === CRYPTOGRAPHIC PROOF SECTION ===
        yPosition = drawSectionHeader("Cryptographic Proof", yPosition: yPosition, pageRect: pageRect, margin: margin, color: primaryColor)
        
        yPosition = drawDetailRow("SHA-256 Hash:", "", yPosition: yPosition, pageRect: pageRect, margin: margin)
        yPosition = drawMonospaceText(item.hashHex, yPosition: yPosition, pageRect: pageRect, margin: margin)
        
        if let calendarUrl = item.calendarUrl {
            yPosition = drawDetailRow("Calendar Server:", calendarUrl, yPosition: yPosition, pageRect: pageRect, margin: margin)
        }
        
        if let submittedAt = item.submittedAt {
            yPosition = drawDetailRow("Submitted:", dateFormatter.string(from: submittedAt), yPosition: yPosition, pageRect: pageRect, margin: margin)
        }
        
        yPosition += 15
        
        // === BITCOIN ATTESTATION SECTION ===
        if item.status == .confirmed || item.status == .verified {
            yPosition = drawSectionHeader("Bitcoin Blockchain Attestation", yPosition: yPosition, pageRect: pageRect, margin: margin, color: primaryColor)
            
            if let blockHeight = item.bitcoinBlockHeight {
                yPosition = drawDetailRow("Block Height:", "#\(blockHeight)", yPosition: yPosition, pageRect: pageRect, margin: margin)
            }
            
            if let blockTime = item.bitcoinBlockTime {
                yPosition = drawDetailRow("Block Time:", dateFormatter.string(from: blockTime), yPosition: yPosition, pageRect: pageRect, margin: margin)
            }
            
            if let txId = item.bitcoinTxId, !txId.isEmpty {
                yPosition = drawDetailRow("Transaction:", "", yPosition: yPosition, pageRect: pageRect, margin: margin)
                yPosition = drawMonospaceText(txId, yPosition: yPosition, pageRect: pageRect, margin: margin)
            }
        }
        
        // === QR CODE (Top Right) ===
        if let qrImage = generateQRCode(for: item) {
            let qrSize: CGFloat = 80
            let qrX = pageRect.width - margin - qrSize
            let qrY = pageRect.height - margin - 30 - qrSize // Below top border
            
            qrImage.draw(in: CGRect(x: qrX, y: qrY, width: qrSize, height: qrSize))
            
            let qrLabelFont = UIFont.systemFont(ofSize: 7, weight: .regular)
            let qrLabel = "Verify on blockchain"
            let qrLabelAttr: [NSAttributedString.Key: Any] = [
                .font: qrLabelFont,
                .foregroundColor: subtitleColor
            ]
            let qrLabelSize = qrLabel.size(withAttributes: qrLabelAttr)
            qrLabel.draw(at: CGPoint(x: qrX + (qrSize - qrLabelSize.width) / 2, y: qrY - qrLabelSize.height - 2), withAttributes: qrLabelAttr)
        }
        
        // === FOOTER (Bottom) ===
        let footerY: CGFloat = margin + 30
        
        // Bottom border
        context.setStrokeColor(primaryColor.cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: margin, y: footerY + 20))
        context.addLine(to: CGPoint(x: pageRect.width - margin, y: footerY + 20))
        context.strokePath()
        
        // Footer text
        let footerFont = UIFont.systemFont(ofSize: 8, weight: .regular)
        let footerText = "This certificate was generated by DataStamp app. Verify authenticity using the .ots proof file at opentimestamps.org"
        let footerAttr: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: subtitleColor
        ]
        footerText.draw(at: CGPoint(x: margin, y: footerY), withAttributes: footerAttr)
        
        // DataStamp logo
        let logoFont = UIFont.systemFont(ofSize: 9, weight: .bold)
        let logoText = "DATASTAMP"
        let logoAttr: [NSAttributedString.Key: Any] = [
            .font: logoFont,
            .foregroundColor: primaryColor
        ]
        let logoSize = logoText.size(withAttributes: logoAttr)
        logoText.draw(at: CGPoint(x: pageRect.width - margin - logoSize.width, y: footerY), withAttributes: logoAttr)
    }
    
    private func drawSectionHeader(
        _ text: String,
        yPosition: CGFloat,
        pageRect: CGRect,
        margin: CGFloat,
        color: UIColor
    ) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = text.size(withAttributes: attr)
        let y = pageRect.height - yPosition - size.height
        
        text.draw(at: CGPoint(x: margin, y: y), withAttributes: attr)
        
        return yPosition + size.height + 12
    }
    
    private func drawDetailRow(
        _ label: String,
        _ value: String,
        yPosition: CGFloat,
        pageRect: CGRect,
        margin: CGFloat
    ) -> CGFloat {
        let labelFont = UIFont.systemFont(ofSize: 10, weight: .medium)
        let valueFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        
        let labelAttr: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor.darkGray
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: UIColor.black
        ]
        
        let labelSize = label.size(withAttributes: labelAttr)
        let y = pageRect.height - yPosition - labelSize.height
        
        label.draw(at: CGPoint(x: margin + 10, y: y), withAttributes: labelAttr)
        
        if !value.isEmpty {
            value.draw(at: CGPoint(x: margin + 110, y: y), withAttributes: valueAttr)
        }
        
        return yPosition + labelSize.height + 6
    }
    
    private func drawMonospaceText(
        _ text: String,
        yPosition: CGFloat,
        pageRect: CGRect,
        margin: CGFloat
    ) -> CGFloat {
        let font = UIFont.monospacedSystemFont(ofSize: 7, weight: .regular)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black
        ]
        
        let size = text.size(withAttributes: attr)
        let y = pageRect.height - yPosition - size.height
        
        // Background
        let bgRect = CGRect(x: margin + 10, y: y - 2, width: size.width + 10, height: size.height + 4)
        UIColor(white: 0.95, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: bgRect, cornerRadius: 3).fill()
        
        text.draw(at: CGPoint(x: margin + 15, y: y), withAttributes: attr)
        
        return yPosition + size.height + 10
    }
    
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
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = 8.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Snapshot Model

/// Immutable snapshot of DataStampItem for thread-safe PDF generation
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

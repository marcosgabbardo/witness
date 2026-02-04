import UIKit
import Social
import UniformTypeIdentifiers
import CryptoKit

class ShareViewController: UIViewController {
    
    private var contentHash: Data?
    private var contentType: String = "file"
    private var fileName: String?
    private var textContent: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        setupUI()
        processSharedContent()
    }
    
    private func setupUI() {
        // Title
        let titleLabel = UILabel()
        titleLabel.text = "DataStamp"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // Subtitle
        let subtitleLabel = UILabel()
        subtitleLabel.text = "Create timestamp proof"
        subtitleLabel.font = .systemFont(ofSize: 17)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)
        
        // Activity indicator
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.tag = 100
        view.addSubview(spinner)
        
        // Status label
        let statusLabel = UILabel()
        statusLabel.text = "Processing..."
        statusLabel.font = .systemFont(ofSize: 15)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.tag = 101
        view.addSubview(statusLabel)
        
        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
    
    private func processSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProviders = extensionItem.attachments else {
            showError("No content to share")
            return
        }
        
        for provider in itemProviders {
            // Handle text
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] item, error in
                    let text = item as? String
                    DispatchQueue.main.async {
                        if let text = text {
                            self?.textContent = text
                            self?.contentType = "text"
                            self?.hashText(text)
                        }
                    }
                }
                return
            }
            
            // Handle URL (could be file or web)
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] item, error in
                    let url = item as? URL
                    let isFileURL = url?.isFileURL ?? false
                    let lastComponent = url?.lastPathComponent
                    let absoluteString = url?.absoluteString
                    DispatchQueue.main.async {
                        if let url = url {
                            if isFileURL {
                                self?.fileName = lastComponent
                                self?.contentType = "file"
                                self?.hashFile(at: url)
                            } else {
                                // Web URL - hash the URL string
                                self?.textContent = absoluteString
                                self?.contentType = "text"
                                if let str = absoluteString {
                                    self?.hashText(str)
                                }
                            }
                        }
                    }
                }
                return
            }
            
            // Handle image
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] item, error in
                    let url = item as? URL
                    let imageData = (item as? UIImage)?.jpegData(compressionQuality: 0.9)
                    let lastComponent = url?.lastPathComponent
                    DispatchQueue.main.async {
                        if let url = url {
                            self?.fileName = lastComponent
                            self?.contentType = "photo"
                            self?.hashFile(at: url)
                        } else if let data = imageData {
                            self?.contentType = "photo"
                            self?.hashData(data)
                        }
                    }
                }
                return
            }
            
            // Handle any file
            if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.data.identifier) { [weak self] item, error in
                    let url = item as? URL
                    let rawData = item as? Data
                    let lastComponent = url?.lastPathComponent
                    DispatchQueue.main.async {
                        if let url = url {
                            self?.fileName = lastComponent
                            self?.contentType = "file"
                            self?.hashFile(at: url)
                        } else if let data = rawData {
                            self?.contentType = "file"
                            self?.hashData(data)
                        }
                    }
                }
                return
            }
        }
        
        showError("Unsupported content type")
    }
    
    private func hashText(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            showError("Failed to process text")
            return
        }
        hashData(data)
    }
    
    private func hashFile(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            hashData(data)
        } catch {
            showError("Failed to read file: \(error.localizedDescription)")
        }
    }
    
    private func hashData(_ data: Data) {
        let hash = SHA256.hash(data: data)
        contentHash = Data(hash)
        
        DispatchQueue.main.async { [weak self] in
            self?.submitToOpenTimestamps()
        }
    }
    
    private func submitToOpenTimestamps() {
        guard let hash = contentHash else {
            showError("No hash generated")
            return
        }
        
        updateStatus("Submitting to OpenTimestamps...")
        
        // Submit to OpenTimestamps calendar
        let url = URL(string: "https://a.pool.opentimestamps.org/digest")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = hash
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.showError("Failed to submit: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let otsData = data else {
                    self?.showError("Server error")
                    return
                }
                
                // Save to shared container for main app to pick up
                self?.saveForMainApp(otsData: otsData)
            }
        }.resume()
    }
    
    private func saveForMainApp(otsData: Data) {
        // Use App Group shared container
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.makiavel.datestamp") else {
            showError("Failed to access shared container")
            return
        }
        
        let pendingDir = containerURL.appendingPathComponent("pending")
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        
        let itemId = UUID().uuidString
        let itemDir = pendingDir.appendingPathComponent(itemId)
        try? FileManager.default.createDirectory(at: itemDir, withIntermediateDirectories: true)
        
        // Save OTS data
        let otsFile = itemDir.appendingPathComponent("timestamp.ots")
        try? otsData.write(to: otsFile)
        
        // Save metadata
        let metadata: [String: Any] = [
            "id": itemId,
            "contentType": contentType,
            "contentHash": contentHash?.base64EncodedString() ?? "",
            "fileName": fileName ?? "",
            "textContent": textContent ?? "",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "status": "submitted"
        ]
        
        let metadataFile = itemDir.appendingPathComponent("metadata.json")
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata) {
            try? jsonData.write(to: metadataFile)
        }
        
        showSuccess()
    }
    
    private func updateStatus(_ message: String) {
        if let label = view.viewWithTag(101) as? UILabel {
            label.text = message
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            if let spinner = self?.view.viewWithTag(100) as? UIActivityIndicatorView {
                spinner.stopAnimating()
            }
            
            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "DataStamp", code: -1))
            })
            self?.present(alert, animated: true)
        }
    }
    
    private func showSuccess() {
        if let spinner = view.viewWithTag(100) as? UIActivityIndicatorView {
            spinner.stopAnimating()
            spinner.isHidden = true
        }
        
        updateStatus("✓ Timestamp created!\nOpen DataStamp app to see details.")
        
        // Auto-close after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
    
    @objc private func cancelTapped() {
        extensionContext?.cancelRequest(withError: NSError(domain: "DataStamp", code: 0))
    }
}

import Foundation

struct LicenseActivationRecord: Codable, Equatable, Sendable {
    let licenseKey: String
    let licenseKeyID: Int?
    let activationInstanceID: String?
    let activationInstanceName: String?
    let storeID: Int?
    let orderID: Int?
    let productID: Int?
    let productName: String?
    let variantID: Int?
    let variantName: String?
    let customerName: String?
    let customerEmail: String?
    let activatedAt: Date
    let lastValidatedAt: Date?

    var maskedLicenseKey: String {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unavailable"
        }

        let suffix = String(trimmed.suffix(4))
        return "•••• \(suffix)"
    }
}

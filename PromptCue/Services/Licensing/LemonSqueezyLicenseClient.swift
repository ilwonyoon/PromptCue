import Foundation

protocol LicenseActivationClient {
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivationRecord
}

struct LemonSqueezyLicenseMeta: Equatable, Sendable {
    let storeID: Int
    let orderID: Int?
    let productID: Int
    let productName: String?
    let variantID: Int?
    let variantName: String?
    let customerName: String?
    let customerEmail: String?
}

enum LemonSqueezyLicenseClientError: LocalizedError {
    case configurationMissing
    case activationRejected(String)
    case unexpectedResponse(String)
    case productMismatch

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Licensing is not configured in this build yet."
        case .activationRejected(let message):
            return message
        case .unexpectedResponse(let message):
            return message
        case .productMismatch:
            return "This license key does not match this Backtick build."
        }
    }
}

struct LemonSqueezyLicenseClient: LicenseActivationClient {
    private let configuration: LicensingConfiguration
    private let urlSession: URLSession

    init(
        configuration: LicensingConfiguration,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.urlSession = urlSession
    }

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivationRecord {
        guard configuration.isActivationAvailable else {
            throw LemonSqueezyLicenseClientError.configurationMissing
        }

        let endpoint = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(
            ActivateRequestBody(
                licenseKey: licenseKey,
                instanceName: instanceName
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw LemonSqueezyLicenseClientError.unexpectedResponse(
                "Lemon Squeezy returned HTTP \(httpResponse.statusCode)."
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload = try decoder.decode(ActivateResponse.self, from: data)

        if let errorMessage = payload.error,
           !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LemonSqueezyLicenseClientError.activationRejected(errorMessage)
        }

        guard payload.activated == true,
              let licenseKeyPayload = payload.licenseKey,
              let meta = payload.meta else {
            throw LemonSqueezyLicenseClientError.unexpectedResponse(
                "Lemon Squeezy returned an incomplete activation response."
            )
        }

        guard configuration.accepts(meta: meta) else {
            throw LemonSqueezyLicenseClientError.productMismatch
        }

        return LicenseActivationRecord(
            licenseKey: licenseKeyPayload.key ?? licenseKey,
            licenseKeyID: licenseKeyPayload.id,
            activationInstanceID: payload.instance?.id,
            activationInstanceName: payload.instance?.name ?? instanceName,
            storeID: meta.storeID,
            orderID: meta.orderID,
            productID: meta.productID,
            productName: meta.productName,
            variantID: meta.variantID,
            variantName: meta.variantName,
            customerName: meta.customerName,
            customerEmail: meta.customerEmail,
            activatedAt: Date(),
            lastValidatedAt: Date()
        )
    }
}

private struct ActivateRequestBody: Encodable {
    let licenseKey: String
    let instanceName: String
}

private struct ActivateResponse: Decodable {
    let activated: Bool?
    let error: String?
    let licenseKey: LicenseKeyPayload?
    let instance: LicenseInstancePayload?
    let meta: LemonSqueezyLicenseMeta?
}

private struct LicenseKeyPayload: Decodable {
    let id: Int?
    let key: String?
}

private struct LicenseInstancePayload: Decodable {
    let id: String?
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyStringIfPresent(forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

extension LemonSqueezyLicenseMeta: Decodable {
    private enum CodingKeys: String, CodingKey {
        case storeID
        case orderID
        case productID
        case productName
        case variantID
        case variantName
        case customerName
        case customerEmail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storeID = try container.decodeLossyIntIfPresent(forKey: .storeID)
        let productID = try container.decodeLossyIntIfPresent(forKey: .productID)

        guard let storeID,
              let productID else {
            throw LemonSqueezyLicenseClientError.unexpectedResponse(
                "Lemon Squeezy did not include store or product metadata."
            )
        }

        self.init(
            storeID: storeID,
            orderID: try container.decodeLossyIntIfPresent(forKey: .orderID),
            productID: productID,
            productName: try container.decodeIfPresent(String.self, forKey: .productName),
            variantID: try container.decodeLossyIntIfPresent(forKey: .variantID),
            variantName: try container.decodeIfPresent(String.self, forKey: .variantName),
            customerName: try container.decodeIfPresent(String.self, forKey: .customerName),
            customerEmail: try container.decodeIfPresent(String.self, forKey: .customerEmail)
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) throws -> String? {
        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }

        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        return nil
    }

    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }

        if let stringValue = try decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        }

        return nil
    }
}

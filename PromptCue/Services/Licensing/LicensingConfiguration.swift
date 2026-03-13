import Foundation

struct LicensingConfiguration: Equatable, Sendable {
    private enum Keys {
        static let storefrontURL = "PROMPTCUE_STORE_URL"
        static let storeID = "PROMPTCUE_LS_STORE_ID"
        static let productID = "PROMPTCUE_LS_PRODUCT_ID"
        static let variantID = "PROMPTCUE_LS_VARIANT_ID"

        static let infoStorefrontURL = "BacktickStoreURL"
        static let infoStoreID = "BacktickLemonSqueezyStoreID"
        static let infoProductID = "BacktickLemonSqueezyProductID"
        static let infoVariantID = "BacktickLemonSqueezyVariantID"
    }

    let storefrontURL: URL?
    let lemonSqueezyStoreID: Int?
    let lemonSqueezyProductID: Int?
    let lemonSqueezyVariantID: Int?

    var isActivationAvailable: Bool {
        lemonSqueezyStoreID != nil && lemonSqueezyProductID != nil
    }

    var canOpenStorefront: Bool {
        storefrontURL != nil
    }

    static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LicensingConfiguration {
        LicensingConfiguration(
            storefrontURL: readURL(
                envKey: Keys.storefrontURL,
                infoKey: Keys.infoStorefrontURL,
                bundle: bundle,
                environment: environment
            ),
            lemonSqueezyStoreID: readInt(
                envKey: Keys.storeID,
                infoKey: Keys.infoStoreID,
                bundle: bundle,
                environment: environment
            ),
            lemonSqueezyProductID: readInt(
                envKey: Keys.productID,
                infoKey: Keys.infoProductID,
                bundle: bundle,
                environment: environment
            ),
            lemonSqueezyVariantID: readInt(
                envKey: Keys.variantID,
                infoKey: Keys.infoVariantID,
                bundle: bundle,
                environment: environment
            )
        )
    }

    func accepts(meta: LemonSqueezyLicenseMeta) -> Bool {
        guard let lemonSqueezyStoreID,
              let lemonSqueezyProductID else {
            return false
        }

        guard meta.storeID == lemonSqueezyStoreID,
              meta.productID == lemonSqueezyProductID else {
            return false
        }

        guard let lemonSqueezyVariantID else {
            return true
        }

        return meta.variantID == lemonSqueezyVariantID
    }

    private static func readURL(
        envKey: String,
        infoKey: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> URL? {
        if let envValue = nonEmptyValue(for: envKey, in: environment) {
            return URL(string: envValue)
        }

        guard let infoValue = bundle.object(forInfoDictionaryKey: infoKey) as? String,
              !infoValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return URL(string: infoValue)
    }

    private static func readInt(
        envKey: String,
        infoKey: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> Int? {
        if let envValue = nonEmptyValue(for: envKey, in: environment) {
            return Int(envValue)
        }

        if let infoValue = bundle.object(forInfoDictionaryKey: infoKey) as? String,
           !infoValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Int(infoValue)
        }

        return nil
    }

    private static func nonEmptyValue(
        for key: String,
        in environment: [String: String]
    ) -> String? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        return value
    }
}

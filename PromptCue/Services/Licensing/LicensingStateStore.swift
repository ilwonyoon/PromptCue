import Foundation
import PromptCueCore
import Security

protocol LicensingStateStoring {
    func loadTrialState() throws -> TrialState?
    func saveTrialState(_ trialState: TrialState?) throws
    func loadLicenseRecord() throws -> LicenseActivationRecord?
    func saveLicenseRecord(_ licenseRecord: LicenseActivationRecord?) throws
}

final class InMemoryLicensingStateStore: LicensingStateStoring {
    private var trialState: TrialState?
    private var licenseRecord: LicenseActivationRecord?

    func loadTrialState() throws -> TrialState? {
        trialState
    }

    func saveTrialState(_ trialState: TrialState?) throws {
        self.trialState = trialState
    }

    func loadLicenseRecord() throws -> LicenseActivationRecord? {
        licenseRecord
    }

    func saveLicenseRecord(_ licenseRecord: LicenseActivationRecord?) throws {
        self.licenseRecord = licenseRecord
    }
}

enum KeychainJSONStoreError: LocalizedError {
    case unexpectedData
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Saved licensing state was unreadable."
        case .unhandledStatus(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}

struct KeychainJSONStore {
    let service: String

    func load<Value: Decodable>(_ type: Value.Type, account: String) throws -> Value? {
        let query = baseQuery(account: account).merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, newValue in
            newValue
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainJSONStoreError.unexpectedData
            }
            return try JSONDecoder().decode(Value.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainJSONStoreError.unhandledStatus(status)
        }
    }

    func save<Value: Encodable>(_ value: Value?, account: String) throws {
        guard let value else {
            try remove(account: account)
            return
        }

        let data = try JSONEncoder().encode(value)
        let query = baseQuery(account: account)
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainJSONStoreError.unhandledStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw KeychainJSONStoreError.unhandledStatus(updateStatus)
        }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainJSONStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

final class LicensingStateStore: LicensingStateStoring {
    private enum Accounts {
        static let trialState = "trial-state"
        static let licenseState = "license-state"
    }

    private let keychainStore: KeychainJSONStore

    init(
        keychainStore: KeychainJSONStore = KeychainJSONStore(
            service: "com.promptcue.promptcue.licensing"
        )
    ) {
        self.keychainStore = keychainStore
    }

    func loadTrialState() throws -> TrialState? {
        try keychainStore.load(TrialState.self, account: Accounts.trialState)
    }

    func saveTrialState(_ trialState: TrialState?) throws {
        try keychainStore.save(trialState, account: Accounts.trialState)
    }

    func loadLicenseRecord() throws -> LicenseActivationRecord? {
        try keychainStore.load(LicenseActivationRecord.self, account: Accounts.licenseState)
    }

    func saveLicenseRecord(_ licenseRecord: LicenseActivationRecord?) throws {
        try keychainStore.save(licenseRecord, account: Accounts.licenseState)
    }

    static func makeDefault() -> any LicensingStateStoring {
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if isTestEnvironment {
            return InMemoryLicensingStateStore()
        }

        return LicensingStateStore()
    }
}

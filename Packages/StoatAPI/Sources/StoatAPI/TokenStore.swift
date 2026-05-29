import Foundation
import Security
import StoatModels

public protocol TokenStore: Sendable {
    func loadCredential() async throws -> StoatAuthCredential?
    func saveCredential(_ credential: StoatAuthCredential) async throws
    func clearCredential() async throws
}

public struct CredentialScope: Codable, Hashable, Sendable {
    public var environmentID: String
    public var accountUserID: UserID?

    public init(environmentID: String, accountUserID: UserID? = nil) {
        self.environmentID = environmentID
        self.accountUserID = accountUserID
    }

    public static let production = CredentialScope(environmentID: StoatAPIEnvironment.production.stableID)

    public var keychainAccountName: String {
        let user = accountUserID?.rawValue ?? "default"
        return "credential.\(environmentID).\(user)"
    }
}

public protocol ScopedTokenStore: TokenStore {
    func loadCredential(scope: CredentialScope) async throws -> StoatAuthCredential?
    func saveCredential(_ credential: StoatAuthCredential, scope: CredentialScope) async throws
    func clearCredential(scope: CredentialScope) async throws
}

public actor InMemoryTokenStore: ScopedTokenStore {
    private var credential: StoatAuthCredential?
    private var scopedCredentials: [CredentialScope: StoatAuthCredential] = [:]

    public init(credential: StoatAuthCredential? = nil) {
        self.credential = credential
        if let credential {
            self.scopedCredentials[.production] = credential
        }
    }

    public func loadCredential() async throws -> StoatAuthCredential? {
        credential
    }

    public func saveCredential(_ credential: StoatAuthCredential) async throws {
        self.credential = credential
    }

    public func clearCredential() async throws {
        credential = nil
    }

    public func loadCredential(scope: CredentialScope) async throws -> StoatAuthCredential? {
        scopedCredentials[scope]
    }

    public func saveCredential(_ credential: StoatAuthCredential, scope: CredentialScope) async throws {
        scopedCredentials[scope] = credential
        if scope == .production {
            self.credential = credential
        }
    }

    public func clearCredential(scope: CredentialScope) async throws {
        scopedCredentials.removeValue(forKey: scope)
        if scope == .production {
            credential = nil
        }
    }
}

public enum KeychainTokenStoreError: Error, Equatable, Sendable {
    case encodingFailed(String)
    case decodingFailed(String)
    case unexpectedStatus(OSStatus)
    case unexpectedData
}

public actor KeychainTokenStore: ScopedTokenStore {
    public static let defaultService = "LiquidBagel.Stoat"

    private let service: String
    private let account: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        service: String = KeychainTokenStore.defaultService,
        account: String = "credential",
        encoder: JSONEncoder = .stoat,
        decoder: JSONDecoder = .stoat
    ) {
        self.service = service
        self.account = account
        self.encoder = encoder
        self.decoder = decoder
    }

    public func loadCredential() async throws -> StoatAuthCredential? {
        try await loadCredential(account: account)
    }

    public func loadCredential(scope: CredentialScope) async throws -> StoatAuthCredential? {
        try await loadCredential(account: scope.keychainAccountName)
    }

    private func loadCredential(account: String) async throws -> StoatAuthCredential? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainTokenStoreError.unexpectedData
        }

        do {
            return try decoder.decode(StoatAuthCredential.self, from: data)
        } catch {
            throw KeychainTokenStoreError.decodingFailed(error.localizedDescription)
        }
    }

    public func saveCredential(_ credential: StoatAuthCredential) async throws {
        try await saveCredential(credential, account: account)
    }

    public func saveCredential(_ credential: StoatAuthCredential, scope: CredentialScope) async throws {
        try await saveCredential(credential, account: scope.keychainAccountName)
    }

    private func saveCredential(_ credential: StoatAuthCredential, account: String) async throws {
        let data: Data
        do {
            data = try encoder.encode(credential)
        } catch {
            throw KeychainTokenStoreError.encodingFailed(error.localizedDescription)
        }

        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeychainTokenStoreError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    public func clearCredential() async throws {
        try await clearCredential(account: account)
    }

    public func clearCredential(scope: CredentialScope) async throws {
        try await clearCredential(account: scope.keychainAccountName)
    }

    private func clearCredential(account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

import Foundation
import Security
import StoatModels

public protocol TokenStore: Sendable {
    func loadCredential() async throws -> StoatAuthCredential?
    func saveCredential(_ credential: StoatAuthCredential) async throws
    func clearCredential() async throws
}

public actor InMemoryTokenStore: TokenStore {
    private var credential: StoatAuthCredential?

    public init(credential: StoatAuthCredential? = nil) {
        self.credential = credential
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
}

public enum KeychainTokenStoreError: Error, Equatable, Sendable {
    case encodingFailed(String)
    case decodingFailed(String)
    case unexpectedStatus(OSStatus)
    case unexpectedData
}

public actor KeychainTokenStore: TokenStore {
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
        var query = baseQuery()
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
        let data: Data
        do {
            data = try encoder.encode(credential)
        } catch {
            throw KeychainTokenStoreError.encodingFailed(error.localizedDescription)
        }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery() as CFDictionary,
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
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

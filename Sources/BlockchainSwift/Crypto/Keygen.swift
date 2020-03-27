//
//  ECDSA.swift
//  App
//
//  Created by Magnus Nevstad on 05/04/2019.
//

import Foundation
import os.log

public typealias KeyPair = (privateKey: SecKey, publicKey: SecKey)

@available(iOS 12.0, OSX 10.14, *)
public final class Keygen {
    private static let keychainLabelPrefix = "BlockchainSwift Wallet: "
    private static let keychainAppTagPublic = "BlockchainSwift Public Key".data(using: .utf8)!
    private static let keychainAppTagPrivate = "BlockchainSwift Private Key".data(using: .utf8)!
    
    /// Attempts to generate a random ECDSA key-pair
    public static func generateKeyPair(name: String, storeInKeychain: Bool = false) -> KeyPair? {
        if let existingKeyPair = loadKeyPairFromKeychain(name: name) {
            os_log("Found existing key-pair")
            return existingKeyPair
        } else {
            let keyGenParams: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeEC,
                kSecAttrKeySizeInBits as String: 256,
                kSecPrivateKeyAttrs as String: [
                    kSecAttrIsPermanent as String: storeInKeychain,
                    kSecAttrApplicationTag as String: keychainAppTagPrivate
                ],
                kSecPublicKeyAttrs as String: [
                    kSecAttrIsPermanent as String: storeInKeychain,
                    kSecAttrApplicationTag as String: keychainAppTagPublic
                ],
                kSecAttrLabel as String: keychainLabelPrefix + name as CFString,
            ]
            var error: Unmanaged<CFError>?
            guard let privateKey = SecKeyCreateRandomKey(keyGenParams as CFDictionary, &error),
                let publicKey = SecKeyCopyPublicKey(privateKey) else {
                    os_log("Could not create key-pair", type: .error)
                    return nil
            }
            return (privateKey: privateKey, publicKey: publicKey)
        }
    }
    
    /// Attempts to generate an ECDSA key-pair from the sepcified privateKey data
    /// - Parameter data: The private key data
    public static func generateKeyPair(name: String, privateKeyData: Data, storeInKeychain: Bool = false) -> KeyPair? {
        let keyGenParams: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrLabel as String: keychainLabelPrefix + name as CFString,
            kSecAttrApplicationTag as String: keychainAppTagPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(privateKeyData as CFData,
                                                    keyGenParams as CFDictionary,
                                                    &error) else {
                                                        return nil
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return nil
        }
        return (privateKey: privateKey, publicKey: publicKey)
    }
    
    /// Attempts to generate an ECDSA key-pair from the sepcified privateKey hex
    /// - Parameter data: The private key hex
    public static func generateKeyPair(name: String, privateKeyHex: String, storeInKeychain: Bool = false) -> KeyPair? {
        guard let privateKeyData = Data(hex: privateKeyHex) else { return nil }
        return generateKeyPair(name: name, privateKeyData: privateKeyData, storeInKeychain: storeInKeychain)
    }
    
    /// Copies the specified SecKey into an external Data format
    /// - Parameter key: The key to copy
    public static func copyExternalRepresentation(key: SecKey) -> Data? {
        return SecKeyCopyExternalRepresentation(key, nil) as Data?
    }
    
    /// Fetches an existing Wallet key-pair from the keychain, if it exists
    /// - Parameter name: The name of the wallet
    public static func loadKeyPairFromKeychain(name: String) -> KeyPair? {
        let getQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keychainAppTagPrivate,
            kSecAttrLabel as String: keychainLabelPrefix + name as CFString,
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecReturnRef as String: false
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(getQuery as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        let privateKey = item as! SecKey
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
        return (privateKey: privateKey, publicKey: publicKey)
    }
    
    /// Fetches the available key-pair names from the keychain
    public static func avalaibleKeyPairsNames() -> [String] {
        let getQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keychainAppTagPrivate,
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecReturnAttributes as String: true,
            kSecReturnRef as String: false,
            kSecMatchLimit as String: 999
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(getQuery as CFDictionary, &item)
        guard status == errSecSuccess else { return [] }
        let privateKeys = item as! Array<CFDictionary>
        var keyPairNames = [String]()
        for keyDict in privateKeys {
            let dict = keyDict as! Dictionary<String, Any>
            let label = dict[kSecAttrLabel as String] as! String
            guard label.hasPrefix(keychainLabelPrefix) else {
                continue
            }
            keyPairNames.append(String(label.dropFirst(keychainLabelPrefix.count)))
        }
        return keyPairNames
    }
    
    /// Clears existing Wallet key-pair, if it exists
    /// - Parameter name: The name of the wallet
    /// - Returns: true if both keys associated with the named wallet existed and were deleted, otherwise false
    @discardableResult
    public static func clearKeychainKeys(name: String) -> Bool {
        let deletePublicKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: keychainLabelPrefix + name as CFString,
            kSecAttrApplicationTag as String: keychainAppTagPublic,
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecReturnRef as String: true
        ]
        let deletePrivateKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: keychainLabelPrefix + name as CFString,
            kSecAttrApplicationTag as String: keychainAppTagPrivate,
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecReturnRef as String: true
        ]
        let statusPublic = SecItemDelete(deletePublicKeyQuery as CFDictionary)
        let statusPrivate = SecItemDelete(deletePrivateKeyQuery as CFDictionary)
        return statusPublic == errSecSuccess && statusPrivate == errSecSuccess
    }
}



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
    private static let keychainAppTagPrivate = "BlockchainSwift Private Key".data(using: .utf8)!
    
    /// Attempts to generate a random ECDSA key-pair
    public static func generateKeyPair(name: String, storeInKeychain: Bool = false) -> KeyPair? {
        if let existingKeyPair = loadKeyPairFromKeychain(name: name) {
            os_log("Found existing key-pair")
            return existingKeyPair
        } else {
            let keyGenParams = [kSecAttrKeyType: kSecAttrKeyTypeEC,
                                kSecAttrKeySizeInBits: 256,
                                kSecPrivateKeyAttrs: [kSecAttrIsPermanent: storeInKeychain,
                                                      kSecAttrApplicationTag: keychainAppTagPrivate],
                                kSecPublicKeyAttrs: [kSecAttrIsPermanent: false],
                                kSecAttrIsExtractable: true,
                                kSecUseAuthenticationUI: kSecUseAuthenticationUIAllow,
                                kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
                                kSecAttrLabel: keychainLabelPrefix + name as CFString] as [String: Any]
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
    public static func generateKeyPair(name: String, privateKeyData: Data) -> KeyPair? {
        let keyGenParams = [kSecAttrKeyType: kSecAttrKeyTypeEC,
                             kSecAttrKeyClass: kSecAttrKeyClassPrivate,
                             kSecAttrApplicationTag: keychainAppTagPrivate,
                             kSecAttrIsExtractable: true,
                             kSecUseAuthenticationUI: kSecUseAuthenticationUIAllow,
                             kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
                             kSecAttrLabel: keychainLabelPrefix + name as CFString,
                             kSecAttrKeySizeInBits: 256] as [String: Any]
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
    public static func generateKeyPair(name: String, privateKeyHex: String) -> KeyPair? {
        guard let privateKeyData = Data(hex: privateKeyHex) else { return nil }
        return generateKeyPair(name: name, privateKeyData: privateKeyData)
    }
    
    /// Copies the specified SecKey into an external Data format
    /// - Parameter key: The key to copy
    public static func copyExternalRepresentation(key: SecKey) -> Data? {
        return SecKeyCopyExternalRepresentation(key, nil) as Data?
    }
    
    /// Fetches an existing Wallet key-pair from the keychain, if it exists
    /// - Parameter name: The name of the wallet
    public static func loadKeyPairFromKeychain(name: String) -> KeyPair? {
        let getQuery = [kSecClass: kSecClassKey,
                        kSecAttrKeyClass: kSecAttrKeyClassPrivate,
                        kSecAttrApplicationTag: keychainAppTagPrivate,
                        kSecAttrLabel: keychainLabelPrefix + name as CFString,
                        kSecAttrKeyType: kSecAttrKeyTypeEC,
                        kSecReturnRef: true] as [String: Any]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(getQuery as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        let privateKey = item as! SecKey
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
        return (privateKey: privateKey, publicKey: publicKey)
    }
    
    /// Fetches the available key-pair names from the keychain
    public static func avalaibleKeyPairsNames() -> [String] {
        let getQuery = [kSecClass: kSecClassKey,
                        kSecAttrApplicationTag: keychainAppTagPrivate,
                        kSecAttrKeyType: kSecAttrKeyTypeEC,
                        kSecReturnAttributes: true,
                        kSecReturnRef: true,
                        kSecMatchLimit: 999] as [String: Any]
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
        let deletePrivateKeyQuery = [kSecClass: kSecClassKey,
                                     kSecAttrLabel: keychainLabelPrefix + name as CFString,
                                     kSecAttrApplicationTag: keychainAppTagPrivate,
                                     kSecAttrKeyType: kSecAttrKeyTypeEC] as [String: Any]
        let statusPrivate = SecItemDelete(deletePrivateKeyQuery as CFDictionary)
        return statusPrivate == errSecSuccess
    }
}

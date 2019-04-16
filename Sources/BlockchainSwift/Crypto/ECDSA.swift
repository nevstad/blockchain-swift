//
//  ECDSA.swift
//  App
//
//  Created by Magnus Nevstad on 05/04/2019.
//

import Foundation

final class ECDSA {
    typealias KeyPair = (privateKey: SecKey, publicKey: SecKey)
    
    private static let keyGenParams: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeEC,
        kSecAttrLabel as String: "BlockchainSwift Wallet" as CFString,
        kSecAttrApplicationTag as String: "BlockchainSwift".data(using: .utf8)!,
        kSecAttrKeySizeInBits as String: 256,
        kSecPrivateKeyAttrs as String: [
            kSecAttrIsPermanent as String: false,
            kSecAttrApplicationTag as String: "BlockchainSwift Wallet Private Key".data(using: .utf8)!,
        ],
        kSecPublicKeyAttrs as String: [
            kSecAttrIsPermanent as String: false,
            kSecAttrApplicationTag as String: "BlockchainSwift Wallet Public Key".data(using: .utf8)!,
        ]
    ]
    
    /// Generates a random ECDSA key-pair
    public static func generateKeyPair() -> KeyPair? {
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keyGenParams as CFDictionary, &error),
            let publicKey = SecKeyCopyPublicKey(privateKey) else {
                return nil
        }
        return (privateKey: privateKey, publicKey: publicKey)
    }

    /// Attempts to generate an ECDSA key-pair from the sepcified privateKey data
    /// - Parameter data: The private key data
    public static func generateKeyPair(from data: Data) -> KeyPair? {
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateFromData(keyGenParams as CFDictionary, data as CFData, &error),
            let publicKey = SecKeyCopyPublicKey(privateKey) else {
                return nil
        }
        return (privateKey: privateKey, publicKey: publicKey)
    }
    
    /// Copies the specified SecKey into an external Data format
    /// - Parameter key: The key to copy
    public static func copyExternalRepresentation(key: SecKey) -> Data? {
        return SecKeyCopyExternalRepresentation(key, nil) as Data?
    }
    
    /// Create a signature of the specified data using the specified private key
    /// - Parameter data: The data to sign
    /// - Parameter privateKey: The private key to sign with
    public static func sign(data: Data, with privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey,
                                                    .ecdsaSignatureDigestX962SHA256,
                                                    data as CFData,
                                                    &error) as Data? else {
                                                        throw error!.takeRetainedValue() as Error
        }
        return signature
    }
    
    /// Verifies that the specified publicKey's privateKey was used to create the signature based on the data
    /// - Parameter publicKey: The publicKey whose privateKey supposedly signed the data
    /// - Parameter data: The data that was signed
    /// - Parameter signature: 
    public static func verify(publicKey: Data, data: Data, signature: Data) -> Bool {
        let attributes: [String:Any] = [
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecAttrKeySizeInBits as String: 256 as AnyObject
        ]
        guard let secKey = SecKeyCreateWithData(publicKey as CFData, attributes as CFDictionary, nil) else {
            print("Could not generate SecKey")
            return false
        }
        return SecKeyVerifySignature(secKey,
                                     .ecdsaSignatureDigestX962SHA256,
                                     data as CFData,
                                     signature as CFData,
                                     nil)
    }

}

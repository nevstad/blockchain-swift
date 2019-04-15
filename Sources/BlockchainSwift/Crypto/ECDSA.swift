//
//  ECDSA.swift
//  App
//
//  Created by Magnus Nevstad on 05/04/2019.
//

import Foundation

final class ECDSA {
    typealias KeyPair = (privateKey: SecKey, publicKey: SecKey)
    
    private static let keychainAttrLabel = "BlockchainSwift Wallet" as CFString
    private static let keychainAttrApplicationTag = "BlockchainSwift".data(using: .utf8)!
    
    /// Generate a ECDSA key-pair
    public static func generateKeyPair() -> KeyPair? {
        let query: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
            kSecAttrLabel as String: keychainAttrLabel,
            kSecAttrApplicationTag as String: keychainAttrApplicationTag,
            kSecAttrIsPermanent as String: kCFBooleanFalse,
            kSecAttrKeySizeInBits as String: 256 as AnyObject
        ]
        var privateKey: SecKey?
        var publicKey: SecKey?
        let status = SecKeyGeneratePair(query as CFDictionary, &publicKey, &privateKey)
        
        guard status == errSecSuccess else {
            print("Could not generate keypair")
            return nil
        }
        
        guard let privKey = privateKey, let pubKey = publicKey else {
            print("Keypair null")
            return nil
        }
        
        return (privateKey: privKey, publicKey: pubKey)
    }
    
    /// Copies the specified SecKey into an external Data format
    public static func copyExternalRepresentation(key: SecKey) -> Data? {
        var error: Unmanaged<CFError>?
        guard
            let keyCopy = SecKeyCopyExternalRepresentation(key, &error) as Data?
            else {
                print("Could not copy key")
                return nil
        }
        return keyCopy
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

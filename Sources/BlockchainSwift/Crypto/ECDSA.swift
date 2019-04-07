//
//  ECDSA.swift
//  App
//
//  Created by Magnus Nevstad on 05/04/2019.
//

import Foundation
import CommonCrypto

final class ECDSA {
    typealias KeyPair = (privateKey: SecKey, publicKey: SecKey)
    
    public static func generateKeyPair() -> KeyPair? {
        let query: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeEC,
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

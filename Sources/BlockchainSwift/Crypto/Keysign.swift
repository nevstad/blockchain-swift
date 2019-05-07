//
//  Keysign.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 07/05/2019.
//

import Foundation
import os.log

final class Keysign {
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
            os_log("Could not generate SecKey for verification", type: .error)
            return false
        }
        return SecKeyVerifySignature(secKey,
                                     .ecdsaSignatureDigestX962SHA256,
                                     data as CFData,
                                     signature as CFData,
                                     nil)
    }
}

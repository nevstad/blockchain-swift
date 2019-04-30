//
//  SHA.swift
//  App
//
//  Created by Magnus Nevstad on 02/04/2019.
//

import Foundation
import CommonCrypto

extension Data {
    /// SHA-256 encodes a hash of `self`
    func sha256() -> Data {
        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = digest.withUnsafeMutableBytes { (digestBytes) in
            withUnsafeBytes { (stringBytes) in
                CC_SHA256(stringBytes, CC_LONG(count), digestBytes)
            }
        }
        return digest
    }
    
    func toAddress() -> Data {
        return sha256().sha256()
    }
    
    public init?(hex: String) {
        let len = hex.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hex.index(hex.startIndex, offsetBy: i * 2)
            let k = hex.index(j, offsetBy: 2)
            let bytes = hex[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
    
    /// Return a hex digest of `self`
    public var hex: String {
        return reduce("") { $0 + String(format: "%02x", $1) }
    }
    
    public var readableHex: String {
        if hex.count < 29 {
            return hex
        }
        return "\(hex.prefix(13))...\(hex.suffix(13))"
    }
}

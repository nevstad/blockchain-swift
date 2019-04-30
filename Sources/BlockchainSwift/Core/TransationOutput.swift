//
//  TransationOutput.swift
//  App
//
//  Created by Magnus Nevstad on 06/04/2019.
//

import Foundation

public struct TransactionOutput: Codable, Serializable {
    /// Transaction value
    public let value: UInt64
    
    // The public key hash of the receiver, for claiming output
    public let address: Data
    
    public var hash: Data {
        return serialized().sha256()
    }
    
    public func isLockedWith(publicKeyHash: Data)  -> Bool {
        return self.address == publicKeyHash
    }

    public func serialized() -> Data {
        var data = Data()
        data += value
        data += address
        return data
    }    
}

extension TransactionOutput: CustomDebugStringConvertible {
    public var debugDescription: String {        
        return "\(value) -> \(address.readableHex)"
    }
}

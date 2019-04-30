//
//  TransactionOutPoint.swift
//  App
//
//  Created by Magnus Nevstad on 06/04/2019.
//

import Foundation

/// The out-point of a transaction, referened in TransactionInput
public struct TransactionOutputReference: Codable, Serializable {
    /// The hash of the referenced transaction
    public let hash: Data
    
    /// Index of the specified output in the transaction
    public let index: UInt32
    
    public func serialized() -> Data {
        var data = Data()
        data += hash
        data += index
        return data
    }
}

extension TransactionOutputReference: CustomDebugStringConvertible {
    public var debugDescription: String {
        return hash.readableHex
    }
}

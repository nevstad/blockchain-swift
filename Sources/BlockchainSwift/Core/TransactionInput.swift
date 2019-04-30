//
//  TransactionInput.swift
//  App
//
//  Created by Magnus Nevstad on 06/04/2019.
//

import Foundation

/// Inputs to a transaction
public struct TransactionInput: Codable, Serializable {
    // A reference to the previous Transaction output
    public let previousOutput: TransactionOutputReference
    
    /// The raw public key
    public let publicKey: Data
    
    /// Computational Script for confirming transaction authorization, usually the sender address/pubkey
    public let signature: Data
    
    /// Coinbase transactions have no inputs, and are typically used for block rewards
    public var isCoinbase: Bool {
        get {
            return previousOutput.hash == Data() && previousOutput.index == 0
        }
    }
    
    public func serialized() -> Data {
        var data = Data()
        data += previousOutput.serialized()
        data += publicKey
        data += signature
        return data
    }
}

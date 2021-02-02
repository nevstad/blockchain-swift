//
//  Transaction.swift
//  App
//
//  Created by Magnus Nevstad on 01/04/2019.
//

import Foundation

public struct Transaction: Codable, Serializable {
    /// Transaction inputs, which are sources for coins
    public let inputs: [TransactionInput]
    
    /// Transaction outputs, which are destinations for coins
    public let outputs: [TransactionOutput]

    /// The lock time or block number
    public let lockTime: UInt32
    
    /// Transaction hash
    public var txHash: Data {
        get {
            return serialized().sha256()
        }
    }
    
    /// Transaction ID
    public var txId: String {
        return Data(txHash.reversed()).hex
    }
    
    /// Coinbase transactions have only one TransactionInput which itself has no previus output reference
    public var isCoinbase: Bool {
        get {
            return inputs.count == 1 && inputs[0].isCoinbase
        }
    }
    
    public func serialized() -> Data {
        var data = Data()
        data += inputs.flatMap { $0.serialized() }
        data += outputs.flatMap { $0.serialized() }
        data += lockTime
        return data
    }
    
    public static func coinbase(address: Data, blockValue: UInt64) -> Transaction {
        let coinbaseTxOutPoint = TransactionOutputReference(hash: Data(), index: 0)
        let coinbaseTxIn = TransactionInput(previousOutput: coinbaseTxOutPoint, publicKey: address, signature: Data())
        let txIns:[TransactionInput] = [coinbaseTxIn]
        let txOuts:[TransactionOutput] = [TransactionOutput(value: blockValue, address: address)]
        return Transaction(inputs: txIns, outputs: txOuts, lockTime: UInt32(Date().timeIntervalSince1970))
    }
}

extension Transaction: Equatable {
    public static func == (lhs: Transaction, rhs: Transaction) -> Bool {
        return lhs.txHash == rhs.txHash
    }
}

extension Transaction: CustomStringConvertible {
    public var description: String {
        let ins = "ins: \(inputs.map { $0.previousOutput.hash.readableHex }.joined(separator: ", "))"
        let outs = "outs: (\(outputs.map { "\($0.value) -> \($0.address.readableHex)" }.joined(separator: ", ")))"
        return "Transaction (id: \(Data(txHash.reversed()).readableHex), \(ins), \(outs))"
    }
}

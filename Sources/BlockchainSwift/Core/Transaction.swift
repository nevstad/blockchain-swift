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
    
    /// Transaction hash
    public var txHash: Data {
        get {
            return self.serialized().sha256()
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
        return data
    }
    
    public static func coinbase(address: Data, blockValue: UInt64) -> Transaction {
        let coinbaseTxOutPoint = TransactionOutPoint(hash: Data(), index: 0)
        let coinbaseTxIn = TransactionInput(previousOutput: coinbaseTxOutPoint, publicKey: address, signature: Data())
        let txIns:[TransactionInput] = [coinbaseTxIn]
        let txOuts:[TransactionOutput] = [TransactionOutput(value: blockValue, address: address)]
        return Transaction(inputs: txIns, outputs: txOuts)
    }
}

extension Transaction: Equatable {
    public static func == (lhs: Transaction, rhs: Transaction) -> Bool {
        return lhs.txHash == rhs.txHash
    }
}

extension Transaction: CustomStringConvertible {
    public var description: String {
//        let encoder = JSONEncoder()
//        encoder.outputFormatting = .prettyPrinted
//        return String(data: try! encoder.encode(self), encoding: .utf8)!
        let ins = "ins: \(inputs.map { $0.previousOutput.hash.hex }.joined(separator: ", "))"
        let outs = "outs: (\(outputs.map { "\($0.value) -> \($0.address.hex)" }.joined(separator: ", ")))"
        return "TX(id: \(txId), \(ins), \(outs))"
    }
}

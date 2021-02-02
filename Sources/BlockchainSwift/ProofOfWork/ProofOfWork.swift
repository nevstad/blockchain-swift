//
//  Crypto.swift
//  App
//
//  Created by Magnus Nevstad on 01/04/2019.
//

import Foundation

public struct ProofOfWork: Codable {
    
    public struct Difficulty: Codable {
        let level: UInt32
        private let prefix: String

        init(level: UInt32) {
            self.level = level
            self.prefix = (1...level).map { _ in "0" }.reduce("", +)
        }
        
        /// Validate a hash String if it has `difficulty` number of leading "0"
        func validate(hash: Data) -> Bool {
            return hash.hex.hasPrefix(prefix)
        }
    }
    
    /// Difficulty determines the level of difficulty of the PoW Algorithm
    private let difficulty: Difficulty

    
    public init(difficulty: UInt32) {
        self.difficulty = Difficulty(level: difficulty)
    }
    
    /// Simple Proof of Work Algorithm, based on HashCash/Bitcoin
    /// - Parameters
    ///     - prevHash: The previous block's hash
    ///     - timestamp: The block's creation timestamp
    ///     - transactions: The transactions to add to the block
    /// - Returns: A valid SHA-256 hash & nonce after success, invalid SHA-256 hash & nonce if unsuccessful avter Int.max tries
    public func work(prevHash: Data, timestamp: UInt32, transactions: [Transaction]) -> (hash: Data, nonce: UInt32) {
        var nonce: UInt32 = 0
        var hash = Block(timestamp: timestamp, transactions: transactions, nonce: nonce, hash: Data(), previousHash: prevHash).serialized().sha256()
        while nonce < Int.max {
            if validate(hash: hash) {
                break
            }
            nonce += 1
            hash = Block(timestamp: timestamp, transactions: transactions, nonce: nonce, hash: Data(), previousHash: prevHash).serialized().sha256()
        }
        return (hash: hash, nonce: nonce)
    }
    
    /// Validates that a block was mined correctly according to the PoW Algorithm
    /// - SHA-256 Hashing this block's data should produce a valid PoW hash
    /// - Parameter block: The Block to validate
    /// - Returns: `true` if the block is valid, ie. PoW completed
    public func validate(block: Block, previousHash: Data) -> Bool {
        return validate(hash: block.serialized().sha256())
    }
    
    /// Validates that a hash has passed the requirement of the correct number of starting 0s
    public func validate(hash: Data) -> Bool {
        return difficulty.validate(hash: hash)
    }
}

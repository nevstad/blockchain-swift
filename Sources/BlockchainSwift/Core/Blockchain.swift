//
//  Blockchain.swift
//  App
//
//  Created by Magnus Nevstad on 01/04/2019.
//

import Foundation

public class Blockchain {
    // Coin specifics, stolen from Bitcoin
    public enum Coin {
        static let satoshis: UInt64 = 100_000_000
        static let subsidy = satoshis / 100
        static let halvingInterval: UInt64 = 210_000
        
        /// Get the block value, or the block reward, at a specified block height
        /// - Parameter blockHeight: The block height (number of blocks)
        static func blockReward(at blockHeight: UInt64) -> UInt64 {
            let halvings = blockHeight / halvingInterval
            return subsidy / (1 + halvings)
        }
        
        static func coinValue(satoshis: UInt64) -> Double {
            return Double(satoshis) / Double(Coin.satoshis)
        }
        
        static func satoshisValue(coinValue: Double) -> UInt64 {
            return UInt64(coinValue * Double(Blockchain.Coin.satoshis))
        }
    }
    
    /// The blockchain
    let blockStore: BlockStore = SQLiteBlockStore()
    
    /// Proof of Work Algorithm
    public var pow = ProofOfWork(difficulty: 3)
    
    
    /// Returns the last block in the blockchain. Fatal error if we have no blocks.
    public func latestBlockHash() -> Data {
        return try! blockStore.latestBlockHash() ?? Data()
    }
    
    /// Get the block value, or the block reward, at current block height
    public func currentBlockValue() -> UInt64 {
        return Coin.blockReward(at: UInt64(try! blockStore.blockHeight()))
    }
    
    public func currentBlockHeight() -> Int {
        return try! blockStore.blockHeight()
    }
    
    /// Create a new block in the chain
    /// - Parameter nonce: The Block nonce after successful PoW
    /// - Parameter hash: The Block hash after successful PoW
    /// - Parameter previousHash: The hash of the previous Block
    /// - Parameter timestamp: The timestamp for when the Block was mined
    /// - Parameter transactions: The transactions in the Block
    @discardableResult
    public func createBlock(nonce: UInt32, hash: Data, previousHash: Data, timestamp: UInt32, transactions: [Transaction]) -> Block {
        let block = Block(timestamp: timestamp, transactions: transactions, nonce: nonce, hash: hash, previousHash: previousHash)
        try! blockStore.addBlock(block)
        return block
    }
    
    /// Returns the balannce for a specified address, defined by the sum of its unspent outputs
    /// - Parameter address: The wallet address whose balance to find
    public func balance(for address: Data) -> UInt64 {
        return try! blockStore.balance(for: address)
    }
    
    /// Finds UTXOs for a specified address
    /// - Parameter address: The wallet address whose UTXOs we want to find
    public func findSpendableOutputs(for address: Data) -> [UnspentTransaction] {
        return try! blockStore.unspentTransactions(for: address)
    }
    
    /// Returns the Transaction history for a specified address
    /// - Parameter address: The specifed address
    public func findTransactions(for address: Data) -> [Payment] {
        return try! blockStore.payments(address: address)
    }

    /// Calculates the circulating supply
    /// - At any given block height, the circulating supply is given by the sum of all black rewards up to, and including, that point
    public func circulatingSupply() -> UInt64 {
        let blockHeight = UInt64(try! blockStore.blockHeight())
        if blockHeight == 0 {
            return 0
        }
        return (1...blockHeight)
            .map { Coin.blockReward(at: $0-1) }
            .reduce(0, +)
    }
}

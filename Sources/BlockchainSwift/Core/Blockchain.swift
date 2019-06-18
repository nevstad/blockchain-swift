//
//  Blockchain.swift
//  App
//
//  Created by Magnus Nevstad on 01/04/2019.
//

import Foundation

public class Blockchain: Codable {
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
    
    enum CodingKeys: String, CodingKey {
        case pow
        case utxos
    }
    
    /// The blockchain
    private var blockStore = BlockStore()
    
    var blocks: [Block] {
        return try! blockStore.blocks()
    }
    
    /// Proof of Work Algorithm
    public var pow = ProofOfWork(difficulty: 3)
    
    /// Unspent Transaction Outputs
    /// - This class keeps track off all current UTXOs, providing a quick lookup for balances and creating new transactions.
    /// - For now, any transaction must use all available utxos for that address, meaning we have an easier job of things.
    public var utxos = [UnspentTransaction]()

    
    /// Returns the last block in the blockchain. Fatal error if we have no blocks.
    public func lastBlockHash() -> Data {
        return try! blockStore.latestBlockHash()
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
        updateSpendableOutputs(with: block)
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
    
    /// Updates UTXOs when a new block is added
    /// - Parameter block: The block that has been added, whose transactions we must go through to find the new UTXO state
    public func updateSpendableOutputs(with block: Block) {
        for transaction in block.transactions {
            updateSpendableOutputs(with: transaction)
        }
    }
    
    /// Updates UTXOs when a new block is added
    /// - Parameter transactions: The new transactions we must go through to find the new UTXO state
    public func updateSpendableOutputs(with transaction: Transaction) {
        // Because we update UTXOs when creating unmined transactions (and thereby have a different UTXO state
        // than the rest of the network), we have to exclude these transactions whose output references are already used
        guard !utxos.map({ $0.outpoint.hash }).contains(transaction.txHash) else { return }
        
        // For non-Coinbase transaction we must remove UTXOs that reference this transaction's inputs
        if !transaction.isCoinbase {
            // TODO remove
            transaction.inputs.map { $0.previousOutput }.forEach { prevOut in
                utxos = utxos.filter { $0.outpoint != prevOut }
            }
            transaction.inputs.forEach { txIn in
                try! blockStore.spend(txIn)
            }
        }
        
        // For all transaction outputs we create a new UTXO
        for (index, output) in transaction.outputs.enumerated() {
            let outputReference = TransactionOutputReference(hash: transaction.txHash, index: UInt32(index))
            let unspentTransaction = UnspentTransaction(output: output, outpoint: outputReference)
            try! blockStore.addUnspentTransaction(unspentTransaction)
            // TODO remove
            utxos.append(unspentTransaction)
        }
    }

    /// Returns the Transaction history for a specified address
    /// - Parameter address: The specifed address
    public func findTransactions(for address: Data) -> [Payment] {
        return try! blockStore.transactions(address: address)
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

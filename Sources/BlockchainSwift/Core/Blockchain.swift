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
        static let satosis: UInt64 = 100_000_000
        static let subsidy = 50 * satosis
        static let halvingInterval: UInt64 = 210_000
        
        /// Get the block value, or the block reward, at a specified block height
        /// - Parameter blockHeight: The block height (number of blocks)
        static func blockReward(at blockHeight: UInt64) -> UInt64 {
            let halvings = blockHeight / halvingInterval
            return subsidy / (1 + halvings)
        }
    }
    
    /// The blockchain
    public private(set) var blocks: [Block] = []
    
    /// Proof of Work Algorithm
    public private(set) var pow = ProofOfWork(difficulty: 3)
    
    /// Unspent Transaction Outputs
    /// - This class keeps track off all current UTXOs, providing a quick lookup for balances and creating new transactions.
    /// - For now, any transaction must use all available utxos for that address, meaning we have an easier job of things.
    private var utxos = [TransactionOutput]()

    
    /// Returns the last block in the blockchain. Fatal error if we have no blocks.
    public func lastBlockHash() -> Data {
        return self.blocks.last?.hash ?? Data()
    }
    
    /// Get the block value, or the block reward, at current block height
    public func currentBlockValue() -> UInt64 {
        return Coin.blockReward(at: UInt64(self.blocks.count))
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
        self.blocks.append(block)
        self.updateSpendableOutputs(with: block)
        return block
    }
    
    /// Finds UTXOs for a specified address
    /// - Parameter address: The wallet address whose UTXOs we want to find
    public func findSpendableOutputs(for address: Data) -> [TransactionOutput] {
        return self.utxos.filter({ $0.address == address })
    }
    
    /// Updates UTXOs when a new block is added
    /// - Parameter block: The block that has been added, whose transactions we must go through to find the nes UTXO state
    public func updateSpendableOutputs(with block: Block) {
        let spentOutputs = block.transactions.flatMap { $0.inputs.map { $0.previousOutput } }
        for spentTxOut in spentOutputs {
            self.utxos.removeAll { (txOut) -> Bool in
                txOut.hash == spentTxOut.hash
            }
        }
        self.utxos.append(contentsOf: block.transactions.flatMap({ $0.outputs }))
    }
    
    /// Returns the balannce for a specified address, defined by the sum of its unspent outputs
    /// - Parameter address: The wallet address whose balance to find
    public func balance(for address: Data) -> UInt64 {
        return findSpendableOutputs(for: address).map { $0.value }.reduce(0, +)
    }

    /// Finds a transaction by id, iterating through every block (to optimize this, look into Merkle trees).
    /// - Parameter txHash: The Transaction hash
    public func findTransaction(txHash: Data) -> Transaction? {
        for block in self.blocks {
            for transaction in block.transactions {
                if transaction.txHash == txHash {
                    return transaction
                }
            }
        }
        return nil
    }
    
}

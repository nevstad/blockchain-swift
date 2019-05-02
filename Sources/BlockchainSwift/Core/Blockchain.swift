//
//  Blockchain.swift
//  App
//
//  Created by Magnus Nevstad on 01/04/2019.
//

import Foundation
import os.log

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
    }
    
    /// The blockchain
    public private(set) var blocks: [Block] = []
    
    /// Proof of Work Algorithm
    public private(set) var pow = ProofOfWork(difficulty: 3)
    
    /// Unspent Transaction Outputs
    /// - This class keeps track off all current UTXOs, providing a quick lookup for balances and creating new transactions.
    /// - For now, any transaction must use all available utxos for that address, meaning we have an easier job of things.
    public var utxos = [UnspentTransaction]()

    
    /// Returns the last block in the blockchain. Fatal error if we have no blocks.
    public func lastBlockHash() -> Data {
        return blocks.last?.hash ?? Data()
    }
    
    /// Get the block value, or the block reward, at current block height
    public func currentBlockValue() -> UInt64 {
        return Coin.blockReward(at: UInt64(blocks.count))
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
        blocks.append(block)
        updateSpendableOutputs(with: block)
        return block
    }
    
    /// Finds UTXOs for a specified address
    /// - Parameter address: The wallet address whose UTXOs we want to find
    public func findSpendableOutputs(for address: Data) -> [UnspentTransaction] {
        return utxos.filter({ $0.output.address == address })
    }
    
    /// Updates UTXOs when a new block is added
    /// - Parameter block: The block that has been added, whose transactions we must go through to find the new UTXO state
    public func updateSpendableOutputs(with block: Block) {
        os_log("pre: %s", type: .debug, utxos.debugDescription)
        for transaction in block.transactions {
            updateSpendableOutputs(with: transaction)
        }
        os_log("post: %s", type: .debug, utxos.debugDescription)
    }
    
    /// Updates UTXOs when a new block is added
    /// - Parameter transactions: The new transactions we must go through to find the new UTXO state
    public func updateSpendableOutputs(with transaction: Transaction) {
        // Because we update UTXOs when creating unmined transactions (and thereby have a different UTXO state
        // than the rest of the network), we have to exclude thesetransactions whose output references are already used
        guard !utxos.map({ $0.outpoint.hash }).contains(transaction.txHash) else { return }
        
        // For non-Coinbase transaction we must remove UTXOs that reference this transactions inputs
        if !transaction.isCoinbase {
            transaction.inputs.map { $0.previousOutput }.forEach { prevOut in
                utxos = utxos.filter { $0.outpoint != prevOut }
            }
        }
        // For all transaction outputs we create a new UTXO
        for (index, output) in transaction.outputs.enumerated() {
            let outputReference = TransactionOutputReference(hash: transaction.txHash, index: UInt32(index))
            let unspentTransaction = UnspentTransaction(output: output, outpoint: outputReference)
            utxos.append(unspentTransaction)
        }
    }
    
    /// Returns the balannce for a specified address, defined by the sum of its unspent outputs
    /// - Parameter address: The wallet address whose balance to find
    public func balance(for address: Data) -> UInt64 {
        return findSpendableOutputs(for: address).map { $0.output.value }.reduce(0, +)
    }

    /// Finds a transaction by id, iterating through every block (to optimize this, look into Merkle trees).
    /// - Parameter txHash: The Transaction hash
    public func findTransaction(txHash: Data) -> Transaction? {
        for block in blocks {
            for transaction in block.transactions {
                if transaction.txHash == txHash {
                    return transaction
                }
            }
        }
        return nil
    }

    /// Returns the Transaction history for a specified address
    /// - Parameter address: The specifed address
    public func findTransactions(for address: Data) -> (sent: [Transaction], received: [Transaction]) {
        var sent: [Transaction] = []
        var received: [Transaction] = []
        for block in blocks {
            for transaction in block.transactions {
                let summary = transaction.summary()
                if summary.from == address {
                    sent.append(transaction)
                } else if summary.to == address {
                    received.append(transaction)
                }
            }
        }
        return (sent: sent, received: received)
    }

}

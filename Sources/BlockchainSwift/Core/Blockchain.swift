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

    /// Transaction error types
    public enum TxError: Error {
        case invalidValue
        case insufficientBalance
        case unverifiedTransaction
    }
    
    /// The blockchain
    public private(set) var chain: [Block] = []
    
    /// Proof of Work Algorithm
    public private(set) var pow = ProofOfWork(difficulty: 3)
    
    /// Transation pool holds all transactions to go into the next block
    public private(set) var mempool = [Transaction]()
    
    /// Unspent Transaction Outputs
    /// - This class keeps track off all current UTXOs, providing a quick lookup for balances and creating new transactions.
    /// - For now, any transaction will use all available utxos for that address, meaning we have an easier job of things.
    /// - Also, since we have no decentralization, we don't have to worry about reloading this based on the current blockchain whenver we have to sync blocks with other nodes.
    public private(set) var utxos = [TransactionOutput]()

    /// Explicitly define Codable properties
    private enum CodingKeys: CodingKey {
        case mempool
        case chain
    }
    

    /// Initialises our blockchain with a genesis block
    public init(minerAddress: Data) {
        mineGenesisBlock(minerAddress: minerAddress)
    }
    
    /// Creates a coinbase transaction
    /// - Parameter address: The miner's address to be awarded a block reward
    /// - Returns: The index of the block to whitch this transaction will be added
    @discardableResult
    private func createCoinbaseTransaction(for address: Data) -> Int {
        // Generate a coinbase tx to reward block miner
        let coinbaseTx = Transaction.coinbase(address: address, blockValue: currentBlockValue())
        self.mempool.append(coinbaseTx)
        self.utxos.append(contentsOf: coinbaseTx.outputs)
        return self.chain.count + 1
    }
    
    /// Create a transaction to be added to the next block.
    /// - Parameters:
    ///     - sender: The sender
    ///     - recipient: The recipient
    ///     - value: The value to transact
    /// - Returns: The index of the block to whitch this transaction will be added
    @discardableResult
    public func createTransaction(sender: Wallet, recipientAddress: Data, value: UInt64) throws -> Int {
        // You cannot send nothing
        if value == 0 {
            throw TxError.invalidValue
        }
        
        // Calculate transaction value and change, based on the sender's balance and the transaction's value
        // - All utxos for the sender must be spent, and are indivisible.
        let balance = self.balance(for: sender.address)
        if value > balance {
            throw TxError.insufficientBalance
        }
        let change = balance - value

        // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
        let spendableOutputs = self.utxos.filter { $0.address == sender.address }
        guard let signedTxIns = try? sender.sign(utxos: spendableOutputs) else { return -1 }
        for (i, txIn) in signedTxIns.enumerated() {
            let originalOutputData = spendableOutputs[i].serialized().sha256()
            if !ECDSA.verify(publicKey: sender.publicKey, data: originalOutputData, signature: txIn.signature) {
                throw TxError.unverifiedTransaction
            }
        }
        
        // Add transaction to the pool
        let txOuts = [
            TransactionOutput(value: value, address: recipientAddress),
            TransactionOutput(value: change, address: sender.address)
        ]
        self.mempool.append(Transaction(inputs: signedTxIns, outputs: txOuts))
        
        // All spendable outputs for sender must be spent, and all outputs added
        self.utxos.removeAll { $0.address == sender.address }
        self.utxos.append(contentsOf: txOuts)
        
        return self.chain.count + 1
    }
    
    /// Finds a transaction by id, iterating through every block (to optimize this, look into Merkle trees).
    /// - Parameter txId: The txId
    public func findTransaction(txId: String) -> Transaction? {
        for block in chain {
            for transaction in block.transactions {
                if transaction.txId == txId {
                    return transaction
                }
            }
        }
        return nil
    }
    
    /// Create a new block in the chain, adding transactions curently in the mempool to the block
    /// - Parameter proof: The proof of the PoW
    @discardableResult
    public func createBlock(nonce: UInt32, hash: Data, previousHash: Data, timestamp: UInt32, transactions: [Transaction]) -> Block {
        let block = Block(timestamp: timestamp, transactions: transactions, nonce: nonce, hash: hash, previousHash: previousHash)
        self.chain.append(block)
        return block
    }
    
    /// Mines our genesis block placing circulating supply in the reward pool,
    /// and awarding the first block to Magnus
    @discardableResult
    private func mineGenesisBlock(minerAddress: Data) -> Block {
        return mineBlock(previousHash: Data(), minerAddress: minerAddress)
    }

    /// Mines the next block using Proof of Work
    /// - Parameter recipient: The miners address for block reward
    public func mineBlock(previousHash: Data, minerAddress: Data) -> Block {
        // Generate a coinbase tx to reward block miner
        createCoinbaseTransaction(for: minerAddress)

        // Do Proof of Work to mine block with all currently registered transactions, the create our block
        let transactions = mempool
        mempool.removeAll()
        let timestamp = UInt32(Date().timeIntervalSince1970)
        let proof = pow.work(prevHash: previousHash, timestamp: timestamp, transactions: transactions)
        return createBlock(nonce: proof.nonce, hash: proof.hash, previousHash: previousHash, timestamp: timestamp, transactions: transactions)
    }
    
    /// Returns the last block in the blockchain. Fatal error if we have no blocks.
    public func lastBlock() -> Block {
        guard let last = chain.last else {
            fatalError("Blockchain needs at least a genesis block!")
        }
        return last
    }
    
    /// Get the block value, or the block reward, at current block height
    public func currentBlockValue() -> UInt64 {
        return Coin.blockReward(at: UInt64(self.chain.count))
    }
    
    /// Returns the balannce for a specified address, defined by the sum of its unspent outputs
    public func balance(for address: Data) -> UInt64 {
        var balance: UInt64 = 0
        for output in utxos.filter({ $0.address == address }) {
            balance += output.value
        }
        return balance
    }
}

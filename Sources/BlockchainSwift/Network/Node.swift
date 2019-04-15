//
//  NodeProtocol.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 11/04/2019.
//

import Foundation

/// In our simplistic network, we have _one_ central Node, with an arbitrary amount of Miners and Wallets.
/// - Central: The hub which all others connect to, and is responsible for syncronizing data accross them. There can only be one.
/// - Miner: Stores new transactions in a mempool, and will put them into blocks once mined. Needs to store the entire chainstate.
/// - Wallet: Sends coins between wallets, and (unlike Bitcoins optimized SPV nodes) needs to store the entire chainstate.
public class Node {
    
    /// Version lets us make sure all nodes run the same version of the blockchain
    public let version: Int = 1
    
    /// Our address in the Node network
    public let address: NodeAddress
    
    /// Our network of nodes
    public var knownNodes = [NodeAddress]()
    public func knownNodes(except: [NodeAddress]) -> [NodeAddress] {
        var nodes = knownNodes
        except.forEach { exception in
            nodes.removeAll(where: { $0 == exception })
        }
        return nodes
    }

    /// Local copy of the blockchain
    public let blockchain: Blockchain
    
    /// Transaction pool holds all transactions to go into the next block
    public var mempool = [Transaction]()

    // The wallet associated with this Node
    public let wallet: Wallet
    
    /// Network IO
    var client: NodeClient
    let server: NodeServer

    /// Transaction error types
    public enum TxError: Error {
        case invalidValue
        case insufficientBalance
        case unverifiedTransaction
    }
    
    /// Create a new Node
    /// - Parameter address: This Node's address
    /// - Parameter wallet: This Node's wallet, created if nil
    init(address: NodeAddress, wallet: Wallet? = nil) {
        self.blockchain = Blockchain()
        self.wallet = wallet ?? Wallet()!
        self.address = address
        
        // Set up client for outgoing requests
        self.client = NodeClient()
        
        // Set up server to listen on incoming requests
        self.server = NodeServer(port: UInt16(address.port)) { newState in
            print(newState)
        }
        self.server.delegate = self

        // All nodes must know of the central node, and connect to it (unless self is central node)
        let firstNodeAddr = NodeAddress.centralAddress()
        self.knownNodes.append(firstNodeAddr)
        if !self.address.isCentralNode {
            let versionMessage = VersionMessage(version: 1, blockHeight: self.blockchain.blocks.count, fromAddress: self.address)
            self.client.sendVersionMessage(versionMessage, to: firstNodeAddr)
        }
    }
    
    /// Create a transaction, sending coins
    /// - Parameters:
    ///     - recipientAddress: The recipient's Wallet address
    ///     - value: The value to transact
    public func createTransaction(recipientAddress: Data, value: UInt64) throws -> Transaction {
        if value == 0 {
            throw TxError.invalidValue
        }
        
        // Calculate transaction value and change, based on the sender's balance and the transaction's value
        // - All utxos for the sender must be spent, and are indivisible.
        let balance = self.blockchain.balance(for: self.wallet.address)
        if value > balance {
            throw TxError.insufficientBalance
        }
        let change = balance - value
        
        // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
        let spendableOutputs = self.blockchain.findSpendableOutputs(for: self.wallet.address)
        guard let signedTxIns = try? self.wallet.sign(utxos: spendableOutputs) else { throw TxError.unverifiedTransaction }
        for (i, txIn) in signedTxIns.enumerated() {
            let originalOutputData = spendableOutputs[i].hash
            if !ECDSA.verify(publicKey: self.wallet.publicKey, data: originalOutputData, signature: txIn.signature) {
                throw TxError.unverifiedTransaction
            }
        }
        
        // Create the transaction with the correct ins and outs
        let txOuts = [
            TransactionOutput(value: value, address: recipientAddress),
            TransactionOutput(value: change, address: self.wallet.address)
        ]
        let transaction = Transaction(inputs: signedTxIns, outputs: txOuts)
        // Add it to our mempool
        self.mempool.append(transaction)

        // Broadcast new transaction to network
        for node in knownNodes(except: [self.address]) {
            client.sendTransactionsMessage(TransactionsMessage(transactions: [transaction], fromAddress: self.address), to: node)
        }
        
        return transaction
    }

    /// Attempts to mine the next block, placing Transactions currently in the mempool into the new block
    public func mineBlock() -> Block? {
        // Caution: Beware of state change mid-mine, ie. new transaction or (even worse) a new block.
        //          We need to reset mining if a new block arrives, we have to remove txs from mempool that are in this new received block,
        //          and we must update utxos... When resolving conflicts, the block timestamp is relevant

        // Generate a coinbase tx to reward block miner
        let coinbaseTx = Transaction.coinbase(address: self.wallet.address, blockValue: self.blockchain.currentBlockValue())
        self.mempool.append(coinbaseTx)
    
        // TODO: Implement mining fees
        
        // Do Proof of Work to mine block with all currently registered transactions, the create our block
        let transactions = self.mempool
        let timestamp = UInt32(Date().timeIntervalSince1970)
        let previousHash = self.blockchain.lastBlockHash()
        let proof = self.blockchain.pow.work(prevHash: previousHash, timestamp: timestamp, transactions: transactions)

        // TODO: What if someone else has mined blocks and sent to us while working?

        // Create the new block
        let block = self.blockchain.createBlock(nonce: proof.nonce, hash: proof.hash, previousHash: previousHash, timestamp: timestamp, transactions: transactions)
        
        // Clear mined transactions from the mempool
        self.mempool.removeAll { (transaction) -> Bool in
            return transactions.contains(transaction)
        }
        
        // Notify nodes about new block
        for node in self.knownNodes(except: [self.address]) {
            self.client.sendBlocksMessage(BlocksMessage(blocks: [block], fromAddress: self.address), to: node)
        }
        
        return block
    }
}

/// Handle incoming messages from the Node Network
extension Node: NodeServerDelegate {
    
    public func didReceiveVersionMessage(_ message: VersionMessage) {
        let localVersion = VersionMessage(version: 1, blockHeight: self.blockchain.blocks.count, fromAddress: self.address)
        
        // Ignore nodes running a different blockchain protocol version
        guard message.version == localVersion.version else {
            print("* Node \(self.address.urlString) received invalid Version from \(message.fromAddress.urlString) (\(message.version))")
            return
        }
        print("* Node \(self.address.urlString) received version from \(message.fromAddress.urlString)")
        
        // If we (as central node) have a new node, add it to our peers
        if self.address.isCentralNode {
            if !self.knownNodes.contains(message.fromAddress) {
                self.knownNodes.append(message.fromAddress)
            }
        }
        print("\t\t- Known peers:")
        self.knownNodes.forEach { print("\t\t\t - \($0.urlString)") }
        
        // If the remote peer has a longer chain, request it's blocks starting from our latest block
        // Otherwise, if the remote peer has a shorter chain, respond with our version
        if localVersion.blockHeight < message.blockHeight  {
            print("\t\t- Remote node has longer chain, requesting blocks")
            let getBlocksMessage = GetBlocksMessage(fromBlockHash: self.blockchain.lastBlockHash(), fromAddress: self.address)
            self.client.sendGetBlocksMessage(getBlocksMessage, to: message.fromAddress)
        } else if localVersion.blockHeight > message.blockHeight {
            print("\t\t- Remote node has shorter chain, sending version")
            self.client.sendVersionMessage(localVersion, to: message.fromAddress)
        }
    }
    
    public func didReceiveTransactionsMessage(_ message: TransactionsMessage) {
        print("* Node \(self.address.urlString) received transactions from \(message.fromAddress.urlString)")

        // Verify and add transactions to blockchain
        for transaction in message.transactions {
            let verifiedInputs = transaction.inputs.filter { input in
                // TODO: Do we need to look up a local version of the output used, in order to do proper verification?
                return ECDSA.verify(publicKey: input.publicKey, data: input.previousOutput.hash, signature: input.signature)
            }
            if verifiedInputs.count == transaction.inputs.count {
                print("\t- Added transaction \(transaction)")
                self.mempool.append(transaction)
            } else {
                print("\t- Unable to verify transaction \(transaction)")
            }
        }

        // Central node is responsible for distributing the new transactions (nodes will handle verification internally)
        if self.address.isCentralNode {
            for node in knownNodes(except: [self.address, message.fromAddress])  {
                self.client.sendTransactionsMessage(message, to: node)
            }
        }
    }
    
    public func didReceiveGetBlocksMessage(_ message: GetBlocksMessage) {
        print("* Node \(self.address.urlString) received getBlocks from \(message.fromAddress.urlString)")
        if message.fromBlockHash.isEmpty {
            self.client.sendBlocksMessage(BlocksMessage(blocks: self.blockchain.blocks, fromAddress: self.address), to: message.fromAddress)
        }
        if let fromHashIndex = self.blockchain.blocks.firstIndex(where: { $0.hash == message.fromBlockHash }) {
            let requestedBlocks = Array<Block>(self.blockchain.blocks[fromHashIndex...])
            let blocksMessage = BlocksMessage(blocks: requestedBlocks, fromAddress: self.address)
            print("\t - Sending blocks message \(blocksMessage)")
            self.client.sendBlocksMessage(blocksMessage, to: message.fromAddress)
        } else {
            print("\t - Unable to generate blocks message to satisfy \(message)")
        }
    }

    public func didReceiveBlocksMessage(_ message: BlocksMessage) {
        print("* Node \(self.address.urlString) received blocks from \(message.fromAddress.urlString)")
        var validBlocks = [Block]()
        for block in message.blocks {
            if block.previousHash != self.blockchain.lastBlockHash() {
                print("\t- Uh oh, we're out of sync!")
            }
            if self.blockchain.pow.validate(block: block, previousHash: self.blockchain.lastBlockHash()) {
                self.blockchain.createBlock(nonce: block.nonce, hash: block.hash, previousHash: block.previousHash, timestamp: block.timestamp, transactions: block.transactions)
                validBlocks.append(block)
                print("\t Added block!")
            } else {
                print("\t- Unable to verify block: \(block)")
            }
        }

        // Central node is responsible for distributing the new transactions (nodes will handle verification internally)
        if self.address.isCentralNode && !validBlocks.isEmpty {
            for node in knownNodes(except: [self.address, message.fromAddress])  {
                self.client.sendBlocksMessage(message, to: node)
            }
        }
    }
}

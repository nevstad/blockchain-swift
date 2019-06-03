//
//  NodeProtocol.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 11/04/2019.
//

import Foundation
import os.log

public protocol NodeDelegate {
    func nodeDidConnectToNetwork(_ node: Node)
    func node(_ node: Node, didAddPeer: NodeAddress)
    func node(_ node: Node, didCreateTransactions transactions: [Transaction])
    func node(_ node: Node, didSendTransactions transactions: [Transaction])
    func node(_ node: Node, didReceiveTransactions transactions: [Transaction])
    func node(_ node: Node, didCreateBlocks blocks: [Block])
    func node(_ node: Node, didSendBlocks blocks: [Block])
    func node(_ node: Node, didReceiveBlocks blocks: [Block])
}

/// In our simplistic network, we have _one_ central Node, with an arbitrary amount of Miners / Wallets.
/// - Central: The hub which all others connect to, and is responsible for syncronizing data accross them. There can only be one.
/// - Miner: Stores new transactions in a mempool, and will put them into blocks once mined. Needs to store the entire chainstate.
/// - Wallet: Sends coins between wallets, and (unlike Bitcoins optimized SPV nodes) needs to store the entire chainstate.
public class Node {
    public enum NodeType: String {
        case central
        case peer
    }
    public let type: NodeType
    
    /// Version lets us make sure all nodes run the same version of the blockchain
    public let version: Int = 1
    
    /// Local copy of the blockchain
    public let blockchain: Blockchain
    
    /// Transaction pool holds all transactions to go into the next block
    public var mempool: [Transaction]
    
    /// Node network
    public var peers = [NodeAddress]()
    private var messageListener: MessageListener
    private let messageSender: MessageSender
    
    public var delegate: NodeDelegate?
    
    private var connected = false {
        didSet {
            if !oldValue {
                delegate?.nodeDidConnectToNetwork(self)
            }
        }
    }
    
    /// Transaction error types
    public enum TxError: Error {
        case sourceEqualDestination
        case invalidValue
        case insufficientBalance
        case unverifiedTransaction
    }
    
    deinit {
        messageListener.stop()
    }
    
    /// Create a new Node
    /// - Parameter address: This Node's address
    /// - Parameter wallet: This Node's wallet, created if nil
    public init(type: NodeType = .peer, blockchain: Blockchain? = nil, mempool: [Transaction]? = nil) {
        self.type = type
        self.blockchain = blockchain ?? Blockchain()
        self.mempool = mempool ?? [Transaction]()
        
        // Setup network
        let port = type == .central ? NodeAddress.centralAddress.port : NodeAddress.randomPort()
        #if os(Linux)
        messageSender = NIOMessageSender(listenPort: port)
        messageListener = NIOMessageListener(host: "localhost", port: nodePort) // hmm
        messageListener.delegate = self
        #else
        messageSender = NWConnectionMessageSender(listenPort: port)
        messageListener = NWListenerMessageListener(port: port)
        messageListener.delegate = self
        #endif

        if type == .peer {
            peers.append(NodeAddress.centralAddress)
        }
    }
    
    // Connect to the Node network by sending Version to central
    public func connect() {
        messageListener.start()
        // All nodes must know of the central node, and connect to it (unless self is central node)
        if type == .peer {
            messageSender.sendVersion(version: 1, blockHeight: self.blockchain.blocks.count, to: NodeAddress.centralAddress)
        } else {
            connected = true
        }
    }
    
    // Disconnect from the Node network
    public func disconnect() {
        // TODO: we should ideally let the network know we're down, or have pruning regularly over time of inactive peers
        messageListener.stop()
    }
    
    /// Create a transaction, sending coins
    /// - Parameters:
    ///     - recipientAddress: The recipient's Wallet address
    ///     - value: The value to transact
    @discardableResult
    public func createTransaction(sender: Wallet, recipientAddress: Data, value: UInt64) throws -> Transaction {
        if value == 0 {
            throw TxError.invalidValue
        }
        
        if recipientAddress == sender.address {
            throw TxError.sourceEqualDestination
        }
        
        // Calculate transaction value and change, based on the sender's balance and the transaction's value
        // - All utxos for the sender must be spent, and are indivisible.
        let balance = blockchain.balance(for: sender.address)
        if value > balance {
            throw TxError.insufficientBalance
        }
        
        // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
        let spendableOutputs = blockchain.findSpendableOutputs(for: sender.address)
        var usedSpendableOutputs = [UnspentTransaction]()
        var spendValue: UInt64 = 0
        for availableSpendableOutput in spendableOutputs {
            usedSpendableOutputs.append(availableSpendableOutput)
            spendValue += availableSpendableOutput.output.value
            if spendValue >= value {
                break
            }
        }
        if spendValue < value {
            os_log("Calcluated balance %d does not match sum of spendable outputs - value=%d, spendValue=%d", type: .error, balance, value, spendValue)
            throw TxError.insufficientBalance
        }
        let change = spendValue - value
        
        guard let signedTxIns = try? sender.sign(utxos: usedSpendableOutputs) else { throw TxError.unverifiedTransaction }
        for (i, txIn) in signedTxIns.enumerated() {
            let originalOutputData = usedSpendableOutputs[i].outpoint.hash
            if !Keysign.verify(publicKey: sender.publicKey, data: originalOutputData, signature: txIn.signature) {
                throw TxError.unverifiedTransaction
            }
        }
        
        // Create the transaction with the correct ins and outs
        var txOuts = [TransactionOutput]()
        txOuts.append(TransactionOutput(value: value, address: recipientAddress))
        if change > 0 {
            txOuts.append(TransactionOutput(value: change, address: sender.address))
        }
        let transaction = Transaction(inputs: signedTxIns, outputs: txOuts, lockTime: UInt32(Date().timeIntervalSince1970))
        
        // Add it to our mempool
        mempool.append(transaction)
        
        // Update our UTXOs
        // NOTE: Ideally UTXOs are updated only when a block is mined, but we have to have a way to avoid re-using UTXOs...
        blockchain.updateSpendableOutputs(with: transaction)
        
        // Inform delegate
        delegate?.node(self, didCreateTransactions: [transaction])
        
        // Broadcast new transaction to network
        for node in peers {
            messageSender.sendTransactions(transactions: [transaction], to: node)
            delegate?.node(self, didSendTransactions: [transaction])
        }
        
        return transaction
    }
    
    /// Attempts to mine the next block, placing Transactions currently in the mempool into the new block
    @discardableResult
    public func mineBlock(minerAddress: Data) -> Block? {
        // Caution: Beware of state change mid-mine, ie. new transaction or (even worse) a new block.
        //          We need to reset mining if a new block arrives, we have to remove txs from mempool that are in this new received block,
        //          and we must update utxos... When resolving conflicts, the block timestamp is relevant
        
        // Generate a coinbase tx to reward block miner
        let coinbaseTx = Transaction.coinbase(address: minerAddress, blockValue: blockchain.currentBlockValue())
        mempool.append(coinbaseTx)
        
        // TODO: Implement mining fees
        
        // Do Proof of Work to mine block with all currently registered transactions, the create our block
        let transactions = mempool
        let timestamp = UInt32(Date().timeIntervalSince1970)
        let previousHash = blockchain.lastBlockHash()
        let proof = blockchain.pow.work(prevHash: previousHash, timestamp: timestamp, transactions: transactions)
        
        // TODO: What if someone else has mined blocks and sent to us while working?
        if blockchain.lastBlockHash() != previousHash {
            os_log("Received block while mining, discarding block and clearning mined transactions")
         
            let newBlock = blockchain.blocks.last!
            mempool = mempool.filter { !newBlock.transactions.contains($0) }
            
            return nil
        }
        
        // Create the new block
        let block = blockchain.createBlock(nonce: proof.nonce, hash: proof.hash, previousHash: previousHash, timestamp: timestamp, transactions: transactions)
        // Clear mined transactions from the mempool
        mempool = mempool.filter { !block.transactions.contains($0) }
        
        delegate?.node(self, didCreateBlocks: [block])
        
        // Notify nodes about new block
        for node in peers {
            messageSender.sendBlocks(blocks: [block], to: node)
            delegate?.node(self, didSendBlocks: [block])
        }
        
        return block
    }
}

/// Handle incoming messages from the Node Network
extension Node: MessageListenerDelegate {
    public func didReceiveVersionMessage(_ message: VersionMessage, from: NodeAddress) {
        let localVersion = 1
        let localBlockHeight = blockchain.blocks.count
        
        // Ignore nodes running a different blockchain protocol version
        guard message.version == localVersion else {
            os_log("* Node received invalid Version from %s (%d)", type: .info, from.urlString, message.version)
            return
        }
        os_log("* Node received version from %s", type: .info, from.urlString)
        
        // If the remote peer has a longer chain, request it's blocks starting from our latest block
        // Otherwise, if the remote peer has a shorter chain, respond with our version
        if localBlockHeight < message.blockHeight  {
            os_log("\t\t- Remote node has longer chain, requesting blocks and transactions", type: .info)
            messageSender.sendGetBlocks(fromBlockHash: blockchain.lastBlockHash(), to: from)
            messageSender.sendGetTransactions(to: from)
        } else if localBlockHeight > message.blockHeight {
            os_log("\t\t- Remote node has shorter chain, sending version", type: .info)
            messageSender.sendVersion(version: localVersion, blockHeight: localBlockHeight, to: from)
        } else if !peers.contains(from) {
            messageSender.sendVersion(version: localVersion, blockHeight: localBlockHeight, to: from)
        }
        
        // If we have the longer chain, or same length, consider ourselves connected
        if localBlockHeight >= message.blockHeight {
            connected = true
        }
        
        if type == .central {
            if !peers.contains(from) {
                peers.append(from)
                delegate?.node(self, didAddPeer: from)
            }
        }
        os_log("\t\t- Known peers:\n%s", type: .info, peers.map{ $0.urlString }.joined(separator: ", "))
        
    }
    
    public func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage, from: NodeAddress) {
        os_log("* Node received getTransactions from %s", type: .info, from.urlString)
        messageSender.sendTransactions(transactions: mempool, to: from)
        delegate?.node(self, didSendTransactions: mempool)
    }
    
    public func didReceiveTransactionsMessage(_ message: TransactionsMessage, from: NodeAddress) {
        os_log("* Node received transactions from %s", type: .info, from.urlString)
        
        var verifiedTransactions = [Transaction]()
        // Verify and add transactions to blockchain
        for transaction in message.transactions {
            if mempool.contains(transaction) {
                os_log("\t- Ignoring duplicate transaction %s", type: .debug, transaction.txId)
                continue
            }
            let verifiedInputs = transaction.inputs.filter { input in
                // TODO: Do we need to look up a local version of the output used, in order to do proper verification?
                return Keysign.verify(publicKey: input.publicKey, data: input.previousOutput.hash, signature: input.signature)
            }
            if verifiedInputs.count == transaction.inputs.count {
                os_log("\t- Added transaction %s", type: .info, transaction.txId)
                verifiedTransactions.append(transaction)
            } else {
                os_log("\t- Unable to verify transaction %s", type: .debug, transaction.txId)
            }
        }
        
        // Add verified transactions to mempool
        mempool.append(contentsOf: verifiedTransactions)
        
        // Should we update UTXOs?
        // NOTE: Ideally UTXOs are updated only when a block is mined, but we have to have a way to avoid re-using UTXOs...
        verifiedTransactions.forEach { self.blockchain.updateSpendableOutputs(with: $0) }
        
        // Inform delegate
        delegate?.node(self, didReceiveTransactions: verifiedTransactions)
        
        // Central node is responsible for distributing the new transactions (nodes will handle verification internally)
        if type == .central {
            for node in peers.filter({ $0 != from })  {
                messageSender.sendTransactions(transactions: message.transactions, to: node)
            }
        }
    }
    
    public func didReceiveGetBlocksMessage(_ message: GetBlocksMessage, from: NodeAddress) {
        os_log("* Node received .getBlocks from %s", type: .info, from.urlString)
        if message.fromBlockHash.isEmpty {
            messageSender.sendBlocks(blocks: blockchain.blocks, to: from)
            delegate?.node(self, didSendBlocks: blockchain.blocks)
        } else if let fromHashIndex = blockchain.blocks.firstIndex(where: { $0.hash == message.fromBlockHash }) {
            let requestedBlocks = Array<Block>(blockchain.blocks[fromHashIndex...])
            messageSender.sendBlocks(blocks: requestedBlocks, to: from)
            delegate?.node(self, didSendBlocks: requestedBlocks)
        } else {
            os_log("\t - Unable to satisfy fromBlockHash=%s", type: .debug, message.fromBlockHash.hex)
        }
        
    }
    
    public func didReceiveBlocksMessage(_ message: BlocksMessage, from: NodeAddress) {
        os_log("* Node received .blocks from %s", type: .info, from.urlString)
        var validBlocks = [Block]()
        for block in message.blocks {
            if block.previousHash != blockchain.lastBlockHash() {
                os_log("\t- Received block whose previous hash doesn't match our latest block hash", type: .debug)
                continue
            }
            if blockchain.pow.validate(block: block, previousHash: blockchain.lastBlockHash()) {
                blockchain.createBlock(nonce: block.nonce, hash: block.hash, previousHash: block.previousHash, timestamp: block.timestamp, transactions: block.transactions)
                validBlocks.append(block)
                mempool.removeAll { (transaction) -> Bool in
                    return block.transactions.contains(transaction)
                }
                os_log("\t Added block!", type: .info)
            } else {
                os_log("\t- Unable to verify block: %s", type: .debug, block.hash.hex)
            }
        }
        
        delegate?.node(self, didReceiveBlocks: validBlocks)
        connected = true
        
        // Central node is responsible for distributing the new blocks (nodes will handle verification internally)
        if case .central = type {
            if !validBlocks.isEmpty {
                for node in peers.filter({ $0 != from })  {
                    messageSender.sendBlocks(blocks: message.blocks, to: node)
                }
            }
        }
    }
}

extension Node {
    public func saveState() {
        try? UserDefaults.blockchainSwift.set(blockchain, forKey: .blockchain)
        try? UserDefaults.blockchainSwift.set(mempool, forKey: .transactions)
    }
    
    public func clearState() {
        UserDefaults.blockchainSwift.clear(forKey: .blockchain)
        UserDefaults.blockchainSwift.clear(forKey: .transactions)
    }
    
    public static func loadState() -> (blockchain: Blockchain?, mempool: [Transaction]?) {
        let bc: Blockchain? = UserDefaults.blockchainSwift.get(forKey: .blockchain)
        let mp: [Transaction]? = UserDefaults.blockchainSwift.get(forKey: .transactions)
        return (blockchain: bc, mempool: mp)
    }
}

extension UserDefaults {
    public static var blockchainSwift: UserDefaults {
        return UserDefaults(suiteName: "BlockchainSwift")!
    }
    
    internal enum DataStoreKey: String {
        case blockchain, transactions, wallet
    }
    
    func set<T: Codable>(_ codable: T, forKey key: DataStoreKey) throws {
        set(try JSONEncoder().encode(codable), forKey: key.rawValue)
    }

    func get<T: Codable>(forKey key: DataStoreKey) -> T? {
        if let data = data(forKey: key.rawValue) {
            return try? JSONDecoder().decode(T.self, from: data)
        } else {
            return nil
        }
    }
    
    func clear(forKey key: DataStoreKey) {
        set(nil, forKey: key.rawValue)
    }
}

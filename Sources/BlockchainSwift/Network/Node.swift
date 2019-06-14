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
    func node(_ node: Node, didAddPeer peer: NodeAddress)
    func node(_ node: Node, didRemovePeer peer: NodeAddress)
    func node(_ node: Node, didCreateTransactions transactions: [Transaction])
    func node(_ node: Node, didSendTransactions transactions: [Transaction])
    func node(_ node: Node, didReceiveTransactions transactions: [Transaction])
    func node(_ node: Node, didCreateBlocks blocks: [Block])
    func node(_ node: Node, didSendBlocks blocks: [Block])
    func node(_ node: Node, didReceiveBlocks blocks: [Block])
}


public class Node {
    /// In our simplistic network, we have _one_ central Node, with an arbitrary amount of Miners / Wallets.
    /// - Central: The hub which all others connect to, and is responsible for syncronizing data accross them. There can only be one.
    /// - Miner: Stores new transactions in a mempool, and will put them into blocks once mined. Needs to store the entire chainstate.
    /// - Wallet: Sends coins between wallets, and (unlike Bitcoins optimized SPV nodes) needs to store the entire chainstate.
    public enum NodeType: String {
        case central
        case peer
    }
    public let type: NodeType
    
    /// Local copy of the blockchain
    public let blockchain: Blockchain
    
    /// Transaction pool holds all transactions to go into the next block
    public var mempool: [Transaction]
    
    /// Node network
    public var peers = [NodeAddress]()
    private var peersLastSeen = [NodeAddress: Date]()
    private var network: NetworkProvider
    private var peerPruneTimer: Timer?
    public static var pingInterval: TimeInterval = 10
    
    /// Delegate
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
    
    /// Mining error types
    public enum MineError: Error {
        case blockAlreadyMined
    }
    
    deinit {
        network.stop()
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
        network = NIONetwork(port: Int(port))
        network.delegate = self
        #else
        network = NWNetwork(port: port)
        network.delegate = self
        #endif
        
        if type == .peer {
            peers.append(NodeAddress.centralAddress)
        }
    }
    
    /// Connect to the Node network by sending Version to central
    public func connect() {
        network.start()
        // All nodes must know of the central node, and connect to it (unless self is central node)
        if type == .peer {
            network.sendVersion(version: 1, blockHeight: self.blockchain.blocks.count, to: NodeAddress.centralAddress)
        } else {
            connected = true
            startPeerPruningTask()
        }
    }
    
    /// Disconnect from the Node network
    public func disconnect() {
        network.stop()
        stopPeerPruningTask()
    }
    
    /// Add a known peer
    private func addPeer(_ peer: NodeAddress) {
        if !peers.contains(peer) {
            peers.append(peer)
            delegate?.node(self, didAddPeer: peer)
            os_log("Added %s to node network", type: .info, peer.urlString)
        }
    }
    
    /// Remove a known peer
    private func removePeer(_ peer: NodeAddress) {
        if peers.contains(peer) {
            peers.removeAll { $0 == peer }
            delegate?.node(self, didRemovePeer: peer)
            os_log("Removed %s from node network", type: .info, peer.urlString)
        }
    }
    
    /// Handle monitoring peers and whether they are still part of the network, pruning those that are not
    private func startPeerPruningTask() {
        peerPruneTimer = Timer.scheduledTimer(withTimeInterval: Node.pingInterval, repeats: true, block: { [weak self] (timer) in
            guard let strongSelf = self else { return }
            
            // Prune inactive peers
            for (peer, pingTime) in strongSelf.network.pingSendTimes {
                if let pongTime = strongSelf.network.pongReceiveTimes[peer] {
                    if pongTime.timeIntervalSince(pingTime) > Node.pingInterval / 2 {
                        // The latest Pong is not within the expected time since latest ping
                        strongSelf.removePeer(peer)
                    }
                } else {
                    if Date().timeIntervalSince(pingTime) > Node.pingInterval / 2 {
                        // We never received a Pong within the expected time
                        strongSelf.removePeer(peer)
                    }
                }
            }
            
            // Send ping to all active peers
            strongSelf.peers.forEach { strongSelf.network.sendPing(to: $0) }
        })
    }
    
    /// Stop the peer pruning task
    private func stopPeerPruningTask() {
        peerPruneTimer?.invalidate()
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
        
        // Notify peers about new transaction
        for node in peers {
            network.sendTransactions(transactions: [transaction], to: node)
            delegate?.node(self, didSendTransactions: [transaction])
        }
        
        return transaction
    }
    
    /// Attempts to mine the next block, placing Transactions currently in the mempool into the new block
    @discardableResult
    public func mineBlock(minerAddress: Data) throws -> Block {
        // Generate a coinbase tx to reward block miner
        let coinbaseTx = Transaction.coinbase(address: minerAddress, blockValue: blockchain.currentBlockValue())
        mempool.append(coinbaseTx)
        
        // TODO: Implement mining fees
        
        // Do Proof of Work to mine block with all currently registered transactions, the create our block
        let transactions = mempool
        let timestamp = UInt32(Date().timeIntervalSince1970)
        let previousHash = blockchain.lastBlockHash()
        let proof = blockchain.pow.work(prevHash: previousHash, timestamp: timestamp, transactions: transactions)
        
        // If someone else has mined the next block and we've received it, discard block and clear the corresponding tx from mempool
        // - Note: Despite discarding blocks when we're gotten beat to the punch, there are cases where others have mined the block
        // and sent it to other peers, but it hasn't reached us yet. This will lead to an out of sync state in the network, and we
        // do not have any conflict resolution in place.
        if blockchain.lastBlockHash() != previousHash {
            os_log("Received block while mining, discarding block and clearing mined transactions")
            let block = blockchain.blocks.last!
            mempool.removeAll { block.transactions.contains($0) }
            throw MineError.blockAlreadyMined
        }
        
        // Create the new block
        let block = blockchain.createBlock(nonce: proof.nonce, hash: proof.hash, previousHash: previousHash, timestamp: timestamp, transactions: transactions)
        // Clear mined transactions from the mempool
        mempool.removeAll { block.transactions.contains($0) }

        // Inform delegate
        delegate?.node(self, didCreateBlocks: [block])
        
        // Notify peers about new block
        for node in peers {
            network.sendBlocks(blocks: [block], to: node)
            delegate?.node(self, didSendBlocks: [block])
        }
        
        return block
    }
}

/// Handle incoming messages from the Node Network
extension Node: MessageListenerDelegate {
    public func didReceivePingMessage(_ message: PingMessage, from: NodeAddress) {}
    public func didReceivePongMessage(_ message: PongMessage, from: NodeAddress) {}
    
    public func didReceiveVersionMessage(_ message: VersionMessage, from: NodeAddress) {
        let localVersion = 1
        let localBlockHeight = blockchain.blocks.count
        
        // Ignore nodes running a different blockchain protocol version
        guard message.version == localVersion else {
            os_log("Received invalid Version from %s (v=%d)", type: .info, from.urlString, message.version)
            return
        }
        
        // If the remote peer has a longer chain, request it's blocks starting from our latest block
        // Otherwise, if the remote peer has a shorter chain, respond with our version
        if localBlockHeight < message.blockHeight  {
            os_log("Remote node has longer chain, requesting blocks and transactions", type: .info)
            network.sendGetBlocks(fromBlockHash: blockchain.lastBlockHash(), to: from)
            network.sendGetTransactions(to: from)
        } else if localBlockHeight > message.blockHeight {
            os_log("Remote node has shorter chain, sending version", type: .info)
            network.sendVersion(version: localVersion, blockHeight: localBlockHeight, to: from)
        } else if !peers.contains(from) {
            network.sendVersion(version: localVersion, blockHeight: localBlockHeight, to: from)
        }
        
        // If we have the longer chain, or same length, consider ourselves connected
        if localBlockHeight >= message.blockHeight {
            connected = true
        }
        
        // Central node is responsible for keeping track of all other nodes and dispatching messages between them
        if type == .central {
            addPeer(from)
        }
        os_log("Known peers: %s", type: .info, peers.map{ $0.urlString }.joined(separator: ", "))
    }
    
    public func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage, from: NodeAddress) {
        network.sendTransactions(transactions: mempool, to: from)
        delegate?.node(self, didSendTransactions: mempool)
    }
    
    public func didReceiveTransactionsMessage(_ message: TransactionsMessage, from: NodeAddress) {
        // Verify and add transactions to blockchain
        var verifiedTransactions = [Transaction]()
        for transaction in message.transactions {
            if mempool.contains(transaction) {
                os_log("Ignoring duplicate transaction %s", type: .debug, transaction.txId)
                continue
            }
            let verifiedInputs = transaction.inputs.filter { input in
                // TODO: Do we need to look up a local version of the output used, in order to do proper verification?
                return Keysign.verify(publicKey: input.publicKey, data: input.previousOutput.hash, signature: input.signature)
            }
            if verifiedInputs.count == transaction.inputs.count {
                os_log("Added transaction %s", type: .info, transaction.txId)
                verifiedTransactions.append(transaction)
            } else {
                os_log("Unable to verify transaction %s", type: .debug, transaction.txId)
            }
        }
        
        // Add verified transactions to mempool
        mempool.append(contentsOf: verifiedTransactions)
        
        // Update UTXOs
        // - Note: Ideally UTXOs are updated only when a block is mined, but we have to have a way to avoid re-using UTXOs
        verifiedTransactions.forEach { self.blockchain.updateSpendableOutputs(with: $0) }
        
        // Inform delegate
        delegate?.node(self, didReceiveTransactions: verifiedTransactions)
        
        // Central node is responsible for distributing the new transactions (nodes will handle verification internally)
        if type == .central {
            for node in peers.filter({ $0 != from })  {
                network.sendTransactions(transactions: message.transactions, to: node)
            }
        }
    }
    
    public func didReceiveGetBlocksMessage(_ message: GetBlocksMessage, from: NodeAddress) {
        if message.fromBlockHash.isEmpty {
            network.sendBlocks(blocks: blockchain.blocks, to: from)
            delegate?.node(self, didSendBlocks: blockchain.blocks)
        } else if let fromHashIndex = blockchain.blocks.firstIndex(where: { $0.hash == message.fromBlockHash }) {
            let requestedBlocks = Array<Block>(blockchain.blocks[fromHashIndex...])
            network.sendBlocks(blocks: requestedBlocks, to: from)
            delegate?.node(self, didSendBlocks: requestedBlocks)
        } else {
            os_log("Unable to satisfy fromBlockHash=%s", type: .debug, message.fromBlockHash.hex)
        }
        
    }
    
    public func didReceiveBlocksMessage(_ message: BlocksMessage, from: NodeAddress) {
        var validBlocks = [Block]()
        for block in message.blocks {
            if block.previousHash != blockchain.lastBlockHash() {
                os_log("Received block whose previous hash doesn't match our latest block hash", type: .debug)
                continue
            }
            if blockchain.pow.validate(block: block, previousHash: blockchain.lastBlockHash()) {
                blockchain.createBlock(nonce: block.nonce, hash: block.hash, previousHash: block.previousHash, timestamp: block.timestamp, transactions: block.transactions)
                validBlocks.append(block)
                mempool.removeAll { (transaction) -> Bool in
                    return block.transactions.contains(transaction)
                }
                os_log("Added block!", type: .info)
            } else {
                os_log("Unable to verify block: %s", type: .debug, block.hash.hex)
            }
        }
        
        delegate?.node(self, didReceiveBlocks: validBlocks)
        connected = true
        
        // Central node is responsible for distributing the new blocks (nodes will handle verification internally)
        if case .central = type {
            if !validBlocks.isEmpty {
                for node in peers.filter({ $0 != from })  {
                    network.sendBlocks(blocks: message.blocks, to: node)
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

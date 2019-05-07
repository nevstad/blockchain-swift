//
//  NodeProtocol.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 11/04/2019.
//

import Foundation
import os.log

protocol NodeDelegate {
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
    public var mempool: [Transaction]
    
    /// Node network
    var messageListener: MessageListener
    let messageSender: MessageSender
    
    var delegate: NodeDelegate?

    /// Transaction error types
    public enum TxError: Error {
        case sourceEqualDestination
        case invalidValue
        case insufficientBalance
        case unverifiedTransaction
    }
    
    /// Create a new Node
    /// - Parameter address: This Node's address
    /// - Parameter wallet: This Node's wallet, created if nil
    init(address: NodeAddress, wallet: Wallet? = nil, blockchain: Blockchain? = nil, mempool: [Transaction]? = nil) {
        self.address = address
        self.blockchain = blockchain ?? Blockchain()
        self.mempool = mempool ?? [Transaction]()
        
        // Handle outcoing connections
        messageSender = NWConnectionMessageSender()
        // Set up server to listen on incoming requests
        messageListener = NWListenerMessageListener(port: UInt16(address.port)) { newState in
            print(newState)
        }
        messageListener.delegate = self

        // All nodes must know of the central node, and connect to it (unless self is central node)
        if !self.address.isCentralNode {
            let firstNodeAddr = NodeAddress.centralAddress()
            knownNodes.append(firstNodeAddr)
            delegate?.node(self, didAddPeer: firstNodeAddr)

            let versionMessage = VersionMessage(version: 1, blockHeight: self.blockchain.blocks.count, fromAddress: self.address)
            messageSender.sendVersionMessage(versionMessage, to: firstNodeAddr)
        }
    }
    
    /// Create a transaction, sending coins
    /// - Parameters:
    ///     - recipientAddress: The recipient's Wallet address
    ///     - value: The value to transact
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
        for node in knownNodes(except: [address]) {
            messageSender.sendTransactionsMessage(TransactionsMessage(transactions: [transaction], fromAddress: address), to: node)
            delegate?.node(self, didSendTransactions: [transaction])
        }
        
        return transaction
    }

    /// Attempts to mine the next block, placing Transactions currently in the mempool into the new block
    public func mineBlock(minerAddress: Data) -> Block {
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

        // Create the new block
        let block = blockchain.createBlock(nonce: proof.nonce, hash: proof.hash, previousHash: previousHash, timestamp: timestamp, transactions: transactions)
        // Clear mined transactions from the mempool
        mempool = mempool.filter { !block.transactions.contains($0) }

        delegate?.node(self, didCreateBlocks: [block])

        // Notify nodes about new block
        for node in knownNodes(except: [address]) {
            messageSender.sendBlocksMessage(BlocksMessage(blocks: [block], fromAddress: address), to: node)
            delegate?.node(self, didSendBlocks: [block])
        }
        
        return block
    }
}

/// Handle incoming messages from the Node Network
extension Node: MessageListenerDelegate {
    public func didReceiveVersionMessage(_ message: VersionMessage) {
        let localVersion = VersionMessage(version: 1, blockHeight: blockchain.blocks.count, fromAddress: address)
        
        // Ignore nodes running a different blockchain protocol version
        guard message.version == localVersion.version else {
            os_log("* Node %s received invalid Version from %s (%d)", type: .info, address.urlString, message.fromAddress.urlString, message.version)
            return
        }
        os_log("* Node %s received version from %s", type: .info, address.urlString, message.fromAddress.urlString)
        
        // If we (as central node) have a new node, add it to our peers
        if address.isCentralNode {
            if !knownNodes.contains(message.fromAddress) {
                knownNodes.append(message.fromAddress)
                delegate?.node(self, didAddPeer: message.fromAddress)
            }
        }
        os_log("\t\t- Known peers:\n%s", type: .info, knownNodes.map { $0.urlString }.joined(separator: ","))
        
        // If the remote peer has a longer chain, request it's blocks starting from our latest block
        // Otherwise, if the remote peer has a shorter chain, respond with our version
        if localVersion.blockHeight < message.blockHeight  {
            os_log("\t\t- Remote node has longer chain, requesting blocks and transactions", type: .info)
            let getBlocksMessage = GetBlocksMessage(fromBlockHash: blockchain.lastBlockHash(), fromAddress: address)
            let getTransactionsMessage = GetTransactionsMessage(fromAddress: address)
            messageSender.sendGetBlocksMessage(getBlocksMessage, to: message.fromAddress)
            messageSender.sendGetTransactionsMessage(getTransactionsMessage, to: message.fromAddress)
        } else if localVersion.blockHeight > message.blockHeight {
            os_log("\t\t- Remote node has shorter chain, sending version", type: .info)
            messageSender.sendVersionMessage(localVersion, to: message.fromAddress)
        }
    }
    
    public func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage) {
        os_log("* Node %s received getTransactions from %s", type: .info, address.urlString, message.fromAddress.urlString)
        let transactionsMessage = TransactionsMessage(transactions: mempool, fromAddress: address)
        os_log("\t - Sending transactions message", type: .info)
        messageSender.sendTransactionsMessage(transactionsMessage, to: message.fromAddress)
        delegate?.node(self, didSendTransactions: mempool)
    }
    
    public func didReceiveTransactionsMessage(_ message: TransactionsMessage) {
        os_log("* Node %s received transactions from %s", type: .info, address.urlString, message.fromAddress.urlString)

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
        if address.isCentralNode {
            for node in knownNodes(except: [address, message.fromAddress])  {
                messageSender.sendTransactionsMessage(message, to: node)
            }
        }
    }
    
    public func didReceiveGetBlocksMessage(_ message: GetBlocksMessage) {
        os_log("* Node %s received .getBlocks from %s", type: .info, address.urlString, message.fromAddress.urlString)
        if message.fromBlockHash.isEmpty {
            messageSender.sendBlocksMessage(BlocksMessage(blocks: blockchain.blocks, fromAddress: address), to: message.fromAddress)
            delegate?.node(self, didSendBlocks: blockchain.blocks)
        } else if let fromHashIndex = blockchain.blocks.firstIndex(where: { $0.hash == message.fromBlockHash }) {
            let requestedBlocks = Array<Block>(blockchain.blocks[fromHashIndex...])
            let blocksMessage = BlocksMessage(blocks: requestedBlocks, fromAddress: address)
            os_log("\t - Sending blocks message with %d blocks", type: .info, blocksMessage.blocks.count)
            messageSender.sendBlocksMessage(blocksMessage, to: message.fromAddress)
            delegate?.node(self, didSendBlocks: requestedBlocks)
        } else {
            os_log("\t - Unable to satisfy fromBlockHash=%s", type: .debug, message.fromBlockHash.hex)
        }

    }

    public func didReceiveBlocksMessage(_ message: BlocksMessage) {
        os_log("* Node %s received .blocks from %s", type: .info, address.urlString, message.fromAddress.urlString)
        var validBlocks = [Block]()
        for block in message.blocks {
            if block.previousHash != blockchain.lastBlockHash() {
                os_log("\t- Received blocks where first block's previous hash doesn't match our latest block hash", type: .debug)
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

        // Central node is responsible for distributing the new transactions (nodes will handle verification internally)
        if address.isCentralNode && !validBlocks.isEmpty {
            for node in knownNodes(except: [address, message.fromAddress])  {
                messageSender.sendBlocksMessage(message, to: node)
            }
        }
    }
}

extension Node {
    public func saveState() {
        try? UserDefaultsBlockchainStore().save(blockchain)
        try? UserDefaultsTransactionsStore().save(mempool)
    }
    
    public func clearState() {
        UserDefaultsBlockchainStore().clear()
        UserDefaultsTransactionsStore().clear()
    }
    
    public static func loadState() -> (blockchain: Blockchain?, mempool: [Transaction]?) {
        let bc = UserDefaultsBlockchainStore().load()
        let mp = UserDefaultsTransactionsStore().load()
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
    
    internal func setData(_ data: Data?, forKey key: DataStoreKey) {
        set(data, forKey: key.rawValue)
    }
    
    internal func getData(forKey key: DataStoreKey) -> Data? {
        return data(forKey: key.rawValue)
    }
}

enum StoreError: Error {
    case loadError
    case saveError
}

protocol BlockchainStore {
    func save(_ blockchain: Blockchain) throws
    func load() -> Blockchain?
    func clear()
}

protocol TransactionsStore {
    func save(_ transactions: [Transaction]) throws
    func load() -> [Transaction]?
    func clear()
}

class UserDefaultsBlockchainStore: BlockchainStore {
    func save(_ blockchain: Blockchain) throws {
        UserDefaults.blockchainSwift.setData(try JSONEncoder().encode(blockchain), forKey: .blockchain)
    }
    
    func load() -> Blockchain? {
        if let blockchainData = UserDefaults.blockchainSwift.getData(forKey: .blockchain) {
            return try? JSONDecoder().decode(Blockchain.self, from: blockchainData)
        } else {
            return nil
        }
    }
    
    func clear() {
        UserDefaults.blockchainSwift.setData(nil, forKey: .blockchain)
    }
}

class UserDefaultsTransactionsStore: TransactionsStore {
    func save(_ transactions: [Transaction]) throws {
        UserDefaults.blockchainSwift.setData(try JSONEncoder().encode(transactions), forKey: .transactions)
    }
    
    func load() -> [Transaction]? {
        if let transactionsData = UserDefaults.blockchainSwift.getData(forKey: .transactions) {
            return try? JSONDecoder().decode([Transaction].self, from: transactionsData)
        } else {
            return nil
        }
    }

    func clear() {
        UserDefaults.blockchainSwift.setData(nil, forKey: .transactions)
    }
}

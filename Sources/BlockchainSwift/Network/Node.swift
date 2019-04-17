//
//  NodeProtocol.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 11/04/2019.
//

import Foundation

protocol NodeDelegate {
    func node(_ node: Node, didReceiveTransactions: [Transaction])
    func node(_ node: Node, didReceiveBlocks: [Block])
}

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
    public var mempool: [Transaction]

    // The wallet associated with this Node
    public let wallet: Wallet
    
    /// Listen for incoming connections
    let server: NodeServer
    
    var delegate: NodeDelegate?

    /// Transaction error types
    public enum TxError: Error {
        case invalidValue
        case insufficientBalance
        case unverifiedTransaction
    }
    
    /// Create a new Node
    /// - Parameter address: This Node's address
    /// - Parameter wallet: This Node's wallet, created if nil
    init(address: NodeAddress, wallet: Wallet? = nil, loadState: Bool = true) {
        self.address = address
        if loadState {
            let state = Node.loadState(address: address)
            self.blockchain = state.blockchain ?? Blockchain()
            self.mempool = state.mempool ?? [Transaction]()
            self.wallet = state.wallet ?? Wallet()!
        } else {
            self.blockchain = Blockchain()
            self.mempool = [Transaction]()
            self.wallet = wallet ?? Wallet()!
        }
        
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
            NodeClient().sendVersionMessage(versionMessage, to: firstNodeAddr)
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
            NodeClient().sendTransactionsMessage(TransactionsMessage(transactions: [transaction], fromAddress: self.address), to: node)
        }
        
        return transaction
    }

    /// Attempts to mine the next block, placing Transactions currently in the mempool into the new block
    public func mineBlock() -> Block {
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
            NodeClient().sendBlocksMessage(BlocksMessage(blocks: [block], fromAddress: self.address), to: node)
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
            print("\t\t- Remote node has longer chain, requesting blocks and transactions")
            let client = NodeClient()
            let getBlocksMessage = GetBlocksMessage(fromBlockHash: self.blockchain.lastBlockHash(), fromAddress: self.address)
            let getTransactionsMessage = GetTransactionsMessage(fromAddress: self.address)
            client.sendGetBlocksMessage(getBlocksMessage, to: message.fromAddress)
            client.sendGetTransactionsMessage(getTransactionsMessage, to: message.fromAddress)
        } else if localVersion.blockHeight > message.blockHeight {
            print("\t\t- Remote node has shorter chain, sending version")
            NodeClient().sendVersionMessage(localVersion, to: message.fromAddress)
        }
    }
    
    public func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage) {
        print("* Node \(self.address.urlString) received getTransactions from \(message.fromAddress.urlString)")
        let transactionsMessage = TransactionsMessage(transactions: self.mempool, fromAddress: self.address)
        print("\t - Sending transactions message \(transactionsMessage)")
        NodeClient().sendTransactionsMessage(transactionsMessage, to: message.fromAddress)
    }
    
    public func didReceiveTransactionsMessage(_ message: TransactionsMessage) {
        print("* Node \(self.address.urlString) received transactions from \(message.fromAddress.urlString)")

        var verifiedTransactions = [Transaction]()
        // Verify and add transactions to blockchain
        for transaction in message.transactions {
            if self.mempool.contains(transaction) {
                print("\t- Ignoring duplicate transaction \(transaction.txId)")
                continue
            }
            let verifiedInputs = transaction.inputs.filter { input in
                // TODO: Do we need to look up a local version of the output used, in order to do proper verification?
                return ECDSA.verify(publicKey: input.publicKey, data: input.previousOutput.hash, signature: input.signature)
            }
            if verifiedInputs.count == transaction.inputs.count {
                print("\t- Added transaction \(transaction)")
                verifiedTransactions.append(transaction)
            } else {
                print("\t- Unable to verify transaction \(transaction)")
            }
        }
        
        // Add verified transactions to mempool
        self.mempool.append(contentsOf: verifiedTransactions)
        
        // Inform delegate
        self.delegate?.node(self, didReceiveTransactions: verifiedTransactions)
        
        // Central node is responsible for distributing the new transactions (nodes will handle verification internally)
        if self.address.isCentralNode {
            for node in knownNodes(except: [self.address, message.fromAddress])  {
                NodeClient().sendTransactionsMessage(message, to: node)
            }
        }
    }
    
    public func didReceiveGetBlocksMessage(_ message: GetBlocksMessage) {
        print("* Node \(self.address.urlString) received getBlocks from \(message.fromAddress.urlString)")
        if message.fromBlockHash.isEmpty {
            NodeClient().sendBlocksMessage(BlocksMessage(blocks: self.blockchain.blocks, fromAddress: self.address), to: message.fromAddress)
        }
        if let fromHashIndex = self.blockchain.blocks.firstIndex(where: { $0.hash == message.fromBlockHash }) {
            let requestedBlocks = Array<Block>(self.blockchain.blocks[fromHashIndex...])
            let blocksMessage = BlocksMessage(blocks: requestedBlocks, fromAddress: self.address)
            print("\t - Sending blocks message \(blocksMessage)")
            NodeClient().sendBlocksMessage(blocksMessage, to: message.fromAddress)
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
        
        // Inform delegate
        self.delegate?.node(self, didReceiveBlocks: validBlocks)

        // Central node is responsible for distributing the new transactions (nodes will handle verification internally)
        if self.address.isCentralNode && !validBlocks.isEmpty {
            for node in knownNodes(except: [self.address, message.fromAddress])  {
                NodeClient().sendBlocksMessage(message, to: node)
            }
        }
    }
}

extension Node {
    public func saveState() {
        try? UserDefaultsBlockchainStore().save(self.blockchain)
        try? UserDefaultsTransactionsStore().save(self.mempool)
        try? UserDefaultsWalletStore().save(self.wallet)
    }
    
    public func clearState() {
        UserDefaultsBlockchainStore().clear()
        UserDefaultsTransactionsStore().clear()
        UserDefaultsWalletStore().clear()
    }
    
    private static func loadState(address: NodeAddress) -> (blockchain: Blockchain?, mempool: [Transaction]?, wallet: Wallet?) {
        let bc = UserDefaultsBlockchainStore().load()
        let mp = UserDefaultsTransactionsStore().load()
        let wl = UserDefaultsWalletStore().load()
        return (blockchain: bc, mempool: mp, wallet: wl)
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

protocol WalletStore {
    func save(_ wallet: Wallet) throws
    func load() -> Wallet?
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

// TODO: It is obviously a bad idea to store the private key in this insecure manner
class UserDefaultsWalletStore: WalletStore {
    enum WalletStoreError: Error {
        case saveError
    }
    func save(_ wallet: Wallet) throws {
        guard let walletData = wallet.exportPrivateKey() else { throw WalletStoreError.saveError }
        UserDefaults.blockchainSwift.setData(walletData, forKey: .wallet)
    }
    
    func load() -> Wallet? {
        guard let walletData = UserDefaults.blockchainSwift.getData(forKey: .wallet) else { return nil }
        return Wallet(privateKeyData: walletData)
    }

    func clear() {
        UserDefaults.blockchainSwift.setData(nil, forKey: .wallet)
    }
}

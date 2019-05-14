import XCTest
@testable import BlockchainSwift

final class BlockchainSwiftTests: XCTestCase {
    
    func testKeyGenAndTxSigning() {
        if let keyPair = Keygen.generateKeyPair(name: "TempPair") {
            if let pubKeyData = Keygen.copyExternalRepresentation(key: keyPair.publicKey) {
                let address = pubKeyData.sha256().sha256()
                let utxo = TransactionOutput(value: 100, address: address)
                let utxoHash = utxo.serialized().sha256()
                // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
                guard let signature1 = try? Keysign.sign(data: utxoHash, with: keyPair.privateKey) else {
                    XCTFail("Could not sign with original key")
                    return
                }
                let verified1 = Keysign.verify(publicKey: pubKeyData, data: utxoHash, signature: signature1)
                XCTAssert(verified1, "Unable to verify signature1")
            } else {
                XCTFail("Failed to restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testKeyRestoreData() {
        if let keyPair = Keygen.generateKeyPair(name: "TempPair"),
            let privKeyData = Keygen.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = Keygen.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = Keygen.generateKeyPair(name: "TempPair", privateKeyData: privKeyData),
                let restoredPrivKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
                XCTAssert(privKeyData.hex == restoredPrivKeyData.hex, "Mismatching private keys")
                XCTAssert(pubKeyData.hex == restoredPubKeyData.hex, "Mismatching public keys")
            } else {
                XCTFail("Could not restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testKeyRestoreHex() {
        if let keyPair = Keygen.generateKeyPair(name: "TempPair"),
            let privKeyData = Keygen.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = Keygen.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = Keygen.generateKeyPair(name: "TempPairRestored", privateKeyHex: privKeyData.hex),
                let restoredPrivKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
                XCTAssert(privKeyData.hex == restoredPrivKeyData.hex, "Mismatching private keys")
                XCTAssert(pubKeyData.hex == restoredPubKeyData.hex, "Mismatching public keys")
            } else {
                XCTFail("Could not restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testWalletStore() {
        let wallet = Wallet(name: "TempPair", storeInKeychain: true)!
        let duplicateWallet = Wallet(name: "TempPair")!
        let duplicateEqualToOriginal =
            wallet.secPrivateKey == duplicateWallet.secPrivateKey &&
                wallet.secPublicKey == duplicateWallet.secPublicKey &&
                wallet.publicKey == duplicateWallet.publicKey &&
                wallet.address == duplicateWallet.address
        XCTAssert(duplicateEqualToOriginal)
        let restoredKeyPair = Keygen.loadKeyPairFromKeychain(name: "TempPair")!
        Keygen.clearKeychainKeys(name: "TempPair")
        let failedRestorePair = Keygen.loadKeyPairFromKeychain(name: "TempPair")
        XCTAssert(failedRestorePair == nil)
        let restoredWallet = Wallet(name: "TempPair", keyPair: restoredKeyPair)
        let restoreEqualToOriginal =
            wallet.secPrivateKey == restoredWallet.secPrivateKey &&
            wallet.secPublicKey == restoredWallet.secPublicKey &&
            wallet.publicKey == restoredWallet.publicKey &&
            wallet.address == restoredWallet.address
        XCTAssert(restoreEqualToOriginal)
    }
    
    func testKeyRestoreAndTxSigning() {
        if let keyPair = Keygen.generateKeyPair(name: "TempPair"),
            let privKeyData = Keygen.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = Keygen.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = Keygen.generateKeyPair(name: "TempPair", privateKeyData: privKeyData),
                let restoredPrivKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = Keygen.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
                XCTAssert(privKeyData.hex == restoredPrivKeyData.hex, "Mismatching private keys")
                XCTAssert(pubKeyData.hex == restoredPubKeyData.hex, "Mismatching public keys")
                
                let address = pubKeyData.sha256().sha256()
                let restoredAddress = restoredPubKeyData.sha256().sha256()
                XCTAssert(address == restoredAddress, "Mismatching addresses")
                
                let utxo = TransactionOutput(value: 100, address: address)
                let utxoHash = utxo.serialized().sha256()
                
                // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
                guard let signature = try? Keysign.sign(data: utxoHash, with: keyPair.privateKey) else {
                    XCTFail("Could not sign with original key")
                    return
                }
                guard let restoredSignature = try? Keysign.sign(data: utxoHash, with: restoredKeyPair.privateKey) else {
                    XCTFail("Could not sign with restored key")
                    return
                }
                let verified1 = Keysign.verify(publicKey: pubKeyData, data: utxoHash, signature: signature)
                let verified2 = Keysign.verify(publicKey: pubKeyData, data: utxoHash, signature: restoredSignature)
                let verified3 = Keysign.verify(publicKey: restoredPubKeyData, data: utxoHash, signature: restoredSignature)
                let verified4 = Keysign.verify(publicKey: restoredPubKeyData, data: utxoHash, signature: signature)
                XCTAssert(verified1 && verified2 && verified3 && verified4, "Original and restored keys are not fully interoperable")
            } else {
                XCTFail("Could not restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testWalletTxSigning() throws {
        let wallet1 = Wallet(name: "Wallet 1")!
        let wallet2 = Wallet(name: "Wallet 2")!
        
        let tx = Transaction.coinbase(address: wallet1.address, blockValue: 1)
        // Wallet 2 will try to steal all of Wallet 1's balance, which is here set to 100
        let wallet1utxo = UnspentTransaction(output: tx.outputs.first!, outpoint: TransactionOutputReference(hash: tx.txHash, index: 0))
        let originalOutputData = wallet1utxo.outpoint.hash

        // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
        let signature1 = try wallet1.sign(utxo: wallet1utxo)
        let signature2 = try wallet2.sign(utxo: wallet1utxo)
        let verified1 = Keysign.verify(publicKey: wallet1.publicKey, data: originalOutputData, signature: signature1)
        let verified2 = Keysign.verify(publicKey: wallet1.publicKey, data: originalOutputData, signature: signature2)
        XCTAssert(verified1, "Wallet1 should have been verified")
        XCTAssert(!verified2, "Wallet2 should not have been verified")
    }
    
    func testTransactions() throws {
        // Two wallets, one blockchain
        let node1Wallet = Wallet(name: "Node1Wallet")!
        let node1 = Node(address: NodeAddress.centralAddress())
        let node2Wallet = Wallet(name: "Node2Wallet")!
        let node2 = Node(address: NodeAddress(host: "localhost", port: 1337))
        let _ = node1.mineBlock(minerAddress: node1Wallet.address)
        
        // Wallet1 has mined genesis block, and should have gotten the reward
        XCTAssert(node1.blockchain.balance(for: node1Wallet.address) == node1.blockchain.currentBlockValue())
        // Wallet2 is broke
        XCTAssert(node1.blockchain.balance(for: node2Wallet.address) == 0)
        
        // Send 1000 from Wallet1 to Wallet2, and again let wallet1 mine the next block
        let _ = try node1.createTransaction(sender: node1Wallet, recipientAddress: node2Wallet.address, value: 1)
        XCTAssert(node1.mempool.count == 1) // One Tx should be in the pool, ready to go into the next block when mined
        let _ = node1.mineBlock(minerAddress: node1Wallet.address)
        XCTAssert(node1.mempool.count == 0) // Tx pool should now be clear
        
        // Wallet1 should now have a balance == two block rewards - 1000
        let node1Balance = node1.blockchain.balance(for: node1Wallet.address)
        let expetedNode1Balance = (node1.blockchain.currentBlockValue() * 2) - 1
        XCTAssert(node1Balance == expetedNode1Balance, "\(node1Balance) != \(expetedNode1Balance)")
        // Wallet 2 should have a balance == 1000
        let node2Balance = node1.blockchain.balance(for: node2Wallet.address)
        let expectedNode2Balance = 1
        XCTAssert(node2Balance == expectedNode2Balance, "\(node2Balance) != \(expectedNode2Balance)")
        
        // Attempt to send more from Wallet1 than it currently has, expect failure
        do {
            let _ = try node1.createTransaction(sender: node1Wallet, recipientAddress: node2Wallet.address, value: UInt64.max)
            XCTAssert(false, "Overdraft")
        } catch { }
        
        // Check sanity of utxo state, ensuring Wallet1 and Wallet2 has rights to their unspent outputs
        let utxosWallet1 = node1.blockchain.findSpendableOutputs(for: node1Wallet.address)
        let utxosWallet2 = node1.blockchain.findSpendableOutputs(for: node2Wallet.address)
        XCTAssert(node1Wallet.canUnlock(utxos: utxosWallet1.map { $0.output }))
        XCTAssert(!node1Wallet.canUnlock(utxos: utxosWallet2.map { $0.output }))
        XCTAssert(node2Wallet.canUnlock(utxos: utxosWallet2.map { $0.output }))
        XCTAssert(!node2Wallet.canUnlock(utxos: utxosWallet1.map { $0.output }))
    }
    
    func testNodeNetwork() {
        // Set up our network of 3 nodes, and letting the first node mine the genesis block
        // Excpect the genesis block to propagate to all nodes
        let initialSync = XCTestExpectation(description: "Initial sync")
        let node1Wallet = Wallet(name: "Node1Wallet")!
        let node1 = Node(address: NodeAddress.centralAddress())
        let _ = node1.mineBlock(minerAddress: node1Wallet.address)
        let node2Wallet = Wallet(name: "Node2Wallet")!
        let node2 = Node(address: NodeAddress(host: "localhost", port: 1337))
        let node3 = Node(address: NodeAddress(host: "localhost", port: 7331))
        DispatchQueue.global().async {
            while true {
                if node2.blockchain.blocks.count == 1 && node3.blockchain.blocks.count == 1 {
                    initialSync.fulfill()
                    break
                }
            }
        }
        wait(for: [initialSync], timeout: 3)
        
        // Now create a transaction on node1 - from node1's wallet to node'2s wallet
        // Expect everyone's mempool to update with the new transaction
        let txSync = XCTestExpectation(description: "Sync transactions")
        do {
            let _ = try node1.createTransaction(sender: node1Wallet, recipientAddress: node2Wallet.address, value: 1)
        } catch {
            XCTFail("Overdraft")
        }
        DispatchQueue.global().async {
            while true {
                let requirements = [
                    node1.mempool.count == node2.mempool.count,
                    node2.mempool.count == node3.mempool.count,
                    node3.mempool.count == 1
                ]
                if requirements.allSatisfy({ $0 == true}) {
                    txSync.fulfill()
                    break
                }
            }
        }
        wait(for: [txSync], timeout: 3)
        
        let newNodeTxSync = XCTestExpectation(description: "Sync new node")
        let node4 = Node(address: NodeAddress(host: "localhost", port: 6969))
        DispatchQueue.global().async {
            while true {
                let requirements = [
                    node4.mempool.count == node1.mempool.count,
                    node4.blockchain.blocks.count == node1.blockchain.blocks.count
                ]
                if requirements.allSatisfy({ $0 == true}) {
                    newNodeTxSync.fulfill()
                    break
                }
            }
        }
        wait(for: [newNodeTxSync], timeout: 3)
        
        // Now let node2 mine the next block, claiming the Coinbase reward as well as receiving 1 from the above transaction
        // Expect every node's blocks to update, and everyones utxos to update appropriately
        let mineSync = XCTestExpectation(description: "Mining sync")
        let _ = node2.mineBlock(minerAddress: node2Wallet.address)
        DispatchQueue.global().async {
            while true {
                let requirements = [
                    node1.blockchain.blocks.count == node2.blockchain.blocks.count,
                    node2.blockchain.blocks.count == node3.blockchain.blocks.count,
                    node3.blockchain.blocks.count == node4.blockchain.blocks.count,
                    node4.blockchain.blocks.count == 2,
                    
                    node1.blockchain.balance(for: node2Wallet.address) == node2.blockchain.balance(for: node2Wallet.address),
                    node2.blockchain.balance(for: node2Wallet.address) == node3.blockchain.balance(for: node2Wallet.address),
                    node3.blockchain.balance(for: node2Wallet.address) == node4.blockchain.balance(for: node2Wallet.address),
                    node1.blockchain.balance(for: node2Wallet.address) == node1.blockchain.currentBlockValue() + 1,
                    
                    node1.blockchain.balance(for: node1Wallet.address) == node1.blockchain.currentBlockValue() - 1,
                    node2.blockchain.balance(for: node1Wallet.address) == node2.blockchain.currentBlockValue() - 1,
                    node3.blockchain.balance(for: node1Wallet.address) == node3.blockchain.currentBlockValue() - 1,
                    node4.blockchain.balance(for: node1Wallet.address) == node4.blockchain.currentBlockValue() - 1
                ]
                if requirements.allSatisfy({ $0 == true}) {
                    mineSync.fulfill()
                    break
                }
            }
        }
        wait(for: [mineSync], timeout: 3)
    }
    
    func testNodeStatePersistence() {
        // Create a Node, mine a block, and add a transaction - then persist it's state
        let node = Node(address: NodeAddress(host: "localhost", port: 8080))
        let wallet = Wallet(name: "Wallet")!
        let _ = node.mineBlock(minerAddress: wallet.address)
        let _ = try? node.createTransaction(sender: wallet, recipientAddress: wallet.address, value: 1000)
        node.saveState()
        var state = Node.loadState()
        
        // A new Node loadState true should get state from previous node
        let node2 = Node(address: NodeAddress(host: "localhost", port: 8080), blockchain: state.blockchain, mempool: state.mempool)
        XCTAssert(node.blockchain.blocks.count == node2.blockchain.blocks.count)
        XCTAssert(node.mempool.count == node2.mempool.count)
        
        // A new node with loadState false should not share state
        let node3 = Node(address: NodeAddress(host: "localhost", port: 1337))
        XCTAssert(node3.blockchain.blocks.count == 0)
        XCTAssert(node3.mempool.count == 0)
        
        // After clearing the state of our first Node, a new node should load empty state
        node.clearState()
        state = Node.loadState()
        let node5 = Node(address: NodeAddress(host: "localhost", port: 8080), blockchain: state.blockchain, mempool: state.mempool)
        XCTAssert(node5.blockchain.blocks.count == 0)
        XCTAssert(node5.mempool.count == 0)
    }
    
    func testCirculatingSupply() {
        let blockchain = Blockchain()
        XCTAssert(blockchain.circulatingSupply() == 0)
        (1...1_000_000).forEach { i in
            let block = Block(timestamp: 0, transactions: [Transaction.coinbase(address: Data(), blockValue: blockchain.currentBlockValue())], nonce: 0, hash: Data(), previousHash: Data())
            blockchain.blocks.append(block)
        }
        let expectedCirculatingSupply =
            blockchain.blocks
                .map { $0.transactions.first! }
                .map { $0.outputs.first!.value }
                .reduce(0, +)
        XCTAssert(expectedCirculatingSupply == blockchain.circulatingSupply())
    }
    
    static let allTests = [
        ("testKeyGenAndTxSigning", testKeyGenAndTxSigning),
        ("testKeyRestoreData", testKeyRestoreData),
        ("testKeyRestoreHex", testKeyRestoreHex),
        ("testWalletStore", testWalletStore),
        ("testKeyRestoreAndTxSigning", testKeyRestoreAndTxSigning),
        ("testWalletTxSigning", testWalletTxSigning),
        ("testTransactions", testTransactions),
        ("testNodeNetwork", testNodeNetwork),
        ("testCirculatingSupply", testCirculatingSupply)
    ]
    
}

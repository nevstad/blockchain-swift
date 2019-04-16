import XCTest
@testable import BlockchainSwift

final class BlockchainSwiftTests: XCTestCase {
    
    func testKeyGenAndTxSigning() {
        if let keyPair = ECDSA.generateKeyPair() {
            if let pubKeyData = ECDSA.copyExternalRepresentation(key: keyPair.publicKey) {
                let address = pubKeyData.sha256().sha256()
                let utxo = TransactionOutput(value: 100, address: address)
                let utxoHash = utxo.serialized().sha256()
                // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
                guard let signature1 = try? ECDSA.sign(data: utxoHash, with: keyPair.privateKey) else {
                    XCTFail("Could not sign with original key")
                    return
                }
                let verified1 = ECDSA.verify(publicKey: pubKeyData, data: utxoHash, signature: signature1)
                XCTAssert(verified1, "Unable to verify signature1")
            } else {
                XCTFail("Failed to restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testKeyRestoreData() {
        if let keyPair = ECDSA.generateKeyPair(),
            let privKeyData = ECDSA.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = ECDSA.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = ECDSA.generateKeyPair(privateKeyData: privKeyData),
                let restoredPrivKeyData = ECDSA.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = ECDSA.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
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
        if let keyPair = ECDSA.generateKeyPair(),
            let privKeyData = ECDSA.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = ECDSA.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = ECDSA.generateKeyPair(privateKeyHex: privKeyData.hex),
                let restoredPrivKeyData = ECDSA.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = ECDSA.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
                XCTAssert(privKeyData.hex == restoredPrivKeyData.hex, "Mismatching private keys")
                XCTAssert(pubKeyData.hex == restoredPubKeyData.hex, "Mismatching public keys")
            } else {
                XCTFail("Could not restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testKeyRestoreAndTxSigning() {
        if let keyPair = ECDSA.generateKeyPair(),
            let privKeyData = ECDSA.copyExternalRepresentation(key: keyPair.privateKey),
            let pubKeyData = ECDSA.copyExternalRepresentation(key: keyPair.publicKey) {
            if let restoredKeyPair = ECDSA.generateKeyPair(privateKeyData: privKeyData),
                let restoredPrivKeyData = ECDSA.copyExternalRepresentation(key: restoredKeyPair.privateKey),
                let restoredPubKeyData = ECDSA.copyExternalRepresentation(key: restoredKeyPair.publicKey) {
                XCTAssert(privKeyData.hex == restoredPrivKeyData.hex, "Mismatching private keys")
                XCTAssert(pubKeyData.hex == restoredPubKeyData.hex, "Mismatching public keys")
                
                let address = pubKeyData.sha256().sha256()
                let restoredAddress = restoredPubKeyData.sha256().sha256()
                XCTAssert(address == restoredAddress, "Mismatching addresses")
                
                let utxo = TransactionOutput(value: 100, address: address)
                let utxoHash = utxo.serialized().sha256()
                
                // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
                guard let signature = try? ECDSA.sign(data: utxoHash, with: keyPair.privateKey) else {
                    XCTFail("Could not sign with original key")
                    return
                }
                guard let restoredSignature = try? ECDSA.sign(data: utxoHash, with: restoredKeyPair.privateKey) else {
                    XCTFail("Could not sign with restored key")
                    return
                }
                let verified1 = ECDSA.verify(publicKey: pubKeyData, data: utxoHash, signature: signature)
                let verified2 = ECDSA.verify(publicKey: pubKeyData, data: utxoHash, signature: restoredSignature)
                let verified3 = ECDSA.verify(publicKey: restoredPubKeyData, data: utxoHash, signature: restoredSignature)
                let verified4 = ECDSA.verify(publicKey: restoredPubKeyData, data: utxoHash, signature: signature)
                XCTAssert(verified1 && verified2 && verified3 && verified4, "Original and restored keys are not fully interoperable")
            } else {
                XCTFail("Could not restore key pair")
            }
        } else {
            XCTFail("Could not generate key pair")
        }
    }
    
    func testWalletTxSigning() throws {
        let wallet1 = Wallet()!
        let wallet2 = Wallet()!

        // Wallet 2 will try to steal all of Wallet 1's balance, which is here set to 100
        let wallet1utxo = TransactionOutput(value: 100, address: wallet1.address)
        let originalOutputData = wallet1utxo.serialized().sha256()

        // Create a transaction and sign it, making sure first the sender has the right to claim the spendale outputs
        let signature1 = try wallet1.sign(utxo: wallet1utxo)
        let signature2 = try wallet2.sign(utxo: wallet1utxo)
        let verified1 = ECDSA.verify(publicKey: wallet1.publicKey, data: originalOutputData, signature: signature1)
        let verified2 = ECDSA.verify(publicKey: wallet1.publicKey, data: originalOutputData, signature: signature2)
        XCTAssert(verified1, "Wallet1 should have been verified")
        XCTAssert(!verified2, "Wallet2 should not have been verified")
    }

    func testTransactions() throws {
        // Two wallets, one blockchain
        let node1 = Node(address: NodeAddress.centralAddress(), loadState: false)
        let node2 = Node(address: NodeAddress(host: "localhost", port: 1337), loadState: false)
        let _ = node1.mineBlock()
        
        // Wallet1 has mined genesis block, and should have gotten the reward
        XCTAssert(node1.blockchain.balance(for: node1.wallet.address) == node1.blockchain.currentBlockValue())
        // Wallet2 is broke
        XCTAssert(node1.blockchain.balance(for: node2.wallet.address) == 0)

        // Send 1000 from Wallet1 to Wallet2, and again let wallet1 mine the next block
        let _ = try node1.createTransaction(recipientAddress: node2.wallet.address, value: 1000)
        XCTAssert(node1.mempool.count == 1) // One Tx should be in the pool, ready to go into the next block when mined
        let _ = node1.mineBlock()
        XCTAssert(node1.mempool.count == 0) // Tx pool should now be clear

        // Wallet1 should now have a balance == two block rewards - 1000
        XCTAssert(node1.blockchain.balance(for: node1.wallet.address) == (node1.blockchain.currentBlockValue() * 2) - 1000)
        // Wallet 2 should have a balance == 1000
        XCTAssert(node1.blockchain.balance(for: node2.wallet.address) == 1000)

        // Attempt to send more from Wallet1 than it currently has, expect failure
        do {
            let _ = try node1.createTransaction(recipientAddress: node2.wallet.address, value: UInt64.max)
            XCTAssert(false, "Overdraft")
        } catch { }

        // Check sanity of utxo state, ensuring Wallet1 and Wallet2 has rights to their unspent outputs
        let utxosWallet1 = node1.blockchain.findSpendableOutputs(for: node1.wallet.address)
        let utxosWallet2 = node1.blockchain.findSpendableOutputs(for: node2.wallet.address)
        XCTAssert(node1.wallet.canUnlock(utxos: utxosWallet1))
        XCTAssert(!node1.wallet.canUnlock(utxos: utxosWallet2))
        XCTAssert(node2.wallet.canUnlock(utxos: utxosWallet2))
        XCTAssert(!node2.wallet.canUnlock(utxos: utxosWallet1))
    }
    
    func testNodeNetwork() {
        // Set up our network of 3 nodes, and letting the first node mine the genesis block
        // Excpect the genesis block to propagate to all nodes
        let initialSync = XCTestExpectation(description: "Initial sync")
        let node1 = Node(address: NodeAddress.centralAddress(), loadState: false)
        let _ = node1.mineBlock()
        let node2 = Node(address: NodeAddress(host: "localhost", port: 1337), loadState: false)
        let node3 = Node(address: NodeAddress(host: "localhost", port: 7331), loadState: false)
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
            let _ = try node1.createTransaction(recipientAddress: node2.wallet.address, value: 100)
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
        
        // Now let node2 mine the next block, claiming the Coinbase reward as well as receiving 100 from the above transaction
        // Expect every node's blocks to update, and everyones utxos to update appropriately
        let mineSync = XCTestExpectation(description: "Mining sync")
        let _ = node2.mineBlock()
        DispatchQueue.global().async {
            while true {
                let requirements = [
                    node1.blockchain.blocks.count == node2.blockchain.blocks.count,
                    node2.blockchain.blocks.count == node3.blockchain.blocks.count,
                    node3.blockchain.blocks.count == 2,
                    
                    node1.blockchain.balance(for: node2.wallet.address) == node2.blockchain.balance(for: node2.wallet.address),
                    node2.blockchain.balance(for: node2.wallet.address) == node3.blockchain.balance(for: node2.wallet.address),
                    node1.blockchain.balance(for: node2.wallet.address) == node1.blockchain.currentBlockValue() + 100,
                    
                    node1.blockchain.balance(for: node1.wallet.address) == node1.blockchain.currentBlockValue() - 100,
                    node2.blockchain.balance(for: node1.wallet.address) == node2.blockchain.currentBlockValue() - 100,
                    node3.blockchain.balance(for: node1.wallet.address) == node3.blockchain.currentBlockValue() - 100
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
        let node = Node(address: NodeAddress(host: "localhost", port: 8080), loadState: false)
        let _ = node.mineBlock()
        let _ = try? node.createTransaction(recipientAddress: node.wallet.address, value: 1000)
        node.saveState()
        
        // A new Node loadState true should get state from previous node
        let node2 = Node(address: NodeAddress(host: "localhost", port: 8080), loadState: true)
        XCTAssert(node.blockchain.blocks.count == node2.blockchain.blocks.count)
        XCTAssert(node.mempool.count == node2.blockchain.blocks.count)

        // A new node with loadState false should not share state
        let node3 = Node(address: NodeAddress(host: "localhost", port: 1337), loadState: false)
        XCTAssert(node3.blockchain.blocks.count == 0)
        XCTAssert(node3.mempool.count == 0)

        // After clearing the state of our first Node, a new node should load empty state
        node.clearState()
        let node5 = Node(address: NodeAddress(host: "localhost", port: 8080), loadState: true)
        XCTAssert(node5.blockchain.blocks.count == 0)
        XCTAssert(node5.mempool.count == 0)
    }
    
    static let allTests = [
        ("testKeyGenAndTxSigning", testKeyGenAndTxSigning),
        ("testKeyRestoreAndTxSigning", testKeyRestoreAndTxSigning),
        ("testWalletTxSigning", testWalletTxSigning),
        ("testTransactions", testTransactions),
        ("testNodeNetwork", testNodeNetwork)
    ]

}

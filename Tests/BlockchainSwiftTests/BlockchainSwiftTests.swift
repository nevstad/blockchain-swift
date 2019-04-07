import XCTest
@testable import BlockchainSwift

final class BlockchainSwiftTests: XCTestCase {
    func testTxSigning() throws {
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
    
    func testTx() throws {
        // Two wallets, one blockchain
        let wallet1 = Wallet()!
        let wallet2 = Wallet()!
        let blockchain = Blockchain(minerAddress: wallet1.address)
        
        // Wallet1 has mined genesis block, and should have gotten the reward
        XCTAssert(blockchain.balance(for: wallet1.address) == blockchain.currentBlockValue())
        // Wallet2 is broke
        XCTAssert(blockchain.balance(for: wallet2.address) == 0)
        
        // Send 1000 from Wallet1 to Wallet2, and again let wallet1 mine the next block
        let _ = try blockchain.createTransaction(sender: wallet1, recipientAddress: wallet2.address, value: 1000)
        XCTAssert(blockchain.mempool.count == 1) // One Tx should be in the pool, ready to go into the next block when mined
        let _ = blockchain.mineBlock(previousHash: blockchain.lastBlock().hash, minerAddress: wallet1.address)
        XCTAssert(blockchain.mempool.count == 0) // Tx pool should now be clear
        
        // Wallet1 should now have a balance == two block rewards - 1000
        XCTAssert(blockchain.balance(for: wallet1.address) == (blockchain.currentBlockValue() * 2) - 1000)
        // Wallet 2 should have a balance == 1000
        XCTAssert(blockchain.balance(for: wallet2.address) == 1000)
        
        // Attempt to send more from Wallet1 than it currently has, expect failure
        do {
            try blockchain.createTransaction(sender: wallet1, recipientAddress: wallet2.address, value: UInt64.max)
            XCTAssert(false, "Overdraft")
        } catch { }
        
        // Check sanity of utxo state, ensuring Wallet1 and Wallet2 has rights to their unspent outputs
        let utxosWallet1 = blockchain.utxos.filter { $0.address == wallet1.address }
        let utxosWallet2 = blockchain.utxos.filter { $0.address == wallet2.address }
        XCTAssert(wallet1.canUnlock(utxos: utxosWallet1))
        XCTAssert(!wallet1.canUnlock(utxos: utxosWallet2))
        XCTAssert(wallet2.canUnlock(utxos: utxosWallet2))
        XCTAssert(!wallet2.canUnlock(utxos: utxosWallet1))
    }
    
    
    static let allTests = [
        ("testTxSigning", testTxSigning),
        ("testTx", testTx)
    ]

}

//
//  BlockStore.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 17/06/2019.
//

import Foundation
import GRDB

/// Represents a transaction between two parties
public struct Payment {
    public enum State {
        case sent
        case received
    }
    
    public let timestamp: UInt32
    public let state: State
    public let value: UInt64
    public let from: Data
    public let to: Data
    public let txId: Data
    public let pending: Bool
}

public protocol BlockStore {
    func addBlock(_ block: Block) throws
    func blocks(fromHash: Data?) throws -> [Block]
    func latestBlockHash() throws -> Data?
    func blockHeight() throws -> Int
    func addTransaction(_ tx: Transaction) throws
    func mempool() throws -> [Transaction]
    func payments(publicKey: Data) throws -> [Payment]
    func balance(for address: Data) throws -> UInt64
    func unspentTransactions(for address: Data) throws -> [UnspentTransaction]
}

/// Blockstore is our database layer for persisting and fetching Blockchain data
public class SQLiteBlockStore: BlockStore {
    private let pool: DatabasePool


    public init(path: URL) {
        pool = try! DatabasePool(path: path.absoluteString)
        try! createTables()
    }
    
    deinit {
        try! pool.erase()
    }
    
    private func createTables() throws {
        try pool.write { db in
            try db.create(table: "block", ifNotExists: true) { t in
                t.column("hash", .blob).notNull().primaryKey()
                t.column("timestamp", .integer).notNull()
                t.column("tx_count", .integer).notNull()
                t.column("nonce", .integer).notNull()
                t.column("prev_hash", .blob).notNull()
            }
            
            try db.create(table: "tx", ifNotExists: true) { t in
                t.column("hash", .blob).notNull().primaryKey()
                t.column("lock_time", .integer).notNull()
                t.column("in_count", .integer).notNull()
                t.column("out_count", .integer).notNull()
                t.column("block_hash", .blob)
                    .references("block", column: "hash")
            }
            
            try db.create(table: "txout", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("value", .integer).notNull()
                t.column("address", .blob).notNull()
                t.column("hash", .blob).notNull()
                t.column("tx_hash", .blob).notNull()
                    .references("tx", column: "hash", onDelete: .cascade, onUpdate: .cascade)
            }

            try db.create(table: "txin", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("out_hash", .blob).notNull()
                t.column("out_idx", .integer).notNull()
                t.column("public_key", .blob).notNull()
                t.column("signature", .blob).notNull()
                t.column("tx_hash", .blob).notNull()
                    .references("tx", column: "hash", onDelete: .cascade, onUpdate: .cascade)
            }
            
            try db.create(table: "utxo", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("outpoint_hash", .blob).notNull()
                t.column("outpoint_idx", .integer).notNull()
                t.column("value", .integer).notNull()
                t.column("address", .blob).notNull()
            }
        }
    }
    
    public func addBlock(_ block: Block) throws {
        try pool.write { db in
            try db.execute(sql: "INSERT INTO block (hash, timestamp, tx_count, nonce, prev_hash) VALUES (?, ?, ?, ?, ?)" ,
                           arguments: [block.hash, block.timestamp, block.transactions.count, block.nonce, block.previousHash])
            try block.transactions.forEach {
                if let _ = try Row.fetchOne(db, sql: "SELECT * FROM tx WHERE hash = ?", arguments: [$0.txHash]) {
                    try db.execute(sql: "UPDATE tx SET block_hash = ? WHERE hash = ?", arguments: [block.hash, $0.txHash])
                } else {
                    try addTransaction(tx: $0, blockHash: block.hash, db: db)
                }
            }
        }
    }
    
    public func addTransaction(_ tx: Transaction) throws {
        try pool.write { db in
            try addTransaction(tx: tx, db: db)
        }
    }
    
    private func addTransaction(tx: Transaction, blockHash: Data? = nil, db: Database) throws {
        try db.execute(sql: "INSERT INTO tx (hash, lock_time, in_count, out_count, block_hash) VALUES (?, ?, ?, ?, ?)" ,
                       arguments: [tx.txHash, tx.lockTime, tx.inputs.count, tx.outputs.count, blockHash]
        )
        try tx.inputs.forEach {
            try db.execute(sql: "INSERT INTO txin (out_hash, out_idx, public_key, signature, tx_hash) VALUES (?, ?, ?, ?, ?)" ,
                           arguments: [$0.previousOutput.hash, $0.previousOutput.index, $0.publicKey, $0.signature, tx.txHash]
            )
        }
        try tx.outputs.forEach {
            try db.execute(sql: "INSERT INTO txout (value, address, hash, tx_hash) VALUES (?, ?, ?, ?)" ,
                           arguments: [$0.value, $0.address, $0.hash, tx.txHash])
        }
        try updateUnspentTransactions(with: tx, db: db)
    }

    private func updateUnspentTransactions(with transaction: Transaction, db: Database) throws {
        // For non-Coinbase transactions (which have no inputs) we must remove UTXOs that reference this transaction's inputs
        if !transaction.isCoinbase {
            try transaction.inputs.map { $0.previousOutput }.forEach { prevOut in
                try db.execute(sql: "DELETE FROM utxo WHERE outpoint_hash = ? AND outpoint_idx = ?",
                               arguments: [prevOut.hash, prevOut.index]
                )
            }
        }
        
        // For all transaction outputs we create a new UTXO
        for (index, output) in transaction.outputs.enumerated() {
            try db.execute(sql: "INSERT INTO utxo (outpoint_hash, outpoint_idx, value, address) VALUES (?, ?, ?, ?)",
                           arguments: [transaction.txHash, UInt32(index), output.value, output.address]
            )
        }
    }

    public func blocks(fromHash: Data? = nil) throws -> [Block] {
        if let hash = fromHash {
            return try pool.read { db -> [Block] in
                let cursor = try Row.fetchCursor(db, sql: "SELECT * FROM block ORDER BY timestamp DESC")
                var blocks = [Block]()
                while let row = try cursor.next() {
                    let b = try block(from: row, db: db)
                    blocks.append(b)
                    if b.hash == hash {
                        break
                    }
                }
                return blocks
            }
        } else {
            return try pool.read { db -> [Block] in
                let rows = try Row.fetchAll(db, sql: "SELECT * FROM block ORDER BY timestamp ASC")
                var blocks = [Block]()
                for row in rows {
                    blocks.append(try block(from: row, db: db))
                }
                return blocks
            }
        }
    }
    
    private func block(from row: Row, db: Database) throws -> Block {
        let timestamp: UInt32  = row["timestamp"]
        let hash: Data = row["hash"]
        let nonce: UInt32 = row["nonce"]
        let prevHash: Data = row["prev_hash"]
        let txs = try transactions(db: db, blockHash: hash)
        return Block(timestamp: timestamp, transactions: txs, nonce: nonce, hash: hash, previousHash: prevHash)
    }
    
    public func mempool() throws -> [Transaction] {
        return try pool.read { db -> [Transaction] in
            return try Row.fetchAll(db, sql: "SELECT * FROM tx WHERE block_hash IS NULL").map { try self.transaction(from: $0, db: db) }
        }
    }
    
    private func transaction(from row: Row, db: Database) throws -> Transaction {
        let txHash: Data = row["hash"]
        let locktime: UInt32 = row["lock_time"]
        let ins = try Row.fetchAll(db, sql: "SELECT out_hash, out_idx, public_key, signature FROM txin WHERE tx_hash = ?", arguments: [txHash]).map { row in
            TransactionInput(previousOutput: TransactionOutputReference(hash: row["out_hash"], index: row["out_idx"]),
                             publicKey: row["public_key"],
                             signature: row["signature"])
        }
        let outs = try Row.fetchAll(db, sql: "SELECT value, address FROM txout WHERE tx_hash = ?", arguments: [txHash]).map { row in
            TransactionOutput(value: row["value"], address: row["address"])
        }
        return Transaction(inputs: ins, outputs: outs, lockTime: locktime)
    }
    
    private func transactions(db: Database, blockHash: Data) throws -> [Transaction] {
        return try Row.fetchAll(db, sql: "SELECT hash, lock_time FROM tx WHERE block_hash = ?", arguments: [blockHash]).map { try transaction(from: $0, db: db) }
    }
    
    public func latestBlockHash() throws -> Data? {
        return try pool.read { db -> Data? in
            if let row = try Row.fetchOne(db, sql: "SELECT hash FROM block ORDER BY timestamp DESC LIMIT 1") {
                let hash: Data = row["hash"]
                return hash
            } else {
                return nil
            }
        }
    }
    
    public func blockHeight() throws -> Int {
        return try pool.read { db -> Int in
            return try Row.fetchOne(db, sql: "SELECT COUNT(1) AS block_height FROM block").map { row in row["block_height"] as Int } ?? 0
        }
    }
    
    public func payments(publicKey: Data) throws -> [Payment] {
        return try pool.read { db -> [Payment] in
            let sqlReceived =
                """
                SELECT DISTINCT tx.block_hash, tx.lock_time, tx.hash, txin.public_key, txout.value, txout.address FROM tx
                LEFT JOIN txout ON tx.hash = txout.tx_hash
                LEFT JOIN txin ON tx.hash = txin.tx_hash
                WHERE txout.address = ? OR txin.public_key = ?
                ORDER BY lock_time DESC
                """
            return try Row.fetchAll(db, sql: sqlReceived, arguments: [publicKey.toAddress(), publicKey]).map { row in
                let txId: Data = row["hash"]
                let txPublicKey: Data = row["public_key"]
                let txFrom = txPublicKey.toAddress()
                let txValue: UInt64 = row["value"]
                let txAddress: Data = row["address"]
                let txBlockHash: Data? = row["block_hash"]
                let txTimestamp: UInt32 = row["lock_time"]
                return Payment(timestamp: txTimestamp, state: txPublicKey == publicKey ? .sent : .received, value: txValue, from: txFrom, to: txAddress, txId: txId, pending: txBlockHash == nil)
                }
                .filter { $0.from != $0.to } // Removes change outputs (which are sent to self)
        }
    }
    
    public func balance(for address: Data) throws -> UInt64 {
        return try pool.read { db -> UInt64 in
            let sql = "SELECT value FROM utxo WHERE address = ?"
            return try Row.fetchAll(db, sql: sql, arguments: [address])
                .map { $0["value"] as UInt64 }
                .reduce(0, +)
        }
    }
    
    public func unspentTransactions(for address: Data) throws -> [UnspentTransaction] {
        return try pool.read { db -> [UnspentTransaction] in
            let sql = "SELECT value, address, outpoint_hash, outpoint_idx FROM utxo WHERE address = ?"
            return try Row.fetchAll(db, sql: sql, arguments: [address]).map { row in
                UnspentTransaction(output: TransactionOutput(value: row["value"], address: row["address"]),
                                   outpoint: TransactionOutputReference(hash: row["outpoint_hash"], index: row["outpoint_idx"]))
            }
        }
    }

    
}


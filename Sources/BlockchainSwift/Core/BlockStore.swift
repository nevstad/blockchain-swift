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
    
    let state: State
    let value: UInt64
    let from: Data
    let to: Data
    let txId: Data
}

/// Blockstore is our database layer for persisting and fetching Blockchain data
public class BlockStore {
    let queue = DatabaseQueue()
    
    public init() {
        try? createTables()
    }
    
    private func createTables() throws {
        try queue.write { db in
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
                t.column("block_hash", .blob).notNull().references("block", column: "hash")
            }
            
            try db.create(table: "txout", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("value", .integer).notNull()
                t.column("address", .blob).notNull()
                t.column("hash", .blob).notNull()
                t.column("tx_hash", .blob).notNull().references("tx", column: "hash")
            }

            try db.create(table: "txin", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("out_hash", .blob).notNull()
                t.column("out_idx", .integer).notNull()
                t.column("public_key", .blob).notNull()
                t.column("signature", .blob).notNull()
                t.column("tx_hash", .blob).notNull().references("tx", column: "hash")
            }
            
            try db.create(table: "utxo", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("outpoint_hash", .blob).notNull()
                t.column("outpoint_idx", .integer).notNull()
                t.column("out_hash", .blob).notNull()
            }
        }
    }
    
    public func addBlock(_ block: Block) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT INTO block (hash, timestamp, tx_count, nonce, prev_hash) VALUES (?, ?, ?, ?, ?)" , arguments: [block.hash, block.timestamp, block.transactions.count, block.nonce, block.previousHash])
        }
        try block.transactions.forEach { try addTransaction($0, blockHash: block.hash) }
    }

    public func blocks(fromHash: Data? = nil) throws -> [Block] {
        return try queue.read { db -> [Block] in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM block ORDER BY timestamp ASC")
            var blocks = [Block]()
            for row in rows {
                let timestamp: UInt32  = row["timestamp"]
                let hash: Data = row["hash"]
                let nonce: UInt32 = row["nonce"]
                let prevHash: Data = row["prev_hash"]
                let txs = try transactions(db: db, blockHash: hash)
                blocks.append(Block(timestamp: timestamp, transactions: txs, nonce: nonce, hash: hash, previousHash: prevHash))
            }
            return blocks
        }
    }
    
    private func addTransaction(_ tx: Transaction, blockHash: Data) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT INTO tx (hash, lock_time, in_count, out_count, block_hash) VALUES (?, ?, ?, ?, ?)" ,
                           arguments: [tx.txHash, tx.lockTime, tx.inputs.count, tx.outputs.count, blockHash]
            )
        }
        try tx.inputs.forEach { try addTransactionInput($0, txHash: tx.txHash)}
        try tx.outputs.forEach { try addTransactionOutput($0, txHash: tx.txHash)}
    }

    private func transactions(db: Database, blockHash: Data) throws -> [Transaction] {
        let rows = try Row.fetchAll(db, sql: "SELECT hash, lock_time FROM tx WHERE block_hash = ?", arguments: [blockHash])
        return try rows.map { row in
            let txHash: Data = row["hash"]
            let locktime: UInt32 = row["lock_time"]
            let ins = try transactionInputs(db: db, txHash: txHash)
            let outs = try transactionOutputs(db: db, txHash: txHash)
            return Transaction(inputs: ins, outputs: outs, lockTime: locktime)
        }
    }

    private func addTransactionInput(_ txIn: TransactionInput, txHash: Data) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT INTO txin (out_hash, out_idx, public_key, signature, tx_hash) VALUES (?, ?, ?, ?, ?)" ,
                           arguments: [txIn.previousOutput.hash, txIn.previousOutput.index, txIn.publicKey, txIn.signature, txHash]
            )
        }
    }
    
    private func transactionInputs(db: Database, txHash: Data) throws -> [TransactionInput] {
        return try Row.fetchAll(db, sql: "SELECT out_hash, out_idx, public_key, signature FROM txin WHERE tx_hash = ?", arguments: [txHash]).map { row in
            TransactionInput(previousOutput: TransactionOutputReference(hash: row["out_hash"], index: row["out_idx"]), publicKey: row["public_key"], signature: row["signature"])
        }
    }

    private func addTransactionOutput(_ txOut: TransactionOutput, txHash: Data) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT INTO txout (value, address, hash, tx_hash) VALUES (?, ?, ?, ?)" ,
                           arguments: [txOut.value, txOut.address, txOut.hash, txHash]
            )
        }
    }
    
    private func transactionOutputs(db: Database, txHash: Data) throws -> [TransactionOutput] {
        return try Row.fetchAll(db, sql: "SELECT value, address FROM txout WHERE tx_hash = ?", arguments: [txHash]).map { row in
            TransactionOutput(value: row["value"], address: row["address"])
        }
    }
    
    public func addUnspentTransaction(_ utxo: UnspentTransaction) throws {
        try queue.write { db in
            try db.execute(sql: "INSERT INTO utxo (outpoint_hash, outpoint_idx, out_hash) VALUES (?, ?, ?)",
                           arguments: [utxo.outpoint.hash, utxo.outpoint.index, utxo.output.hash]
            )
        }
    }
    
    public func deleteUnspentTransaction(_ utxo: UnspentTransaction) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM utxo WHERE outpoint_hash = ? AND outpoint_idx = ?, and out_hash = ?",
                           arguments: [utxo.outpoint.hash, utxo.outpoint.index, utxo.output.hash]
            )
        }
    }

    public func unspentTransactions(for address: Data) throws -> [UnspentTransaction] {
        return try queue.read { db -> [UnspentTransaction] in
            let sql =
                """
                SELECT txout.value, txout.address, outpoint_hash, outpoint_idx FROM utxo
                LEFT JOIN txout ON utxo.out_hash = txout.hash
                LEFT JOIN txin ON txout.tx_hash = txin.tx_hash
                WHERE txout.address = ?
                """
            return try Row.fetchAll(db, sql: sql, arguments: [address]).map { row in
                UnspentTransaction(output: TransactionOutput(value: row["value"], address: row["address"]), outpoint: TransactionOutputReference(hash: row["outpoint_hash"], index: row["outpoint_idx"]))
            }
        }
    }
    
    public func spend(_ txIn: TransactionInput) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM utxo WHERE outpoint_hash = ? AND outpoint_idx = ?",
                           arguments: [txIn.previousOutput.hash, txIn.previousOutput.index]
            )
        }
    }

    public func balance(for address: Data) throws -> UInt64 {
        return try queue.read { db -> UInt64 in
            let sql = "SELECT txout.value FROM utxo LEFT JOIN txout ON out_hash = txout.hash WHERE txout.address = ?"
            return try Row.fetchAll(db, sql: sql, arguments: [address])
                .map { row in
                    row["value"] as UInt64
                }
                .reduce(0, +)
        }
    }
    
    public func latestBlockHash() throws -> Data {
        return try queue.read { db -> Data in
            if let row = try Row.fetchOne(db, sql: "SELECT hash FROM block ORDER BY timestamp DESC LIMIT 1") {
                let hash: Data = row["hash"]
                return hash
            } else {
                return Data()
            }
        }
    }
    
    public func blockHeight() throws -> Int {
        return try queue.read { db -> Int in
            let rows = try Row.fetchAll(db, sql: "SELECT COUNT(1) FROM block").count
            return rows
        }
    }

    public func transactions(address: Data) throws -> [Payment] {
        return try queue.read { db -> [Payment] in
            let sql =
                """
                SELECT tx.hash, txin.public_key, txout.value, txout.address FROM tx
                LEFT JOIN txout ON tx.hash = txout.tx_hash
                LEFT JOIN txin ON tx.hash = txin.tx_hash
                WHERE txout.address = ?
                """
            let txRows = try Row.fetchAll(db, sql: sql, arguments: [address])
            var txs = [Payment]()
            for txRow in txRows {
                let txid: Data = txRow["hash"]
                let publicKey: Data = txRow["public_key"]
                let from = publicKey.toAddress()
                let value: UInt64 = txRow["value"]
                let address: Data = txRow["address"]
                let payment = Payment(state: from == address ? .sent : .received, value: value, from: publicKey.toAddress(), to: address, txId: txid)
                txs.append(payment)
            }
            return txs
        }
    }
    
}

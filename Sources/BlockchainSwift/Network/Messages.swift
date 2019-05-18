//
//  NodeMessages.swift
//  App
//
//  Created by Magnus Nevstad on 10/04/2019.
//

import Foundation

/// All messages get wrapped
public struct Message: Serializable, Deserializable, Codable {
    public enum Command: String, Codable, CustomStringConvertible {
        public var description: String {
            return ".\(rawValue)"
        }
        
        case version
        case getTransactions
        case transactions
        case getBlocks
        case blocks
    }
    
    public let command: Command
    public let payload: Data
    public let fromPort: UInt32
    
    public func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    public static func deserialize(_ data: Data) throws -> Message {
        return try JSONDecoder().decode(Message.self, from: data)
    }
}

/// The version message
public struct VersionMessage: Serializable, Deserializable, Codable {
    public let version: Int
    public let blockHeight: Int

    public func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    public static func deserialize(_ data: Data) throws -> VersionMessage {
        return try JSONDecoder().decode(VersionMessage.self, from: data)
    }
}

/// The GetBlocksMessage object will request Transactions
public struct GetTransactionsMessage: Serializable, Deserializable, Codable {
    public func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    public static func deserialize(_ data: Data) throws -> GetTransactionsMessage {
        return try JSONDecoder().decode(GetTransactionsMessage.self, from: data)
    }
}

/// The transactions message contains new transations
public struct TransactionsMessage: Serializable, Deserializable, Codable {
    public let transactions: [Transaction]

    public func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    public static func deserialize(_ data: Data) throws -> TransactionsMessage {
        return try JSONDecoder().decode(TransactionsMessage.self, from: data)
    }
}

/// The GetBlocksMessage object will request Blocks
public struct GetBlocksMessage: Serializable, Deserializable, Codable {
    public let fromBlockHash: Data

    public func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    public static func deserialize(_ data: Data) throws -> GetBlocksMessage {
        return try JSONDecoder().decode(GetBlocksMessage.self, from: data)
    }
}

/// The BlocksMessage contains transferred Blocks
public struct BlocksMessage: Serializable, Deserializable, Codable {
    public let blocks: [Block]

    public func serialized() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    public static func deserialize(_ data: Data) throws -> BlocksMessage {
        return try JSONDecoder().decode(BlocksMessage.self, from: data)
    }
}

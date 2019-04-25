//
//  NodeClient.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 13/04/2019.
//

import Foundation
import Network
import os.log

/// The MessageSender handles a an outgoing connection to another Node
public protocol MessageSender {
    func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)?)
}

extension MessageSender {
    public func sendVersionMessage(_ message: VersionMessage, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .version, payload: message, to: to, completion: completion)
    }
    public func sendGetTransactionsMessage(_ message: GetTransactionsMessage, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .getTransactions, payload: message, to: to, completion: completion)
    }
    public func sendTransactionsMessage(_ message: TransactionsMessage, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .transactions, payload: message, to: to, completion: completion)
    }
    public func sendGetBlocksMessage(_ message: GetBlocksMessage, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .getBlocks, payload: message, to: to, completion: completion)
    }
    public func sendBlocksMessage(_ message: BlocksMessage, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .blocks, payload: message, to: to, completion: completion)
    }
}

public class URLSessionMessageSender: MessageSender {
    public func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        let task = URLSession.shared.uploadTask(with: URLRequest(url: to.url), from: Message(command: command, payload: payload.serialized()).serialized()) { data, response, error in
            if let error = error {
                print(error)
            }
            print(response?.debugDescription ?? "No response")
            completion?(error == nil)
        }
        task.resume()
    }
}

public class NWConnectionMessageSender: MessageSender {
    public var queue: DispatchQueue
    
    public init(stateHandler: ((NWConnection.State) -> Void)? = nil) {
        queue = DispatchQueue(label: "NWConnectionMessageSender Queue")
    }
    
    public func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(to.host), port: NWEndpoint.Port(rawValue: UInt16(to.port))!)
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.start(queue: queue)
        let message = Message(command: command, payload: payload.serialized())
        connection.send(content: message.serialized(), completion: .contentProcessed({ (error) in
            if error != nil {
                os_log("Sending message failed", type: .error)
            } else {
                os_log("Sent %s message", type: .info, message.command.description)
            }
            connection.cancel()
            completion?(error == nil)
        }))
    }
}

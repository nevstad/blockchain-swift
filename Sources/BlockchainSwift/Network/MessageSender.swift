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
    var listenPort: UInt32 { get set }
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


public class NWConnectionMessageSender: MessageSender {
    public var queue: DispatchQueue
    public var listenPort: UInt32
    
    public init(listenPort port: UInt32, stateHandler: ((NWConnection.State) -> Void)? = nil) {
        queue = DispatchQueue(label: "NWConnectionMessageSender Queue")
        listenPort = port
    }
    
    public func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(to.host), port: NWEndpoint.Port(rawValue: UInt16(to.port))!)
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.start(queue: queue)
        let message = Message(command: command, payload: payload.serialized(), fromPort: listenPort)
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

#if canImport(NIO)
import NIO

public class NIOMessageSender: MessageSender {
    let group: MultiThreadedEventLoopGroup
    let bootstrap: ClientBootstrap
    public var listenPort: UInt32
    
    init(listenPort port: UInt32) {
        listenPort = port
        group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        bootstrap = ClientBootstrap(group: group)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    }
    
    public func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)?) {
        DispatchQueue.global().async {
            do {
                let channel = try self.bootstrap.connect(host: to.host, port: Int(to.port)).wait()
                let message = Message(command: command, payload: payload.serialized(), fromPort: self.listenPort).serialized()
                var buffer = channel.allocator.buffer(capacity: message.count)
                buffer.writeBytes(message)
                try channel.writeAndFlush(buffer).wait()
                try channel.close().wait()
                os_log("Sent %s message", type: .info, command.description)
            } catch let error {
                os_log("Sending message failed: %s", type: .error, error.localizedDescription)
                return
            }
        }
    }
}

#endif

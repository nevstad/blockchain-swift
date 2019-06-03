//
//  NodeClient.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 13/04/2019.
//

import Foundation
import Network
import os.log


extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

/// The MessageSender handles a an outgoing connection to another Node
public protocol MessageSender {
    var listenPort: UInt32 { get set }
    func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)?)
}

extension MessageSender {
    public func sendVersion(version: Int, blockHeight: Int, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .version, payload: VersionMessage(version: version, blockHeight: blockHeight), to: to, completion: completion)
    }
    public func sendGetTransactions(to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .getTransactions, payload: GetTransactionsMessage(), to: to, completion: completion)
    }
    public func sendTransactions(transactions: [Transaction], to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .transactions, payload: TransactionsMessage(transactions: transactions), to: to, completion: completion)
    }
    public func sendGetBlocks(fromBlockHash: Data, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .getBlocks, payload: GetBlocksMessage(fromBlockHash: fromBlockHash), to: to, completion: completion)
    }
    public func sendBlocks(blocks: [Block], to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .blocks, payload: BlocksMessage(blocks: blocks), to: to, completion: completion)
    }
}


public class NWConnectionMessageSender: MessageSender {
    private var queue: DispatchQueue
    public var listenPort: UInt32
    
    public init(listenPort port: UInt32, stateHandler: ((NWConnection.State) -> Void)? = nil) {
        queue = DispatchQueue(label: "NWConnectionMessageSender Queue")
        listenPort = port
    }
    
    public func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        let message = Message(command: command, payload: payload.serialized(), fromPort: listenPort)
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(to.host), port: NWEndpoint.Port(rawValue: UInt16(to.port))!)
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.start(queue: queue)
        connection.send(content: message.serialized(), contentContext: .defaultStream, isComplete: false, completion: .contentProcessed({ (error) in
            if error != nil {
                os_log("Sending message failed", type: .error)
            } else {
                connection.send(content: nil, contentContext: .defaultStream, isComplete: true, completion: .contentProcessed({ (error) in
                    os_log("Sent %s message", type: .info, message.command.description)
                    connection.cancel()
                    completion?(error == nil)
                }))
            }
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

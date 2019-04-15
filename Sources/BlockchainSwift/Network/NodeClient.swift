//
//  NodeClient.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 13/04/2019.
//

import Foundation
import Network

/// The NodeClient handles a an outgoing connection to another Node
public class NodeClient {
    public var queue: DispatchQueue
    
    public init(stateHandler: ((NWConnection.State) -> Void)? = nil) {
        self.queue = DispatchQueue(label: "Node Client Queue")
    }
    
    private func openConnection(to: NodeAddress) -> NWConnection {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(to.host), port: NWEndpoint.Port(rawValue: UInt16(to.port))!)
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: queue)
        return connection
    }
    
    public func sendVersionMessage(_ versionMessage: VersionMessage, to: NodeAddress) {
        let connection = openConnection(to: to)
        let message = Message(command: Message.Commands.version.rawValue, payload: versionMessage.serialized())
        connection.send(content: message.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ (error) in
            if let error = error {
                print(error)
            } else {
                print("Sent \(message)")
            }
        }))
    }
    
    public func sendTransactionsMessage(_ transactionsMessage: TransactionsMessage, to: NodeAddress) {
        let connection = openConnection(to: to)
        let message = Message(command: Message.Commands.transactions.rawValue, payload: transactionsMessage.serialized())
        connection.send(content: message.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ (error) in
            if let error = error {
                print(error)
            } else {
                print("Sent \(message)")
            }
        }))
    }

    public func sendGetBlocksMessage(_ getBlocksMessage: GetBlocksMessage, to: NodeAddress) {
        let connection = openConnection(to: to)
        let message = Message(command: Message.Commands.getBlocks.rawValue, payload: getBlocksMessage.serialized())
        connection.send(content: message.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ (error) in
            if let error = error {
                print(error)
            } else {
                print("Sent \(message)")
            }
        }))
    }
    
    public func sendBlocksMessage(_ blocksMessage: BlocksMessage, to: NodeAddress) {
        let connection = openConnection(to: to)
        let message = Message(command: Message.Commands.blocks.rawValue, payload: blocksMessage.serialized())
        connection.send(content: message.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ (error) in
            if let error = error {
                print(error)
            } else {
                print("Sent \(message)")
            }
        }))
    }

}

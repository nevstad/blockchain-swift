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
    
    private func send(serializable: Serializable, command: Message.Command, to: NodeAddress) {
        let connection = openConnection(to: to)
        let message = Message(command: command, payload: serializable.serialized())
        connection.send(content: message.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ (error) in
            if let error = error {
                print(error)
            } else {
                print("Sent \(message)")
            }
            connection.cancel()
        }))
    }
    
    public func sendVersionMessage(_ versionMessage: VersionMessage, to: NodeAddress) {
        send(serializable: versionMessage, command: .version, to: to)
    }
    
    public func sendGetTransactionsMessage(_ getTransactionsMessage: GetTransactionsMessage, to: NodeAddress) {
        send(serializable: getTransactionsMessage, command: .getTransactions, to: to)
    }

    public func sendTransactionsMessage(_ transactionsMessage: TransactionsMessage, to: NodeAddress) {
        send(serializable: transactionsMessage, command: .transactions, to: to)
    }

    public func sendGetBlocksMessage(_ getBlocksMessage: GetBlocksMessage, to: NodeAddress) {
        send(serializable: getBlocksMessage, command: .getBlocks, to: to)
    }
    
    public func sendBlocksMessage(_ blocksMessage: BlocksMessage, to: NodeAddress) {
        send(serializable: blocksMessage, command: .blocks, to: to)
    }
}

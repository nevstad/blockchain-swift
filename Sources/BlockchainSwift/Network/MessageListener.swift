//
//  NodeServer.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 13/04/2019.
//

import Foundation
import Network
import os.log

public protocol MessageListenerDelegate {
    func didReceiveVersionMessage(_ message: VersionMessage)
    func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage)
    func didReceiveTransactionsMessage(_ message: TransactionsMessage)
    func didReceiveGetBlocksMessage(_ message: GetBlocksMessage)
    func didReceiveBlocksMessage(_ message: BlocksMessage)
}

protocol MessageListener {
    var delegate: MessageListenerDelegate? { get set }
}

/// The MessageListener handles all incoming connections to a Node
public class NWListenerMessageListener: MessageListener {
    public let listener: NWListener
    public let queue: DispatchQueue
    public var connections = [NWConnection]()
    
    var delegate: MessageListenerDelegate?
    
    init(port: UInt16, stateHandler: ((NWListener.State) -> Void)? = nil) {
        self.queue = DispatchQueue(label: "Node Server Queue")
        self.listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener.stateUpdateHandler = stateHandler
        listener.newConnectionHandler = { [weak self] newConnection in
            if let strongSelf = self {
                newConnection.receive(minimumIncompleteLength: 1, maximumLength: 13371337) { (data, context, isComplete, error) in
                    if let data = data, let message = try? Message.deserialize(data) {
                        if message.command == .version {
                            if let versionMessage = try? VersionMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveVersionMessage(versionMessage)
                            } else {
                                os_log("Received malformed %s message", type: .error, message.command.description)
                            }
                        } else if message.command == .getTransactions {
                            if let getTransactionsMessage = try? GetTransactionsMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveGetTransactionsMessage(getTransactionsMessage)
                            } else {
                                os_log("Received malformed %s message", type: .error, message.command.description)
                            }
                        } else if message.command == .transactions {
                            if let transactionsMessage = try? TransactionsMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveTransactionsMessage(transactionsMessage)
                            } else {
                                os_log("Received malformed %s message", type: .error, message.command.description)
                            }
                        } else if message.command == .getBlocks {
                            if let getBlocksMessage = try? GetBlocksMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveGetBlocksMessage(getBlocksMessage)
                            } else {
                                os_log("Received malformed %s message", type: .error, message.command.description)
                            }
                        } else if message.command == .blocks {
                            if let blocksMessage = try? BlocksMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveBlocksMessage(blocksMessage)
                            } else {
                                os_log("Received malformed %s message", type: .error, message.command.description)
                            }
                        } else {
                            os_log("Received unknown %s message", type: .error, message.command.description)
                        }
                    } else {
                        os_log("Could not deserialize message", type: .error)
                    }
                }
                newConnection.start(queue: strongSelf.queue)
                self?.connections.append(newConnection)
                os_log("New connection: %s", type: .info, newConnection.debugDescription)
            }
        }
        listener.start(queue: queue)
    }
}


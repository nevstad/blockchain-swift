//
//  NodeServer.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 13/04/2019.
//

import Foundation
import Network

public protocol NodeServerDelegate {
    func didReceiveVersionMessage(_ message: VersionMessage)
    func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage)
    func didReceiveTransactionsMessage(_ message: TransactionsMessage)
    func didReceiveGetBlocksMessage(_ message: GetBlocksMessage)
    func didReceiveBlocksMessage(_ message: BlocksMessage)
}

/// The NodeServer handles all incoming connections to a Node
public class NodeServer {
    public let listener: NWListener
    public let queue: DispatchQueue
    public var connections = [NWConnection]()
    
    var delegate: NodeServerDelegate?
    
    init(port: UInt16, stateHandler: ((NWListener.State) -> Void)? = nil) {
        self.queue = DispatchQueue(label: "Node Server Queue")
        self.listener = try! NWListener(using: .udp, on: NWEndpoint.Port(rawValue: port)!)
        listener.stateUpdateHandler = stateHandler
        listener.newConnectionHandler = { [weak self] newConnection in
            if let strongSelf = self {
                newConnection.receiveMessage { (data, context, isComplete, error) in
                    if let data = data, let message = try? Message.deserialize(data) {
                        if message.command == .version {
                            if let versionMessage = try? VersionMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveVersionMessage(versionMessage)
                            } else {
                                print("Error: Received malformed \(message.command) message")
                            }
                        } else if message.command == .getTransactions {
                            if let getTransactionsMessage = try? GetTransactionsMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveGetTransactionsMessage(getTransactionsMessage)
                            } else {
                                print("Error: Received malformed \(message.command) message")
                            }
                        }else if message.command == .transactions {
                            if let transactionsMessage = try? TransactionsMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveTransactionsMessage(transactionsMessage)
                            } else {
                                print("Error: Received malformed \(message.command) message")
                            }
                        } else if message.command == .getBlocks {
                            if let getBlocksMessage = try? GetBlocksMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveGetBlocksMessage(getBlocksMessage)
                            } else {
                                print("Error: Received malformed \(message.command) message")
                            }
                        } else if message.command == .blocks {
                            if let blocksMessage = try? BlocksMessage.deserialize(message.payload) {
                                strongSelf.delegate?.didReceiveBlocksMessage(blocksMessage)
                            } else {
                                print("Error: Received malformed \(message.command) message")
                            }
                        } else {
                            print("Received unknown Message: \(message)")
                        }
                    } else {
                        print("Could not deserialize Message!")
                    }
                }
                newConnection.start(queue: strongSelf.queue)
                self?.connections.append(newConnection)
            }
        }
        listener.start(queue: .main)
    }
}


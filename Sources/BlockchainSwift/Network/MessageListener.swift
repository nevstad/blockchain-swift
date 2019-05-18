//
//  NodeServer.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 13/04/2019.
//

import Foundation
import os.log

public protocol MessageListenerDelegate {
    func didReceiveVersionMessage(_ message: VersionMessage, from: NodeAddress)
    func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage, from: NodeAddress)
    func didReceiveTransactionsMessage(_ message: TransactionsMessage, from: NodeAddress)
    func didReceiveGetBlocksMessage(_ message: GetBlocksMessage, from: NodeAddress)
    func didReceiveBlocksMessage(_ message: BlocksMessage, from: NodeAddress)
}

protocol MessageListener {
    var delegate: MessageListenerDelegate? { get set }
    func start()
    func stop()
}

extension MessageListener {
    func handleMessage(_ message: Message, from: NodeAddress) {
        if message.command == .version {
            if let versionMessage = try? VersionMessage.deserialize(message.payload) {
                delegate?.didReceiveVersionMessage(versionMessage, from: from)
            } else {
                os_log("Received malformed %s message", type: .error, message.command.description)
            }
        } else if message.command == .getTransactions {
            if let getTransactionsMessage = try? GetTransactionsMessage.deserialize(message.payload) {
                delegate?.didReceiveGetTransactionsMessage(getTransactionsMessage, from: from)
            } else {
                os_log("Received malformed %s message", type: .error, message.command.description)
            }
        } else if message.command == .transactions {
            if let transactionsMessage = try? TransactionsMessage.deserialize(message.payload) {
                delegate?.didReceiveTransactionsMessage(transactionsMessage, from: from)
            } else {
                os_log("Received malformed %s message", type: .error, message.command.description)
            }
        } else if message.command == .getBlocks {
            if let getBlocksMessage = try? GetBlocksMessage.deserialize(message.payload) {
                delegate?.didReceiveGetBlocksMessage(getBlocksMessage, from: from)
            } else {
                os_log("Received malformed %s message", type: .error, message.command.description)
            }
        } else if message.command == .blocks {
            if let blocksMessage = try? BlocksMessage.deserialize(message.payload) {
                delegate?.didReceiveBlocksMessage(blocksMessage, from: from)
            } else {
                os_log("Received malformed %s message", type: .error, message.command.description)
            }
        } else {
            os_log("Received unknown %s message", type: .error, message.command.description)
        }
    }
}

#if canImport(Network)
import Network

/// The MessageListener handles all incoming connections to a Node
@available(iOS 12.0, macOS 10.14, *)
public class NWListenerMessageListener: MessageListener {
    public var listener: NWListener?
    public let queue: DispatchQueue
    public var connections = [NWConnection]()
    private var port: UInt32
    
    var delegate: MessageListenerDelegate?
    
    init(port: UInt32) {
        self.port = port
        queue = DispatchQueue(label: "Node Server Queue")
    }
    
    private func handleConnection(_ newConnection: NWConnection) {
        newConnection.receive(minimumIncompleteLength: 1, maximumLength: 13371337) { [weak self] (data, context, isComplete, error) in
            if let data = data, let message = try? Message.deserialize(data), let strongSelf = self {
                strongSelf.handleMessage(message, from: NodeAddress(host: newConnection.endpoint.host!, port: message.fromPort))
            } else {
                os_log("Could not deserialize message", type: .error)
            }
        }
        newConnection.start(queue: queue)
        connections.append(newConnection)
        os_log("New connection: %s", type: .info, newConnection.debugDescription)
    }
    
    func start() {
        listener = nil
        listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: UInt16(port))!)
        listener?.stateUpdateHandler = { newState in
            if case .ready = newState {
                os_log("Listener is now open", type: .info)
            }
        }
        listener?.newConnectionHandler = { [weak self] newConnection in
            if let strongSelf = self {
                strongSelf.handleConnection(newConnection)
            }
        }
        listener?.start(queue: queue)
    }
    
    func stop() {
        listener?.cancel()
        connections.removeAll()
    }
}

extension NWEndpoint {
    var host: String? {
        if case .hostPort(let host, _) = self {
            switch host {
            case .ipv4(let addr):
                var bytes: [UInt8] = []
                addr.rawValue.forEach { bytes.append($0) }
                return bytes.map { String($0) }.joined(separator: ".")
            case .ipv6(let addr):
                if let ipv4addr = addr.asIPv4 {
                    var bytes: [UInt8] = []
                    ipv4addr.rawValue.forEach { bytes.append($0) }
                    return bytes.map { String($0) }.joined(separator: ".")
                } else {
                    return nil
                }
            default:
                return nil
            }
        } else {
            return nil
        }
    }
}
#endif

#if canImport(NIO)
import NIO

public class NIOMessageListener: MessageListener {
    private var host: String
    private var port: Int
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var messageHandler: MessageHandler
    internal var delegate: MessageListenerDelegate?
    
    init(host: String, port: Int) {
        self.host = host
        self.port = port
        messageHandler = MessageHandler()
        messageHandler.listener = self
        
        start()
    }
    
    func start() {
        DispatchQueue.global().async {
            do {
                let channel = try self.serverBootstrap.bind(host: self.host, port: self.port).wait()
                os_log("%s is now open", type: .info, channel.localAddress!.description)
                try channel.closeFuture.wait()
            } catch let error {
                print(error)
                return
            }
        }
    }
    
    func stop() {
        do {
            try group.syncShutdownGracefully()
        } catch let error {
            print("Could not shutdown gracefully - forcing exit (\(error.localizedDescription))")
        }
        print("Server closed")
    }
    
    final class MessageCodec: ByteToMessageDecoder {
        public typealias InboundIn = ByteBuffer
        public typealias InboundOut = ByteBuffer
        
        public func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
            let bytes = buffer.withUnsafeReadableBytes { Data($0) }
            if let _ = try? Message.deserialize(bytes) {
                context.fireChannelRead(self.wrapInboundOut(buffer.readSlice(length: bytes.count)!))
                return .continue
            }
            return .needMoreData
        }
        
        public func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
            return try self.decode(context: context, buffer: &buffer)
        }
    }
    
    final class MessageHandler: ChannelInboundHandler {
        public typealias InboundIn = ByteBuffer
        public typealias OutboundOut = ByteBuffer
        
        // All access to channels is guarded by channelsSyncQueue.
        private let channelsSyncQueue = DispatchQueue(label: "messagesQueue")
        private var channels: [ObjectIdentifier: Channel] = [:]
        var listener: MessageListener?
        
        public func channelActive(context: ChannelHandlerContext) {
            let channel = context.channel
            self.channelsSyncQueue.async {
                self.channels[ObjectIdentifier(channel)] = channel
            }
        }
        
        public func channelInactive(context: ChannelHandlerContext) {
            let channel = context.channel
            self.channelsSyncQueue.async {
                if self.channels.removeValue(forKey: ObjectIdentifier(channel)) != nil {
                }
            }
        }
        
        public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            //            let id = ObjectIdentifier(context.channel)
            var read = self.unwrapInboundIn(data)
            var messageData = Data()
            while let byte: UInt8 = read.readInteger() {
                messageData.append(byte)
            }
            if let message = try? Message.deserialize(messageData) {
                if let listener = listener {
                    listener.handleMessage(message, from: NodeAddress(host: context.remoteAddress!.host!, port: message.fromPort))
                }
            } else {
                os_log("Could not deserialize message", type: .error)
            }
        }
        
        public func errorCaught(context: ChannelHandlerContext, error: Error) {
            os_log("Error: %s", type: .error, error.localizedDescription)
            
            // As we are not really interested getting notified on success or failure we just pass nil as promise to
            // reduce allocations.
            context.close(promise: nil)
        }
    }
    
    private var serverBootstrap: ServerBootstrap {
        return ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                   // Add handler that will buffer data until a full Message can be decoded
                channel.pipeline.addHandler(ByteToMessageHandler(MessageCodec())).flatMap { v in
                    // It's important we use the same handler for all accepted channels. The MessageHandler is thread-safe!
                    channel.pipeline.addHandler(self.messageHandler)
                }
            }
            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }
}

extension SocketAddress {
    var host: String? {
        switch self {
        case .v4(let addr):
            return addr.host
        case .v6(let addr):
            return addr.host
        default:
            return nil
        }
    }
}
#endif

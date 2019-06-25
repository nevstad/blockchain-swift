//
//  Network.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 11/06/2019.
//

import Foundation
import os.log


/// The MessageSender handles a an outgoing connection to another Node
protocol MessageSender {
    var pingSendTimes: [NodeAddress : Date] { get set }
    func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)?)
}

extension MessageSender {
    func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        return send(command: command, payload: payload, to: to, completion: completion)
    }
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
    public mutating func sendPing(to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        pingSendTimes[to] = Date()
        send(command: .ping, payload: PingMessage(), to: to, completion: completion)
    }
    public func sendPong(to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        send(command: .pong, payload: PongMessage(), to: to, completion: completion)
    }
}

public protocol MessageListenerDelegate {
    func didReceiveVersionMessage(_ message: VersionMessage, from: NodeAddress)
    func didReceiveGetTransactionsMessage(_ message: GetTransactionsMessage, from: NodeAddress)
    func didReceiveTransactionsMessage(_ message: TransactionsMessage, from: NodeAddress)
    func didReceiveGetBlocksMessage(_ message: GetBlocksMessage, from: NodeAddress)
    func didReceiveBlocksMessage(_ message: BlocksMessage, from: NodeAddress)
    func didReceivePingMessage(_ message: PingMessage, from: NodeAddress)
    func didReceivePongMessage(_ message: PongMessage, from: NodeAddress)
}

protocol MessageListener {
    var pongReceiveTimes: [NodeAddress: Date] { get set }
    var delegate: MessageListenerDelegate? { get set }
    func start()
    func stop()
}

@available(iOS 10.0, OSX 10.14, *)
extension MessageListener {
    mutating func handleMessage(_ message: Message, from: NodeAddress) {
        os_log("Received %s message from %s", type: .error, message.command.description, from.urlString)
        switch message.command {
        case .version:
            if let versionMessage = try? VersionMessage.deserialize(message.payload) {
                delegate?.didReceiveVersionMessage(versionMessage, from: from)
                return
            }
        case .getTransactions:
            if let getTransactionsMessage = try? GetTransactionsMessage.deserialize(message.payload) {
                delegate?.didReceiveGetTransactionsMessage(getTransactionsMessage, from: from)
                return
            }
        case .transactions:
            if let transactionsMessage = try? TransactionsMessage.deserialize(message.payload) {
                delegate?.didReceiveTransactionsMessage(transactionsMessage, from: from)
                return
            }
        case .getBlocks:
            if let getBlocksMessage = try? GetBlocksMessage.deserialize(message.payload) {
                delegate?.didReceiveGetBlocksMessage(getBlocksMessage, from: from)
                return
            }
        case .blocks:
            if let blocksMessage = try? BlocksMessage.deserialize(message.payload) {
                delegate?.didReceiveBlocksMessage(blocksMessage, from: from)
                return
            }
        case .ping:
            if let pingMessage = try? PingMessage.deserialize(message.payload) {
                delegate?.didReceivePingMessage(pingMessage, from: from)
                return
            }
        case .pong:
            if let pongMessage = try? PongMessage.deserialize(message.payload) {
                pongReceiveTimes[from] = Date()
                delegate?.didReceivePongMessage(pongMessage, from: from)
                return
            }
        }
        os_log("Received malformed %s message", type: .error, message.command.description)
    }
}

typealias NetworkProvider = MessageSender & MessageListener

#if canImport(Network)
import Network

@available(iOS 12.0, OSX 10.14, *)
public class NWNetwork: NetworkProvider {
    
    private var queue: DispatchQueue
    private var listener: NWListener?
    private var port: UInt32
    
    public var pingSendTimes = [NodeAddress : Date]()
    public var pongReceiveTimes = [NodeAddress : Date]()
    public var delegate: MessageListenerDelegate?

    public init(port listenPort: UInt32) {
        queue = DispatchQueue(label: "NetworkProvider Queue")
        port = listenPort
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
    }
    
    internal func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        let message = Message(command: command, payload: payload.serialized(), fromPort: port)
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(to.host), port: NWEndpoint.Port(rawValue: UInt16(to.port))!)
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.start(queue: queue)
        connection.send(content: message.serialized(), contentContext: .defaultStream, isComplete: false, completion: .contentProcessed({ (error) in
            if let error = error {
                os_log("Sending %s message failed: %s", type: .error, command.rawValue, error.debugDescription)
            } else {
                connection.send(content: nil, contentContext: .defaultStream, isComplete: true, completion: .contentProcessed({ (error) in
                    os_log("Sent %s message", type: .info, message.command.description)
                    connection.cancel()
                    completion?(error == nil)
                }))
            }
        }))
    }
    
    private func handleConnection(_ newConnection: NWConnection) {
        newConnection.receiveMessage() { [weak self] (data, context, isComplete, error) in
            if let data = data, let message = try? Message.deserialize(data), var strongSelf = self {
                let from = NodeAddress(host: newConnection.endpoint.host!, port: message.fromPort)
                strongSelf.handleMessage(message, from: from)
                if message.command == .ping {
                    strongSelf.send(command: .pong, payload: PongMessage(), to: from, completion: nil)
                }
            } else {
                os_log("Could not deserialize message", type: .error)
            }
        }
        newConnection.start(queue: queue)
        os_log("New connection: %s", type: .info, newConnection.debugDescription)
    }
}

@available(iOS 12.0, OSX 10.14, *)
extension NWEndpoint {
    var host: String? {
        if case .hostPort(let host, _) = self {
            switch host {
            case .ipv4(let addr):
                var output = Data(count: Int(INET_ADDRSTRLEN))
                var address = addr
                guard let presentationBytes = output.withUnsafeMutableBytes({ bytes in
                    inet_ntop(AF_INET, &address, bytes, socklen_t(INET_ADDRSTRLEN))
                }) else {
                    return nil
                }
                return String(cString: presentationBytes)
            case .ipv6(let addr):
                var output = Data(count: Int(INET6_ADDRSTRLEN))
                var address = addr
                guard let presentationBytes = output.withUnsafeMutableBytes({
                    inet_ntop(AF_INET6, &address, $0, socklen_t(INET6_ADDRSTRLEN))
                }) else {
                    return nil
                }
                return String(cString: presentationBytes)
            case .name(let name, _):
                return name
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

@available(iOS 12.0, OSX 10.14, *)
public class NIONetwork: NetworkProvider {
    private var host: String
    private var port: Int
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let sgroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let messageHandler: MessageHandler

    public var pingSendTimes = [NodeAddress : Date]()
    public var pongReceiveTimes = [NodeAddress : Date]()
    public var delegate: MessageListenerDelegate?
    
    private var bootstrap: ClientBootstrap {
        return ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    }
    private var serverBootstrap: ServerBootstrap {
        return ServerBootstrap(group: sgroup)
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
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }
    
    init(host: String = "127.0.0.1", port: Int) {
        self.host = host
        self.port = port
        messageHandler = MessageHandler()
        messageHandler.network = self
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
    
    internal func send(command: Message.Command, payload: Serializable, to: NodeAddress, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global().async {
            do {
                let channel = try self.bootstrap.connect(host: to.host, port: Int(to.port)).wait()
                let message = Message(command: command, payload: payload.serialized(), fromPort: UInt32(self.port)).serialized()
                var buffer = channel.allocator.buffer(capacity: message.count)
                buffer.writeBytes(message)
                try channel.writeAndFlush(buffer).wait()
                try channel.close().wait()
                os_log("Sent %s message", type: .info, command.description)
            } catch let error {
                os_log("Sending %s message failed: %s", type: .error, command.rawValue, error.localizedDescription)
                return
            }
        }
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
        var network: NIONetwork?

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
                if var network = network {
                    let from = NodeAddress(host: context.remoteAddress!.host!, port: message.fromPort)
                    network.handleMessage(message, from: from)
                    if message.command == .ping {
                        network.send(command: .pong, payload: PongMessage(), to: from)
                    }
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

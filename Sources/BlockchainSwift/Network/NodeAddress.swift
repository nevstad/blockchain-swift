//
//  NodeAddress.swift
//  App
//
//  Created by Magnus Nevstad on 10/04/2019.
//

import Foundation

public struct NodeAddress: Codable {
    public let host: String
    public let port: UInt32

    public var urlString: String {
        get {
            return "\(host):\(port)"
        }
    }
    public var url: URL {
        get {
            return URL(string: urlString)!
        }
    }
}

extension NodeAddress: Equatable {
    public static func == (lhs: NodeAddress, rhs: NodeAddress) -> Bool {
        return lhs.port == rhs.port && lhs.host == rhs.host
    }
}

extension NodeAddress {
    // For simplicity's sake we hard code the central node address
    static var centralAddress: NodeAddress = NodeAddress(host: "central.lucidity.network", port: 1337)
    
    public static func randomPort() -> UInt32 {
        return UInt32.random(in: (1338...13337))
    }
    
    public var isCentralNode: Bool {
        get {
            return self == NodeAddress.centralAddress
        }
    }
}

//
//  NodeAddress.swift
//  App
//
//  Created by Magnus Nevstad on 10/04/2019.
//

import Foundation

let nodePort = 1337
let centralNodeAddress = "central.lucidity.network"
/*
public struct NodeAddress: Codable {
    public let host: String
    public let port: UInt32

    public var urlString: String {
        get {
            return "http://\(host):\(port)"
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
    public static func centralAddress() -> NodeAddress {
        return NodeAddress(host: "central.lucidity.network", port: 8080)
    }
    
    public var isCentralNode: Bool {
        get {
            return self == NodeAddress.centralAddress()
        }
    }
}
*/

//
//  UnspentTransaction.swift
//  BlockchainSwiftWallet
//
//  Created by Magnus Nevstad on 30/04/2019.
//  Copyright © 2019 Magnus Nevstad. All rights reserved.
//

import Foundation

// Unspent transactions are the basis for what Coins any given wallet owns
public struct UnspentTransaction: Codable {
    public let output: TransactionOutput
    public let outpoint: TransactionOutputReference
    
    public init(output: TransactionOutput, outpoint: TransactionOutputReference) {
        self.output = output
        self.outpoint = outpoint
    }
}

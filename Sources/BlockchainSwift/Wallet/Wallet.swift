//
//  Wallet.swift
//  App
//
//  Created by Magnus Nevstad on 03/04/2019.
//

import Foundation

protocol TransactionSigner {
    func sign(utxos: [UnspentTransaction]) throws -> [TransactionInput]
    func sign(utxo: UnspentTransaction) throws -> Data
}

public class Wallet: TransactionSigner {
    /// Key pair
    public let secPrivateKey: SecKey
    public let secPublicKey: SecKey
    
    /// Public Key represented as data
    public let publicKey: Data
    
    /// This wallet's address in readable format, double SHA256 hash'ed
    public var address: Data
    
    /// The name of this wallet
    public var name: String
    
    public init(name: String, keyPair: KeyPair) {
        self.name = name
        self.secPrivateKey = keyPair.privateKey
        self.secPublicKey = keyPair.publicKey
        self.publicKey = Keygen.copyExternalRepresentation(key: keyPair.publicKey)!
        self.address = self.publicKey.toAddress()
    }
    
    /// Initalizes a Wallet with randomly generated keys
    public convenience init?(name: String, storeInKeychain: Bool = false) {
        if let keyPair = Keygen.generateKeyPair(name: name, storeInKeychain: storeInKeychain) {
            self.init(name: name, keyPair: keyPair)
        } else {
            return nil
        }
    }

    /// Initalizes a Wallet with keys restored from private key data
    /// - Parameter privateKeyData: The private key data
    public convenience init?(name: String, privateKeyData: Data, storeInKeychain: Bool = false) {
        if let keyPair = Keygen.generateKeyPair(name: name, privateKeyData: privateKeyData, storeInKeychain: storeInKeychain) {
            self.init(name: name, keyPair: keyPair)
        } else {
            return nil
        }
    }

    /// Initalizes a Wallet with keys restored from private key hex
    /// - Parameter privateKeyHex: The private key hex
    public convenience init?(name: String, privateKeyHex: String, storeInKeychain: Bool = false) {
        if let keyPair = Keygen.generateKeyPair(name: name, privateKeyHex: privateKeyHex, storeInKeychain: storeInKeychain) {
            self.init(name: name, keyPair: keyPair)
        } else {
            return nil
        }
    }

    /// Signs a Transaction's inputs with this Wallet's privateKey
    /// - Parameter utxos: Unspent transaction outputs (utxo) represent spendable coins
    public func sign(utxos: [UnspentTransaction]) throws -> [TransactionInput] {
        var signedInputs = [TransactionInput]()
        for utxo in utxos {
            let signature = try sign(utxo: utxo)
            let signedTxIn = TransactionInput(previousOutput: utxo.outpoint, publicKey: publicKey, signature: signature)
            signedInputs.append(signedTxIn)
        }
        return signedInputs
    }

    /// Signs a TransactionOutput with this Wallet's privateKey
    /// - Parameter utxo: Unspent transaction output (utxo) represents spendable coins
    public func sign(utxo: UnspentTransaction) throws -> Data {
        return try Keysign.sign(data: utxo.outpoint.hash, with: secPrivateKey)
    }
    
    /// Checks if Unspent Transaction Outputs (utxo) can be unlocked by this Wallet
    public func canUnlock(utxos: [TransactionOutput]) -> Bool {
        return utxos.reduce(true, { (res, output) -> Bool in
            return res && output.isLockedWith(publicKeyHash: address)
        })
    }
    
    /// Exports the private key as Data
    public func exportPrivateKey() -> Data? {
        return Keygen.copyExternalRepresentation(key: secPrivateKey)
    }
}

// Helper for attempting to create a Wallet address from (hex) string
public extension Data {
    init?(walletAddress: String) {
        if let data = Data(hex: walletAddress), data.count == 32 {
            self = data
        } else {
            return nil
        }
    }
}

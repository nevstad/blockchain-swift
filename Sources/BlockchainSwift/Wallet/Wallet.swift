//
//  Wallet.swift
//  App
//
//  Created by Magnus Nevstad on 03/04/2019.
//

import Foundation

public class Wallet {
    /// Key pair
    private let secPrivateKey: SecKey
    private let secPublicKey: SecKey
    
    /// Public Key represented as data
    public let publicKey: Data
    
    /// This wallet's address in readable format, double SHA256 hash'ed
    public var address: Data
    
    /// Initalizes a Wallet with randomly generated keys
    public init?() {
        if let keyPair = ECDSA.generateKeyPair(), let publicKeyCopy = ECDSA.copyExternalRepresentation(key: keyPair.publicKey) {
            self.secPrivateKey = keyPair.privateKey
            self.secPublicKey = keyPair.publicKey
            self.publicKey = publicKeyCopy
            self.address = self.publicKey.toAddress()
        } else {
            return nil
        }
    }

    /// Initalizes a Wallet with keys restored from private key data
    /// - Parameter privateKeyData: The private key data
    public init?(privateKeyData: Data) {
        if let keyPair = ECDSA.generateKeyPair(privateKeyData: privateKeyData), let publicKeyCopy = ECDSA.copyExternalRepresentation(key: keyPair.publicKey) {
            self.secPrivateKey = keyPair.privateKey
            self.secPublicKey = keyPair.publicKey
            self.publicKey = publicKeyCopy
            self.address = self.publicKey.toAddress()
        } else {
            return nil
        }
    }

    /// Initalizes a Wallet with keys restored from private key hex
    /// - Parameter privateKeyHex: The private key hex
    public init?(privateKeyHex: String) {
        if let keyPair = ECDSA.generateKeyPair(privateKeyHex: privateKeyHex), let publicKeyCopy = ECDSA.copyExternalRepresentation(key: keyPair.publicKey) {
            self.secPrivateKey = keyPair.privateKey
            self.secPublicKey = keyPair.publicKey
            self.publicKey = publicKeyCopy
            self.address = self.publicKey.toAddress()
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
        return try ECDSA.sign(data: utxo.outpoint.hash, with: secPrivateKey)
    }
    
    /// Checks if Unspent Transaction Outputs (utxo) can be unlocked by this Wallet
    public func canUnlock(utxos: [TransactionOutput]) -> Bool {
        return utxos.reduce(true, { (res, output) -> Bool in
            return res && output.isLockedWith(publicKeyHash: address)
        })
    }
    
    /// Exports the private key as Data
    public func exportPrivateKey() -> Data? {
        return ECDSA.copyExternalRepresentation(key: secPrivateKey)
    }
}

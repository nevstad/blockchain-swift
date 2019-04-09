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
    
    public init?() {
        if let keyPair = ECDSA.generateKeyPair(), let publicKeyCopy = ECDSA.copyExternalRepresentation(key: keyPair.publicKey) {
            self.secPrivateKey = keyPair.privateKey
            self.secPublicKey = keyPair.publicKey
            self.publicKey = publicKeyCopy
            self.address = self.publicKey.sha256().sha256()
        } else {
            return nil
        }
    }

    /// Signs a Transaction
    /// - Unspent transaction outputs (txos) represent spendable coins
    public func sign(utxos: [TransactionOutput]) throws -> [TransactionInput] {
        // Define Transaction
        var signedInputs = [TransactionInput]()
        for (i, utxo) in utxos.enumerated() {
            // Sign transaction hash
            var error: Unmanaged<CFError>?
            let txOutputDataHash = utxo.hash
            guard let signature = SecKeyCreateSignature(self.secPrivateKey,
                                                        .ecdsaSignatureDigestX962SHA256,
                                                        txOutputDataHash as CFData,
                                                        &error) as Data? else {
                                                            throw error!.takeRetainedValue() as Error
            }
            // Update TransactionInput
            let prevOut = TransactionOutPoint(hash: txOutputDataHash, index: UInt32(i))
            let signedTxIn = TransactionInput(previousOutput: prevOut, publicKey: self.publicKey, signature: signature)
            signedInputs.append(signedTxIn)
        }
        return signedInputs
    }

    public func sign(utxo: TransactionOutput) throws -> Data {
        // Sign transaction hash
        var error: Unmanaged<CFError>?
        let txOutputDataHash = utxo.serialized().sha256()
        guard let signature = SecKeyCreateSignature(self.secPrivateKey,
                                                    .ecdsaSignatureDigestX962SHA256,
                                                    txOutputDataHash as CFData,
                                                    &error) as Data? else {
                                                        throw error!.takeRetainedValue() as Error
        }
        return signature
    }
    
    public func canUnlock(utxos: [TransactionOutput]) -> Bool {
        return utxos.reduce(true, { (res, output) -> Bool in
            return res && output.isLockedWith(publicKeyHash: self.address)
        })
    }
}

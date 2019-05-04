//
//  Wallet+QRCode.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 05/05/2019.
//

import CoreImage

extension Wallet {
    // Generate a QR-code image of the private key
    public func generateQRCode() -> CIImage? {
        guard let privateKeyData = exportPrivateKey(), let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrFilter.setValue(privateKeyData, forKey: "inputMessage")
        return qrFilter.outputImage
    }
}

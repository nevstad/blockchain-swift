//
//  Wallet+QRCode.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 05/05/2019.
//

import CoreImage

protocol QRCodeRepresentable {
    func generateQRCode() -> CIImage?
}

extension Data: QRCodeRepresentable {
    public func generateQRCode() -> CIImage? {
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrFilter.setValue(self, forKey: "inputMessage")
        return qrFilter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    }
}

extension String: QRCodeRepresentable {
    public func generateQRCode() -> CIImage? {
        return data(using: .utf8)?.generateQRCode()
    }
}

extension Wallet: QRCodeRepresentable {
    // Generate a QR-code image of the private key
    public func generateQRCode() -> CIImage? {
        return exportPrivateKey()?.hex.generateQRCode()
    }
}

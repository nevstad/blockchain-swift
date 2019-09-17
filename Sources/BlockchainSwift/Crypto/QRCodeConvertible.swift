//
//  Wallet+QRCode.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 05/05/2019.
//

import CoreImage

@available(iOS 10.0, OSX 10.12, *)
public protocol QRCodeConvertible {
    func generateQRCode() -> CIImage?
    var qrCode: Data? { get }
}

@available(iOS 10.0, OSX 10.12, *)
public extension QRCodeConvertible {
    func generateQRCode() -> CIImage? {
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrFilter.setValue(qrCode, forKey: "inputMessage")
        qrFilter.setValue("L", forKey: "inputCorrectionLevel")
        return qrFilter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    }
}

@available(iOS 10.0, OSX 10.12, *)
extension String: QRCodeConvertible {
    public var qrCode: Data? {
        return self.data(using: .ascii)
    }
}

@available(iOS 10.0, OSX 10.12, *)
extension Data: QRCodeConvertible {
    public var qrCode: Data? {
        return self
    }
}

@available(iOS 10.0, OSX 10.12, *)
extension SecKey: QRCodeConvertible {
    public var qrCode: Data? {
        return Keygen.copyExternalRepresentation(key: self)?.hex.qrCode
    }
}

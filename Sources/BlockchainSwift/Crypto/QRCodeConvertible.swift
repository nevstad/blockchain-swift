//
//  Wallet+QRCode.swift
//  BlockchainSwift
//
//  Created by Magnus Nevstad on 05/05/2019.
//

import CoreImage

@available(iOS 10.0, OSX 10.12, *)
protocol QRCodeConvertible {
    func generateQRCode() -> CIImage?
    var qrCodeString: String { get }
}

@available(iOS 10.0, OSX 10.12, *)
extension QRCodeConvertible {
    public func generateQRCode() -> CIImage? {
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrFilter.setValue(qrCodeString.data(using: .utf8), forKey: "inputMessage")
        qrFilter.setValue("L", forKey: "inputCorrectionLevel")
        return qrFilter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
    }
}

extension String: QRCodeConvertible {
    public var qrCodeString: String {
        return self
    }
}

extension Data: QRCodeConvertible {
    public var qrCodeString: String {
        return String(data: self, encoding: .utf8)!
    }
}

@available(iOS 10.0, OSX 10.12, *)
extension SecKey: QRCodeConvertible {
    var qrCodeString: String {
        return Keygen.copyExternalRepresentation(key: self)!.hex
    }
}

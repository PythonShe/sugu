// Checks a Sparkle EdDSA signature of a file against a public key, both
// base64 as Sparkle writes them:
//   swift scripts/check-ed-signature.swift <public key> <signature> <file>
// Exits 0 when the signature is valid.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4,
      let key = Data(base64Encoded: arguments[1]),
      let signature = Data(base64Encoded: arguments[2]),
      let data = FileManager.default.contents(atPath: arguments[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key) else {
    FileHandle.standardError.write(Data("usage: check-ed-signature.swift <public key> <signature> <file>\n".utf8))
    exit(2)
}
exit(publicKey.isValidSignature(signature, for: data) ? 0 : 1)

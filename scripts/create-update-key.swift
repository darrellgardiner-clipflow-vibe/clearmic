import CryptoKit
import Foundation

// The private signing seed stays outside the repo with owner-only permissions.
let manager = FileManager.default
let directory = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true).appendingPathComponent("ClearMic/Signing")
try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let keyURL = directory.appendingPathComponent("ed25519.key")
let key: Curve25519.Signing.PrivateKey
if manager.fileExists(atPath: keyURL.path) {
    guard let data = Data(base64Encoded: try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else {
        fatalError("Existing signing key is invalid. Refusing to replace it.")
    }
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
} else {
    key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.base64EncodedString().write(to: keyURL, atomically: true, encoding: .utf8)
}
try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
try manager.createDirectory(atPath: "Release", withIntermediateDirectories: true)
try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: "Release/public-key.txt", atomically: true, encoding: .utf8)
print("Public key saved in Release/public-key.txt. Private key stays in Application Support/ClearMic/Signing.")

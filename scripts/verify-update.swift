import CryptoKit
import Foundation

final class Enclosure: NSObject, XMLParserDelegate {
    let filename: String
    var signature: String?
    var length: Int?
    init(filename: String) { self.filename = filename }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard name == "enclosure", let url = attributes["url"], URL(string: url)?.lastPathComponent == filename else { return }
        signature = attributes["sparkle:edSignature"]
        length = attributes["length"].flatMap(Int.init)
    }
}

enum VerificationError: Error { case arguments, invalidFeed, invalidKey, lengthMismatch, signatureMismatch }
do {
    guard CommandLine.arguments.count == 4 else { throw VerificationError.arguments }
    let paths = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
    let keyText = try String(contentsOf: paths[0], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let keyData = Data(base64Encoded: keyText) else { throw VerificationError.invalidKey }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let enclosure = Enclosure(filename: paths[2].lastPathComponent)
    let parser = XMLParser(data: try Data(contentsOf: paths[1]))
    parser.delegate = enclosure
    guard parser.parse(), let encodedSignature = enclosure.signature,
          let signature = Data(base64Encoded: encodedSignature) else { throw VerificationError.invalidFeed }
    let archive = try Data(contentsOf: paths[2])
    guard enclosure.length == archive.count else { throw VerificationError.lengthMismatch }
    guard key.isValidSignature(signature, for: archive) else { throw VerificationError.signatureMismatch }
    print("Update archive size and Ed25519 signature verified using the public key.")
} catch {
    fputs("Update verification failed: \(error)\n", stderr)
    exit(1)
}

//
//  FxACrypto.swift
//  Reynard
//
//  Crypto primitives used by Mozilla account sign-in and Firefox Sync.
//  Everything here is iOS 13 compatible (CryptoKit + CommonCrypto).
//

import CommonCrypto
import CryptoKit
import Foundation
import Security

nonisolated enum FxACryptoError: Error, LocalizedError {
    case randomGenerationFailed
    case invalidInput(String)
    case unsupportedAlgorithm(String)
    case hmacMismatch
    case cipherFailure(Int32)

    var errorDescription: String? {
        switch self {
        case .randomGenerationFailed:
            return "Could not generate secure random bytes."
        case let .invalidInput(detail):
            return "Invalid crypto input: \(detail)"
        case let .unsupportedAlgorithm(name):
            return "Unsupported algorithm: \(name)"
        case .hmacMismatch:
            return "Record HMAC verification failed."
        case let .cipherFailure(status):
            return "AES operation failed (\(status))."
        }
    }
}

// MARK: - Base64

nonisolated enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

// MARK: - Primitives

nonisolated enum FxACrypto {
    static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw FxACryptoError.randomGenerationFailed
        }
        return Data(bytes)
    }

    static func randomBase64URL(byteCount: Int) throws -> String {
        Base64URL.encode(try randomBytes(byteCount))
    }

    /// A 12 character, URL safe identifier, the format Sync uses for record IDs.
    static func makeSyncGUID() -> String {
        let bytes = (try? randomBytes(9)) ?? Data(UUID().uuidString.utf8.prefix(9))
        return Base64URL.encode(bytes)
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    static func hmacSHA256(key: Data, data: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))
        return Data(mac)
    }

    static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) {
            difference |= left ^ right
        }
        return difference == 0
    }

    static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func aes256CBC(
        encrypt: Bool,
        key: Data,
        iv: Data,
        input: Data
    ) throws -> Data {
        guard key.count == kCCKeySizeAES256 else {
            throw FxACryptoError.invalidInput("AES key must be 32 bytes")
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw FxACryptoError.invalidInput("AES IV must be 16 bytes")
        }

        var output = Data(count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var produced = 0
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputBuffer in
            input.withUnsafeBytes { inputBuffer in
                iv.withUnsafeBytes { ivBuffer in
                    key.withUnsafeBytes { keyBuffer in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            key.count,
                            ivBuffer.baseAddress,
                            inputBuffer.baseAddress,
                            input.count,
                            outputBuffer.baseAddress,
                            outputCapacity,
                            &produced
                        )
                    }
                }
            }
        }

        guard status == CCCryptorStatus(kCCSuccess) else {
            throw FxACryptoError.cipherFailure(status)
        }
        output.count = produced
        return output
    }
}

// MARK: - PKCE

nonisolated struct PKCEPair {
    let verifier: String
    let challenge: String

    static func generate() throws -> PKCEPair {
        // 32 random bytes encode to a 43 character verifier (RFC 7636 minimum).
        let verifier = try FxACrypto.randomBase64URL(byteCount: 32)
        let challenge = Base64URL.encode(FxACrypto.sha256(Data(verifier.utf8)))
        return PKCEPair(verifier: verifier, challenge: challenge)
    }
}

// MARK: - Scoped keys (JWE, ECDH-ES + A256GCM)

/// The ephemeral key pair used to receive scoped keys (kSync) from the
/// Mozilla account server. The public half is sent as `keys_jwk` when
/// starting the OAuth flow; the server answers with a `keys_jwe`.
nonisolated struct ScopedKeysFlow {
    let privateKey: P256.KeyAgreement.PrivateKey

    init() {
        privateKey = P256.KeyAgreement.PrivateKey()
    }

    init(rawRepresentation: Data) throws {
        privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: rawRepresentation)
    }

    var rawRepresentation: Data {
        privateKey.rawRepresentation
    }

    func publicJWK() -> [String: String] {
        // Raw representation is the uncompressed point without the 0x04 prefix: x || y.
        let raw = privateKey.publicKey.rawRepresentation
        let x = raw.prefix(32)
        let y = raw.suffix(32)
        return [
            "crv": "P-256",
            "kty": "EC",
            "x": Base64URL.encode(Data(x)),
            "y": Base64URL.encode(Data(y)),
        ]
    }

    /// Value for the `keys_jwk` authorization parameter.
    func keysJWKParameter() throws -> String {
        let json = try JSONSerialization.data(withJSONObject: publicJWK(), options: [.sortedKeys])
        return Base64URL.encode(json)
    }

    /// Decrypts a compact JWE produced by the account server.
    func decrypt(jwe: String) throws -> Data {
        let parts = jwe.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else {
            throw FxACryptoError.invalidInput("JWE must have 5 segments")
        }
        let protectedHeaderB64 = parts[0]
        guard parts[1].isEmpty else {
            throw FxACryptoError.invalidInput("ECDH-ES JWE must not carry an encrypted key")
        }
        guard let headerData = Base64URL.decode(protectedHeaderB64),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let iv = Base64URL.decode(parts[2]),
              let ciphertext = Base64URL.decode(parts[3]),
              let tag = Base64URL.decode(parts[4]) else {
            throw FxACryptoError.invalidInput("Malformed JWE segments")
        }

        guard header["alg"] as? String == "ECDH-ES" else {
            throw FxACryptoError.unsupportedAlgorithm(header["alg"] as? String ?? "nil")
        }
        guard let enc = header["enc"] as? String, enc == "A256GCM" else {
            throw FxACryptoError.unsupportedAlgorithm(header["enc"] as? String ?? "nil")
        }
        guard let epk = header["epk"] as? [String: Any],
              epk["crv"] as? String == "P-256",
              let xString = epk["x"] as? String,
              let yString = epk["y"] as? String,
              let x = Base64URL.decode(xString),
              let y = Base64URL.decode(yString),
              x.count == 32, y.count == 32 else {
            throw FxACryptoError.invalidInput("JWE epk must be a P-256 public key")
        }

        let peerKey = try P256.KeyAgreement.PublicKey(rawRepresentation: x + y)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: peerKey)
        let z: Data = sharedSecret.withUnsafeBytes { Data($0) }

        let apu = header["apu"] as? String ?? ""
        let apv = header["apv"] as? String ?? ""
        let contentKey = Self.concatKDF(z: z, algorithmID: enc, apu: apu, apv: apv)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: iv),
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(
            sealedBox,
            using: SymmetricKey(data: contentKey),
            authenticating: Data(protectedHeaderB64.utf8)
        )
    }

    /// RFC 7518 section 4.6 Concat KDF, single round (key length 256 <= hash length).
    static func concatKDF(z: Data, algorithmID: String, apu: String, apv: String) -> Data {
        var buffer = Data()
        buffer.append(bigEndian32(1))
        buffer.append(z)
        for field in [algorithmID, apu, apv] {
            let bytes = Data(field.utf8)
            buffer.append(bigEndian32(UInt32(bytes.count)))
            buffer.append(bytes)
        }
        buffer.append(bigEndian32(256))
        return FxACrypto.sha256(buffer)
    }

    private static func bigEndian32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}

// MARK: - Hawk (Sync storage auth)

nonisolated struct HawkCredentials {
    let id: String
    let key: Data
}

nonisolated enum Hawk {
    static func header(
        credentials: HawkCredentials,
        method: String,
        url: URL,
        timestamp: Int64,
        nonce: String,
        ext: String? = nil
    ) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else {
            return nil
        }

        var resource = components.percentEncodedPath
        if resource.isEmpty {
            resource = "/"
        }
        if let query = components.percentEncodedQuery {
            resource += "?" + query
        }
        let port = components.port ?? (components.scheme?.lowercased() == "http" ? 80 : 443)

        let normalized = [
            "hawk.1.header",
            String(timestamp),
            nonce,
            method.uppercased(),
            resource,
            host,
            String(port),
            "",
            ext ?? "",
        ].joined(separator: "\n") + "\n"

        let mac = FxACrypto.hmacSHA256(key: credentials.key, data: Data(normalized.utf8)).base64EncodedString()
        var header = "Hawk id=\"\(credentials.id)\", ts=\"\(timestamp)\", nonce=\"\(nonce)\""
        if let ext, !ext.isEmpty {
            header += ", ext=\"\(ext)\""
        }
        header += ", mac=\"\(mac)\""
        return header
    }
}

// MARK: - Sync record crypto

/// An encryption + HMAC key pair, as used for Sync's crypto/keys and per collection keys.
nonisolated struct SyncKeyBundle: Equatable {
    let encryptionKey: Data
    let hmacKey: Data

    init(encryptionKey: Data, hmacKey: Data) throws {
        guard encryptionKey.count == 32, hmacKey.count == 32 else {
            throw FxACryptoError.invalidInput("Sync keys must be 32 bytes each")
        }
        self.encryptionKey = encryptionKey
        self.hmacKey = hmacKey
    }

    /// The root bundle derived from the 64 byte `kSync` scoped key.
    init(kSync: Data) throws {
        guard kSync.count == 64 else {
            throw FxACryptoError.invalidInput("kSync must be 64 bytes")
        }
        try self.init(encryptionKey: kSync.prefix(32), hmacKey: kSync.suffix(32))
    }

    init(base64Pair: [String]) throws {
        guard base64Pair.count == 2,
              let encryptionKey = Data(base64Encoded: base64Pair[0]),
              let hmacKey = Data(base64Encoded: base64Pair[1]) else {
            throw FxACryptoError.invalidInput("Malformed key pair")
        }
        try self.init(encryptionKey: encryptionKey, hmacKey: hmacKey)
    }

    static func random() throws -> SyncKeyBundle {
        try SyncKeyBundle(encryptionKey: FxACrypto.randomBytes(32), hmacKey: FxACrypto.randomBytes(32))
    }

    var base64Pair: [String] {
        [encryptionKey.base64EncodedString(), hmacKey.base64EncodedString()]
    }

    /// Decrypts a BSO payload string (`{"ciphertext", "IV", "hmac"}`) into a JSON object.
    func decrypt(payload: String) throws -> [String: Any] {
        guard let envelopeData = payload.data(using: .utf8),
              let envelope = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
              let ciphertextB64 = envelope["ciphertext"] as? String,
              let ivB64 = envelope["IV"] as? String,
              let hmacHex = envelope["hmac"] as? String else {
            throw FxACryptoError.invalidInput("Payload is not an encrypted envelope")
        }

        let expected = FxACrypto.hexString(FxACrypto.hmacSHA256(key: hmacKey, data: Data(ciphertextB64.utf8)))
        guard FxACrypto.constantTimeEquals(Data(expected.utf8), Data(hmacHex.lowercased().utf8)) else {
            throw FxACryptoError.hmacMismatch
        }

        guard let ciphertext = Data(base64Encoded: ciphertextB64),
              let iv = Data(base64Encoded: ivB64) else {
            throw FxACryptoError.invalidInput("Envelope is not valid base64")
        }

        let cleartext = try FxACrypto.aes256CBC(encrypt: false, key: encryptionKey, iv: iv, input: ciphertext)
        guard let object = try JSONSerialization.jsonObject(with: cleartext) as? [String: Any] else {
            throw FxACryptoError.invalidInput("Cleartext is not a JSON object")
        }
        return object
    }

    /// Encrypts a JSON object into a BSO payload string.
    func encrypt(_ cleartext: [String: Any]) throws -> String {
        let plaintext = try JSONSerialization.data(withJSONObject: cleartext)
        let iv = try FxACrypto.randomBytes(16)
        let ciphertext = try FxACrypto.aes256CBC(encrypt: true, key: encryptionKey, iv: iv, input: plaintext)
        let ciphertextB64 = ciphertext.base64EncodedString()
        let hmac = FxACrypto.hexString(FxACrypto.hmacSHA256(key: hmacKey, data: Data(ciphertextB64.utf8)))
        let envelope: [String: Any] = [
            "ciphertext": ciphertextB64,
            "IV": iv.base64EncodedString(),
            "hmac": hmac,
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        return String(decoding: envelopeData, as: UTF8.self)
    }
}

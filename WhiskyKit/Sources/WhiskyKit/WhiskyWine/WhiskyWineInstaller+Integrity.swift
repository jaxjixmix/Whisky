//
//  WhiskyWineInstaller+Integrity.swift
//  WhiskyKit
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import CryptoKit
import Foundation
import os.log

extension WhiskyWineInstaller {
    /// SHA-256 of a file, streamed so a large archive is never loaded whole.
    static func sha256(ofFileAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
        } catch {
            Logger.wineKit.error("Failed to hash runtime archive: \(error, privacy: .public)")
            return nil
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Verify a base64 Ed25519 signature over `payload`.
    static func verifySignature(
        base64 signature: String,
        payload: Data,
        publicKeyBase64: String? = nil
    ) -> Bool {
        guard let keyString = publicKeyBase64 ?? runtimePublicKeyBase64,
              let keyData = Data(base64Encoded: keyString),
              let signatureData = Data(base64Encoded: signature),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return false
        }
        return publicKey.isValidSignature(signatureData, for: payload)
    }

    /// The app's pinned manifest key, with the Sparkle key as the default.
    static var runtimePublicKeyBase64: String? {
        Bundle.main.object(forInfoDictionaryKey: "WhiskyRuntimePublicKey") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }

    /// Verify the archive hash and, when present, the manifest signature.
    static func verify(tarball: URL, manifest: WhiskyWineVersion) throws {
        guard let expected = manifest.sha256?.lowercased(), !expected.isEmpty else {
            try requireIntegrity("WhiskyWine manifest has no sha256")
            return
        }
        guard let actual = sha256(ofFileAt: tarball), actual == expected else {
            throw WhiskyWineInstallError.checksumMismatch
        }

        guard let signature = manifest.signature, !signature.isEmpty else {
            try requireIntegrity("WhiskyWine manifest has no signature")
            return
        }
        guard verifySignature(base64: signature, payload: Data(manifest.signingPayload.utf8)) else {
            throw WhiskyWineInstallError.invalidSignature
        }
    }

    /// Debug builds warn when integrity metadata is missing; release builds
    /// refuse to install an unsigned runtime.
    private static func requireIntegrity(_ message: String) throws {
        #if DEBUG
        Logger.wineKit.warning("\(message, privacy: .public)")
        #else
        throw WhiskyWineInstallError.missingIntegrityMetadata
        #endif
    }

    /// Fetch and decode the remote version manifest, bounded to 1 MB.
    static func fetchRemoteVersion() async -> WhiskyWineVersion? {
        guard let url = URL(string: versionPlistURLString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        return await withCheckedContinuation { continuation in
            URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
                guard error == nil,
                      let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      http.expectedContentLength <= Int64(maxManifestBytes),
                      let data,
                      data.count <= maxManifestBytes else {
                    continuation.resume(returning: nil)
                    return
                }
                do {
                    let info = try PropertyListDecoder().decode(WhiskyWineVersion.self, from: data)
                    continuation.resume(returning: info)
                } catch {
                    Logger.wineKit.warning(
                        "Failed to decode the WhiskyWine manifest: \(error, privacy: .public)"
                    )
                    continuation.resume(returning: nil)
                }
            }.resume()
        }
    }
}

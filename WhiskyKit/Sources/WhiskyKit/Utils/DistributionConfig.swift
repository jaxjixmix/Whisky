//
//  DistributionConfig.swift
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

import Foundation

/// URLs the app uses for runtime and app distribution. The release pipeline can
/// override the two base URLs in Info.plist without changing code.
public enum DistributionConfig {
    public static var baseURL: String {
        override("WhiskyDistributionBaseURL") ?? "https://jaxjixmix.github.io/Whisky"
    }

    public static var releasesBaseURL: String {
        override("WhiskyReleasesBaseURL")
            ?? "https://github.com/jaxjixmix/Whisky/releases/download"
    }

    public static var versionPlistURL: String {
        "\(baseURL)/WhiskyWineVersion.plist"
    }

    public static var appcastURL: String {
        "\(baseURL)/appcast.xml"
    }

    public static var releasesPageURL: String {
        "https://github.com/jaxjixmix/Whisky/releases"
    }

    /// The runtime archive for a Wine Libraries release (`v<version>` tag).
    public static func librariesURL(version: String) -> String {
        "\(releasesBaseURL)/v\(version)/Libraries.tar.gz"
    }

    private static func override(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

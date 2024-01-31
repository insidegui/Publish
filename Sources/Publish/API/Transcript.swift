/**
*  Publish
*  Copyright (c) John Sundell 2019
*  MIT license, see LICENSE file for details
*/

import Foundation
import Plot
import Codextended

/// A representation of a location's transcript as specified
/// by the RSS Namespace Extension for Podcast Transcripts.
/// https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/1.0.md#transcript
public struct Transcript: Hashable {
    /// Enum that defines transcript formats supported
    /// by the RSS Namespace Extension for Podcast Transcripts.
    public enum MimeType: String, Codable {
        case srt = "application/srt"
        case vtt = "text/vtt"
        case json = "application/json"
        case html = "text/html"
    }

    /// Enum that defines values for the `rel` attribute in podcast transcripts.
    public enum Rel: String, Codable {
        /// Content represents closed captions.
        case captions
    }

    /// The URL of the transcript file. Should be an absolute URL.
    public var url: URL
    /// The mime type of the transcript. See `MimeType`.
    public var mimeType: MimeType
    /// The language represented by the transcript file.
    public var language: Language?
    /// Can be set to `.captions` if the content is for closed captions.
    public var rel: Rel?

    /// Initialize a new instance of this type.
    /// - parameter url: The URL of the transcript file.
    /// - parameter format: The format of the transcript.
    /// - parameter language: The language represented by the transcript file.
    /// - parameter rel: The `rel` attribute for the transcript tag.
    public init(url: URL,
                mimeType: MimeType,
                language: Language? = nil,
                rel: Rel? = nil) {
        self.url = url
        self.mimeType = mimeType
        self.language = language
        self.rel = rel
    }
}

extension Transcript: Codable {

    public init(from decoder: Decoder) throws {
        url = try decoder.decode("url")
        mimeType = try decoder.decode("mimeType")
        language = try decoder.decodeIfPresent("language", as: String.self).flatMap({ Language(rawValue: $0) })
        rel = try decoder.decodeIfPresent("rel")
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.encode(url, for: "url")
        try encoder.encode(mimeType, for: "mimeType")
        try encoder.encode(language?.rawValue, for: "language")
        try encoder.encode(rel, for: "rel")
    }

}

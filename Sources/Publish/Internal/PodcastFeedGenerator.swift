/**
*  Publish
*  Copyright (c) John Sundell 2019
*  MIT license, see LICENSE file for details
*/

import Foundation
import Plot
import CollectionConcurrencyKit

public struct PodcastFeedGenerator<Site: Website> where Site.ItemMetadata: PodcastCompatibleWebsiteItemMetadata {

    let sectionID: Site.SectionID
    let itemPredicate: Predicate<Item<Site>>?
    let itemMutations: Mutations<Item<Site>>?
    let config: PodcastFeedConfiguration<Site>
    let context: PublishingContext<Site>
    let date: Date
    let formattedDate: String?

    public init(sectionID: Site.SectionID, itemPredicate: Predicate<Item<Site>>?, itemMutations: Mutations<Item<Site>>?, config: PodcastFeedConfiguration<Site>, context: PublishingContext<Site>, date: Date, formattedDate: String? = nil) {
        self.sectionID = sectionID
        self.itemPredicate = itemPredicate
        self.itemMutations = itemMutations
        self.config = config
        self.context = context
        self.date = date
        self.formattedDate = formattedDate
    }

    public func generate() async throws {
        let cacheFileName = config.targetPath.string.replacingOccurrences(of: "/", with: "-")
        let outputFile = try context.createOutputFile(at: config.targetPath)
        let cacheFile = try context.cacheFile(named: cacheFileName)
        let oldCache = try? cacheFile.read().decoded() as Cache
        let section = context.sections[sectionID]
        var items = section.items.sorted(by: { $0.date > $1.date })

        if let predicate = itemPredicate?.inverse() {
            items.removeAll(where: predicate.matches)
        }

        if let date = context.lastGenerationDate, let cache = oldCache {
            if cache.config == config, cache.itemCount == items.count {
                let newlyModifiedItem = items.first { $0.lastModified > date }

                guard newlyModifiedItem != nil else {
                    return try outputFile.write(cache.feed)
                }
            }
        }

        let feed = try await makeFeed(containing: items, section: section)
            .render(indentedBy: config.indentation)

        let newCache = Cache(config: config, feed: feed, itemCount: items.count)
        try cacheFile.write(newCache.encoded())
        try outputFile.write(feed)
    }
}

private extension PodcastFeedGenerator {
    struct Cache: Codable {
        let config: PodcastFeedConfiguration<Site>
        let feed: String
        let itemCount: Int
    }

    func makeFeed(containing items: [Item<Site>],
                  section: Section<Site>) async throws -> PodcastFeed {
        try PodcastFeed(
            .unwrap(config.newFeedURL, Node.newFeedURL),
            .title(config.title ?? context.site.name),
            .description(config.description),
            .link(config.linkURL ?? context.site.url(for: section)),
            .language(context.site.language),
            /// Use pre-formatted date if available.
            /// This was introduced in order to workaround a crash on Linux (https://github.com/apple/swift/issues/69496)
            .unwrap(formattedDate, { dateString in
                    .group([
                        .element(named: "lastBuildDate", text: dateString),
                        .element(named: "pubDate", text: dateString)
                    ])
            }, else: .group([
                .lastBuildDate(date, timeZone: context.dateFormatter.timeZone),
                .pubDate(date, timeZone: context.dateFormatter.timeZone),
            ])),
            .ttl(Int(config.ttlInterval)),
            .atomLink(context.site.url(for: config.targetPath)),
            .unwrap(config.webSubHubURL, { url in
                .selfClosedElement(named: "atom:link", attributes: [
                    .attribute(named: "href", value: url.absoluteString),
                    .attribute(named: "rel", value: "hub")
                ])
            }),
            .copyright(config.copyrightText),
            .author(config.author.name),
            .subtitle(config.subtitle),
            .summary(config.description),
            .explicit(config.isExplicit),
            .owner(
                .name(config.author.name),
                .email(config.author.emailAddress)
            ),
            .category(
                config.category,
                .unwrap(config.subcategory) { .category($0) }
            ),
            .type(config.type),
            .image(config.imageURL),
            .group(await items.concurrentMap {
                let item: Item<Site>

                if let mutations = itemMutations {
                    var mutatedItem = $0
                    try mutations(&mutatedItem)
                    item = mutatedItem
                } else {
                    item = $0
                }

                guard let audio = item.audio else {
                    throw PodcastError(path: item.path, reason: .missingAudio)
                }

                guard let audioDuration = audio.duration else {
                    throw PodcastError(path: item.path, reason: .missingAudioDuration)
                }

                guard let audioSize = audio.byteSize else {
                    throw PodcastError(path: item.path, reason: .missingAudioSize)
                }

                let title = item.rssTitle
                let metadata = item.metadata.podcast
                let imageURL = item.imagePath.flatMap { path in
                    URL(string: path.absoluteString)
                }

                return .item(
                    .guid(for: item, site: context.site),
                    .title(title),
                    .description(item.description),
                    .link(context.site.url(for: item)),
                    .pubDate(item.date, timeZone: context.dateFormatter.timeZone),
                    .content(for: item, site: context.site),
                    .author(config.author.name),
                    .subtitle(item.description),
                    .summary(item.description),
                    .explicit(metadata?.isExplicit ?? false),
                    .duration(audioDuration),
                    .unwrap(imageURL, Node.image),
                    .unwrap(metadata?.episodeNumber, Node.episodeNumber),
                    .unwrap(metadata?.seasonNumber, Node.seasonNumber),
                    .audio(
                        url: audio.url,
                        byteSize: audioSize,
                        type: "audio/\(audio.format.rawValue)",
                        title: title
                    )
                )
            })
        )
    }
}

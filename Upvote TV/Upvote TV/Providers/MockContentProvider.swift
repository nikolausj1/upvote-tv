import Foundation

struct MockContentProvider: ContentProvider {
    func postsStream(deprioritizing watchedIDs: Set<String>) -> AsyncThrowingStream<[Post], Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Simulate network delay
                try? await Task.sleep(for: .milliseconds(800))
                continuation.yield(Self.samplePosts)
                continuation.finish()
            }
        }
    }

    // MARK: - Sample Data

    private static let now = Date()
    private static func shared(_ secondsAgo: TimeInterval) -> Date {
        now.addingTimeInterval(-secondsAgo)
    }
    private static func resolved(_ secondsAgo: TimeInterval) -> Date {
        now.addingTimeInterval(-secondsAgo)
    }

    /// Sorted newest `sharedAt` first.
    static let samplePosts: [Post] = unsortedSamplePosts.sorted { lhs, rhs in
        (lhs.sharedAt ?? lhs.createdAt) > (rhs.sharedAt ?? rhs.createdAt)
    }

    private static let unsortedSamplePosts: [Post] = [
        // Direct YouTube — Short
        Post(
            id: "yt_short_1",
            title: "Chef shows the fastest way to break down a whole chicken #shorts",
            subreddit: nil,
            author: "Knife Skills Daily",
            createdAt: shared(60 * 30),
            postType: .youtube,
            thumbnailURL: URL(string: "https://picsum.photos/seed/ytshort1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/ytshort1/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://www.youtube.com/shorts/aBcDeFgHiJk"),
            domain: "youtube.com",
            isNSFW: false,
            score: nil,
            sharedAt: shared(60 * 15),
            resolvedAt: resolved(60 * 14)
        ),

        // Direct YouTube — full-length video
        Post(
            id: "yt_full_1",
            title: "Building a Synthesizer from Scratch — Part 3: Envelopes and Filters",
            subreddit: nil,
            author: "Moogulator",
            createdAt: shared(60 * 60 * 4),
            postType: .youtube,
            thumbnailURL: URL(string: "https://picsum.photos/seed/ytfull1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/ytfull1/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://www.youtube.com/watch?v=ZyXwVuT1234"),
            domain: "youtube.com",
            isNSFW: false,
            score: nil,
            sharedAt: shared(60 * 45),
            resolvedAt: resolved(60 * 44)
        ),

        // Direct YouTube — live stream
        Post(
            id: "yt_live_1",
            title: "LIVE: International Space Station Earth Viewing",
            subreddit: nil,
            author: "NASA",
            createdAt: shared(60 * 60 * 2),
            postType: .youtube,
            thumbnailURL: URL(string: "https://picsum.photos/seed/ytlive1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/ytlive1/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://youtu.be/liveStream123"),
            domain: "youtu.be",
            isNSFW: false,
            score: nil,
            sharedAt: shared(60 * 90),
            resolvedAt: resolved(60 * 89)
        ),

        // Reddit video - hosted v.redd.it
        Post(
            id: "t3_mock_video_1",
            title: "Incredible time-lapse of the Northern Lights over Iceland last night",
            subreddit: "space",
            author: "aurora_chaser",
            createdAt: shared(3600),
            postType: .video,
            thumbnailURL: URL(string: "https://picsum.photos/seed/vid1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/vid1/1920/1080"),
            mediaURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "v.redd.it",
            isNSFW: false,
            score: 48_291,
            sharedAt: shared(60 * 120),
            resolvedAt: resolved(60 * 119)
        ),

        // Reddit video - another one
        Post(
            id: "t3_mock_video_2",
            title: "My cat discovered the robot vacuum and I can't stop laughing",
            subreddit: "funny",
            author: "catdad_supreme",
            createdAt: shared(7200),
            postType: .video,
            thumbnailURL: URL(string: "https://picsum.photos/seed/vid2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/vid2/1920/1080"),
            mediaURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "v.redd.it",
            isNSFW: false,
            score: 31_445,
            sharedAt: shared(60 * 180),
            resolvedAt: resolved(60 * 179)
        ),

        // Reddit image - landscape
        Post(
            id: "t3_mock_image_1",
            title: "Caught this perfect reflection at Moraine Lake yesterday morning",
            subreddit: "EarthPorn",
            author: "mountain_lens",
            createdAt: shared(5400),
            postType: .image,
            thumbnailURL: URL(string: "https://picsum.photos/seed/img1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/img1/1920/1080"),
            mediaURL: URL(string: "https://picsum.photos/seed/img1full/3840/2160"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "i.redd.it",
            isNSFW: false,
            score: 67_832,
            sharedAt: shared(60 * 240),
            resolvedAt: resolved(60 * 239)
        ),

        // Reddit image - portrait
        Post(
            id: "t3_mock_image_2",
            title: "My grandmother turned 100 today. She still makes pasta from scratch every Sunday.",
            subreddit: "pics",
            author: "italian_family",
            createdAt: shared(14400),
            postType: .image,
            thumbnailURL: URL(string: "https://picsum.photos/seed/img2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/img2/1920/1080"),
            mediaURL: URL(string: "https://picsum.photos/seed/img2full/1920/2560"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "i.redd.it",
            isNSFW: false,
            score: 142_500,
            sharedAt: shared(60 * 300),
            resolvedAt: resolved(60 * 299)
        ),

        // Reddit text - long
        Post(
            id: "t3_mock_text_1",
            title: "I finally paid off my student loans after 12 years. Here's what I learned.",
            subreddit: "personalfinance",
            author: "debt_free_2026",
            createdAt: shared(10800),
            postType: .text,
            thumbnailURL: nil,
            previewImageURL: nil,
            mediaURL: nil,
            galleryItems: nil,
            textBody: """
            After 12 years, 144 monthly payments, and a lot of ramen noodles, I finally made my last student loan payment today.

            Here's what I wish someone had told me when I graduated:

            1. **Pay more than the minimum.** Even an extra $50/month made a huge difference over time. I set up automatic payments for the minimum, then manually added extra whenever I could.

            2. **Refinancing saved me thousands.** I refinanced twice \u{2014} once when rates dropped and again when my credit score improved. Went from 6.8% to 3.2%.

            3. **The avalanche method works.** I listed all my loans by interest rate and attacked the highest one first. Mathematically optimal and it felt great watching the expensive ones disappear.

            4. **Lifestyle creep is the real enemy.** Every raise I got, I split 50/50 between loan payments and savings. The temptation to upgrade everything is real.

            5. **Track your progress visually.** I kept a simple spreadsheet with a chart. Watching that line go down kept me motivated during the years when it felt endless.

            The total I paid: $87,342 on an original balance of $64,000. That extra $23k was all interest. Let that sink in.

            If you're in the middle of paying yours off, keep going. It does end.
            """,
            outboundURL: nil,
            domain: "self.personalfinance",
            isNSFW: false,
            score: 28_903,
            sharedAt: shared(60 * 360),
            resolvedAt: resolved(60 * 359)
        ),

        // Reddit text - short
        Post(
            id: "t3_mock_text_2",
            title: "TIL that octopuses have three hearts and blue blood",
            subreddit: "todayilearned",
            author: "ocean_facts",
            createdAt: shared(28800),
            postType: .text,
            thumbnailURL: nil,
            previewImageURL: nil,
            mediaURL: nil,
            galleryItems: nil,
            textBody: "Two of their hearts pump blood to the gills, while the third pumps it to the rest of the body. Their blood is blue because it uses copper-based hemocyanin instead of iron-based hemoglobin. The gill hearts actually stop beating when they swim, which is why they prefer crawling \u{2014} swimming exhausts them.",
            outboundURL: nil,
            domain: "self.todayilearned",
            isNSFW: false,
            score: 51_200,
            sharedAt: shared(60 * 420),
            resolvedAt: resolved(60 * 419)
        ),

        // Reddit gallery
        Post(
            id: "t3_mock_gallery_1",
            title: "Renovated our 1960s kitchen on a budget - before and after photos",
            subreddit: "HomeImprovement",
            author: "diy_or_die",
            createdAt: shared(18000),
            postType: .gallery,
            thumbnailURL: URL(string: "https://picsum.photos/seed/gal1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/gal1p1/1920/1080"),
            mediaURL: nil,
            galleryItems: [
                GalleryItem(id: "gal1_1", imageURL: URL(string: "https://picsum.photos/seed/gal1p1/1920/1440")!, width: 1920, height: 1440, position: 0),
                GalleryItem(id: "gal1_2", imageURL: URL(string: "https://picsum.photos/seed/gal1p2/1920/1440")!, width: 1920, height: 1440, position: 1),
                GalleryItem(id: "gal1_3", imageURL: URL(string: "https://picsum.photos/seed/gal1p3/1920/1440")!, width: 1920, height: 1440, position: 2),
                GalleryItem(id: "gal1_4", imageURL: URL(string: "https://picsum.photos/seed/gal1p4/1920/1440")!, width: 1920, height: 1440, position: 3),
                GalleryItem(id: "gal1_5", imageURL: URL(string: "https://picsum.photos/seed/gal1p5/1920/1440")!, width: 1920, height: 1440, position: 4),
            ],
            textBody: nil,
            outboundURL: nil,
            domain: "reddit.com",
            isNSFW: false,
            score: 15_670,
            sharedAt: shared(60 * 480),
            resolvedAt: resolved(60 * 479)
        ),

        // Reddit gallery - art
        Post(
            id: "t3_mock_gallery_2",
            title: "Watercolor paintings I did during my trip to Japan this spring",
            subreddit: "Art",
            author: "wandering_brush",
            createdAt: shared(43200),
            postType: .gallery,
            thumbnailURL: URL(string: "https://picsum.photos/seed/gal2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/gal2p1/1920/1080"),
            mediaURL: nil,
            galleryItems: [
                GalleryItem(id: "gal2_1", imageURL: URL(string: "https://picsum.photos/seed/gal2p1/1920/1440")!, width: 1920, height: 1440, position: 0),
                GalleryItem(id: "gal2_2", imageURL: URL(string: "https://picsum.photos/seed/gal2p2/1920/1440")!, width: 1920, height: 1440, position: 1),
                GalleryItem(id: "gal2_3", imageURL: URL(string: "https://picsum.photos/seed/gal2p3/1920/1440")!, width: 1920, height: 1440, position: 2),
            ],
            textBody: nil,
            outboundURL: nil,
            domain: "reddit.com",
            isNSFW: false,
            score: 22_100,
            sharedAt: shared(60 * 540),
            resolvedAt: resolved(60 * 539)
        ),

        // YouTube-linked Reddit post
        Post(
            id: "t3_mock_youtube_1",
            title: "How NASA Plans to Build a Base on the Moon by 2030 [26:14]",
            subreddit: "space",
            author: "space_nerd_42",
            createdAt: shared(21600),
            postType: .youtube,
            thumbnailURL: URL(string: "https://picsum.photos/seed/yt1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/yt1/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            domain: "youtube.com",
            isNSFW: false,
            score: 8_420,
            sharedAt: shared(60 * 600),
            resolvedAt: resolved(60 * 599)
        ),

        // YouTube-linked Reddit post
        Post(
            id: "t3_mock_youtube_2",
            title: "The Most Satisfying Video in the World [12:03]",
            subreddit: "oddlysatisfying",
            author: "satisfaction_guaranteed",
            createdAt: shared(40000),
            postType: .youtube,
            thumbnailURL: URL(string: "https://picsum.photos/seed/yt2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/yt2/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://youtu.be/abc123"),
            domain: "youtu.be",
            isNSFW: false,
            score: 45_300,
            sharedAt: shared(60 * 660),
            resolvedAt: resolved(60 * 659)
        ),

        // Reddit link
        Post(
            id: "t3_mock_link_2",
            title: "Scientists discover high-temperature superconductor that works at room pressure",
            subreddit: "science",
            author: "physics_today",
            createdAt: shared(36000),
            postType: .link,
            thumbnailURL: URL(string: "https://picsum.photos/seed/link2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/link2/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://www.nature.com/articles/example"),
            domain: "nature.com",
            isNSFW: false,
            score: 94_100,
            sharedAt: shared(60 * 720),
            resolvedAt: resolved(60 * 719)
        ),

        // NSFW Reddit (filter testing)
        Post(
            id: "t3_mock_nsfw_1",
            title: "Spicy meme compilation - definitely not safe for work",
            subreddit: "memes",
            author: "meme_lord",
            createdAt: shared(25200),
            postType: .image,
            thumbnailURL: URL(string: "https://picsum.photos/seed/nsfw1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/nsfw1/1920/1080"),
            mediaURL: URL(string: "https://picsum.photos/seed/nsfw1full/1920/1080"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "i.redd.it",
            isNSFW: true,
            score: 12_300,
            sharedAt: shared(60 * 780),
            resolvedAt: resolved(60 * 779)
        ),

        // Unsupported Reddit
        Post(
            id: "t3_mock_unsupported_1",
            title: "Check out this interactive data visualization of global temperature changes",
            subreddit: "dataisbeautiful",
            author: "viz_wizard",
            createdAt: shared(50400),
            postType: .unsupported,
            thumbnailURL: URL(string: "https://picsum.photos/seed/unsup1thumb/320/180"),
            previewImageURL: nil,
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://example.com/interactive-viz"),
            domain: "example.com",
            isNSFW: false,
            score: 5_800,
            sharedAt: shared(60 * 840),
            resolvedAt: resolved(60 * 839)
        ),

        // Additional Reddit image
        Post(
            id: "t3_mock_image_3",
            title: "Found this little guy hiding in my garden this morning",
            subreddit: "aww",
            author: "garden_friends",
            createdAt: shared(57600),
            postType: .image,
            thumbnailURL: URL(string: "https://picsum.photos/seed/img3thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/img3/1920/1080"),
            mediaURL: URL(string: "https://picsum.photos/seed/img3full/1920/1080"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "i.redd.it",
            isNSFW: false,
            score: 89_100,
            sharedAt: shared(60 * 900),
            resolvedAt: resolved(60 * 899)
        ),

        // Additional Reddit video
        Post(
            id: "t3_mock_video_3",
            title: "Drone footage of the most remote village in Switzerland",
            subreddit: "travel",
            author: "drone_explorer",
            createdAt: shared(64800),
            postType: .video,
            thumbnailURL: URL(string: "https://picsum.photos/seed/vid3thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/vid3/1920/1080"),
            mediaURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "v.redd.it",
            isNSFW: false,
            score: 19_250,
            sharedAt: shared(60 * 960),
            resolvedAt: resolved(60 * 959)
        ),

        // Additional Reddit text
        Post(
            id: "t3_mock_text_3",
            title: "What's a fact that sounds fake but is completely true?",
            subreddit: "AskReddit",
            author: "curious_mind",
            createdAt: shared(72000),
            postType: .text,
            thumbnailURL: nil,
            previewImageURL: nil,
            mediaURL: nil,
            galleryItems: nil,
            textBody: "I'll start: Cleopatra lived closer in time to the Moon landing than to the construction of the Great Pyramid of Giza. The Great Pyramid was built around 2560 BC, Cleopatra lived around 30 BC, and the Moon landing was in 1969 AD.",
            outboundURL: nil,
            domain: "self.AskReddit",
            isNSFW: false,
            score: 74_500,
            sharedAt: shared(60 * 1020),
            resolvedAt: resolved(60 * 1019)
        ),

        // Additional Reddit link
        Post(
            id: "t3_mock_link_3",
            title: "The best chocolate chip cookie recipe I've ever found - crispy edges, chewy center",
            subreddit: "food",
            author: "baking_daily",
            createdAt: shared(86400),
            postType: .link,
            thumbnailURL: URL(string: "https://picsum.photos/seed/link3thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/link3/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://www.seriouseats.com/example-cookie-recipe"),
            domain: "seriouseats.com",
            isNSFW: false,
            score: 33_800,
            sharedAt: shared(60 * 1080),
            resolvedAt: resolved(60 * 1079)
        ),
    ]
}

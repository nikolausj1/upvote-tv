import Foundation

struct MockContentProvider: ContentProvider {
    func fetchUpvotedPosts() async throws -> [Post] {
        // Simulate network delay
        try await Task.sleep(for: .milliseconds(800))
        return Self.samplePosts
    }

    // MARK: - Sample Data

    static let samplePosts: [Post] = [
        // Video post - Reddit hosted
        Post(
            id: "t3_mock_video_1",
            title: "Incredible time-lapse of the Northern Lights over Iceland last night",
            subreddit: "space",
            author: "aurora_chaser",
            createdAt: Date().addingTimeInterval(-3600),
            postType: .video,
            thumbnailURL: URL(string: "https://picsum.photos/seed/vid1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/vid1/1920/1080"),
            mediaURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "v.redd.it",
            isNSFW: false,
            score: 48_291
        ),

        // Video post - another one
        Post(
            id: "t3_mock_video_2",
            title: "My cat discovered the robot vacuum and I can't stop laughing",
            subreddit: "funny",
            author: "catdad_supreme",
            createdAt: Date().addingTimeInterval(-7200),
            postType: .video,
            thumbnailURL: URL(string: "https://picsum.photos/seed/vid2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/vid2/1920/1080"),
            mediaURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "v.redd.it",
            isNSFW: false,
            score: 31_445
        ),

        // Image post - landscape
        Post(
            id: "t3_mock_image_1",
            title: "Caught this perfect reflection at Moraine Lake yesterday morning",
            subreddit: "EarthPorn",
            author: "mountain_lens",
            createdAt: Date().addingTimeInterval(-5400),
            postType: .image,
            thumbnailURL: URL(string: "https://picsum.photos/seed/img1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/img1/1920/1080"),
            mediaURL: URL(string: "https://picsum.photos/seed/img1full/3840/2160"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "i.redd.it",
            isNSFW: false,
            score: 67_832
        ),

        // Image post - portrait photo
        Post(
            id: "t3_mock_image_2",
            title: "My grandmother turned 100 today. She still makes pasta from scratch every Sunday.",
            subreddit: "pics",
            author: "italian_family",
            createdAt: Date().addingTimeInterval(-14400),
            postType: .image,
            thumbnailURL: URL(string: "https://picsum.photos/seed/img2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/img2/1920/1080"),
            mediaURL: URL(string: "https://picsum.photos/seed/img2full/1920/2560"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "i.redd.it",
            isNSFW: false,
            score: 142_500
        ),

        // Text post - long
        Post(
            id: "t3_mock_text_1",
            title: "I finally paid off my student loans after 12 years. Here's what I learned.",
            subreddit: "personalfinance",
            author: "debt_free_2026",
            createdAt: Date().addingTimeInterval(-10800),
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
            score: 28_903
        ),

        // Text post - short
        Post(
            id: "t3_mock_text_2",
            title: "TIL that octopuses have three hearts and blue blood",
            subreddit: "todayilearned",
            author: "ocean_facts",
            createdAt: Date().addingTimeInterval(-28800),
            postType: .text,
            thumbnailURL: nil,
            previewImageURL: nil,
            mediaURL: nil,
            galleryItems: nil,
            textBody: "Two of their hearts pump blood to the gills, while the third pumps it to the rest of the body. Their blood is blue because it uses copper-based hemocyanin instead of iron-based hemoglobin. The gill hearts actually stop beating when they swim, which is why they prefer crawling \u{2014} swimming exhausts them.",
            outboundURL: nil,
            domain: "self.todayilearned",
            isNSFW: false,
            score: 51_200
        ),

        // Gallery post
        Post(
            id: "t3_mock_gallery_1",
            title: "Renovated our 1960s kitchen on a budget - before and after photos",
            subreddit: "HomeImprovement",
            author: "diy_or_die",
            createdAt: Date().addingTimeInterval(-18000),
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
            score: 15_670
        ),

        // Gallery post - art
        Post(
            id: "t3_mock_gallery_2",
            title: "Watercolor paintings I did during my trip to Japan this spring",
            subreddit: "Art",
            author: "wandering_brush",
            createdAt: Date().addingTimeInterval(-43200),
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
            score: 22_100
        ),

        // YouTube post
        Post(
            id: "t3_mock_youtube_1",
            title: "How NASA Plans to Build a Base on the Moon by 2030 [26:14]",
            subreddit: "space",
            author: "space_nerd_42",
            createdAt: Date().addingTimeInterval(-21600),
            postType: .youtube,
            thumbnailURL: URL(string: "https://picsum.photos/seed/yt1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/yt1/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
            domain: "youtube.com",
            isNSFW: false,
            score: 8_420
        ),

        // YouTube post - short form
        Post(
            id: "t3_mock_youtube_2",
            title: "The Most Satisfying Video in the World [12:03]",
            subreddit: "oddlysatisfying",
            author: "satisfaction_guaranteed",
            createdAt: Date().addingTimeInterval(-40000),
            postType: .youtube,
            thumbnailURL: URL(string: "https://picsum.photos/seed/yt2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/yt2/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://youtu.be/abc123"),
            domain: "youtu.be",
            isNSFW: false,
            score: 45_300
        ),

        // Link post - news article
        Post(
            id: "t3_mock_link_2",
            title: "Scientists discover high-temperature superconductor that works at room pressure",
            subreddit: "science",
            author: "physics_today",
            createdAt: Date().addingTimeInterval(-36000),
            postType: .link,
            thumbnailURL: URL(string: "https://picsum.photos/seed/link2thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/link2/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://www.nature.com/articles/example"),
            domain: "nature.com",
            isNSFW: false,
            score: 94_100
        ),

        // NSFW post (for testing filter)
        Post(
            id: "t3_mock_nsfw_1",
            title: "Spicy meme compilation - definitely not safe for work",
            subreddit: "memes",
            author: "meme_lord",
            createdAt: Date().addingTimeInterval(-25200),
            postType: .image,
            thumbnailURL: URL(string: "https://picsum.photos/seed/nsfw1thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/nsfw1/1920/1080"),
            mediaURL: URL(string: "https://picsum.photos/seed/nsfw1full/1920/1080"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "i.redd.it",
            isNSFW: true,
            score: 12_300
        ),

        // Unsupported post type
        Post(
            id: "t3_mock_unsupported_1",
            title: "Check out this interactive data visualization of global temperature changes",
            subreddit: "dataisbeautiful",
            author: "viz_wizard",
            createdAt: Date().addingTimeInterval(-50400),
            postType: .unsupported,
            thumbnailURL: URL(string: "https://picsum.photos/seed/unsup1thumb/320/180"),
            previewImageURL: nil,
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://example.com/interactive-viz"),
            domain: "example.com",
            isNSFW: false,
            score: 5_800
        ),

        // More posts to fill out the list
        Post(
            id: "t3_mock_image_3",
            title: "Found this little guy hiding in my garden this morning",
            subreddit: "aww",
            author: "garden_friends",
            createdAt: Date().addingTimeInterval(-57600),
            postType: .image,
            thumbnailURL: URL(string: "https://picsum.photos/seed/img3thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/img3/1920/1080"),
            mediaURL: URL(string: "https://picsum.photos/seed/img3full/1920/1080"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "i.redd.it",
            isNSFW: false,
            score: 89_100
        ),

        Post(
            id: "t3_mock_video_3",
            title: "Drone footage of the most remote village in Switzerland",
            subreddit: "travel",
            author: "drone_explorer",
            createdAt: Date().addingTimeInterval(-64800),
            postType: .video,
            thumbnailURL: URL(string: "https://picsum.photos/seed/vid3thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/vid3/1920/1080"),
            mediaURL: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/adv_dv_atmos/main.m3u8"),
            galleryItems: nil,
            textBody: nil,
            outboundURL: nil,
            domain: "v.redd.it",
            isNSFW: false,
            score: 19_250
        ),

        Post(
            id: "t3_mock_text_3",
            title: "What's a fact that sounds fake but is completely true?",
            subreddit: "AskReddit",
            author: "curious_mind",
            createdAt: Date().addingTimeInterval(-72000),
            postType: .text,
            thumbnailURL: nil,
            previewImageURL: nil,
            mediaURL: nil,
            galleryItems: nil,
            textBody: "I'll start: Cleopatra lived closer in time to the Moon landing than to the construction of the Great Pyramid of Giza. The Great Pyramid was built around 2560 BC, Cleopatra lived around 30 BC, and the Moon landing was in 1969 AD.",
            outboundURL: nil,
            domain: "self.AskReddit",
            isNSFW: false,
            score: 74_500
        ),

        Post(
            id: "t3_mock_link_3",
            title: "The best chocolate chip cookie recipe I've ever found - crispy edges, chewy center",
            subreddit: "food",
            author: "baking_daily",
            createdAt: Date().addingTimeInterval(-86400),
            postType: .link,
            thumbnailURL: URL(string: "https://picsum.photos/seed/link3thumb/320/180"),
            previewImageURL: URL(string: "https://picsum.photos/seed/link3/1920/1080"),
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: URL(string: "https://www.seriouseats.com/example-cookie-recipe"),
            domain: "seriouseats.com",
            isNSFW: false,
            score: 33_800
        ),
    ]
}

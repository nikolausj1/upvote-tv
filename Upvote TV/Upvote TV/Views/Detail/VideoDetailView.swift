import SwiftUI
import AVKit

struct VideoDetailView: View {
    let post: Post
    let onMarkWatched: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var showReplay = false
    @State private var hasMarkedWatched = false
    @State private var loadError = false
    @State private var timeObserver: Any?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if loadError {
                MediaErrorView(post: post)
            } else if showReplay {
                replayOverlay
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { teardownPlayer() }
    }

    // MARK: - Replay

    private var replayOverlay: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(post.title)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 80)

            Button {
                replay()
            } label: {
                Label("Replay", systemImage: "arrow.counterclockwise")
                    .font(.title3)
            }
            .buttonStyle(.card)

            Spacer()
        }
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        guard let url = post.mediaURL else {
            loadError = true
            return
        }

        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer

        // Observe playback end
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            showReplay = true
        }

        // Observe errors
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            loadError = true
        }

        // Track playback progress for 85% watched marking
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard !hasMarkedWatched,
                  let duration = avPlayer.currentItem?.duration,
                  duration.isNumeric,
                  duration.seconds > 0 else { return }

            let progress = time.seconds / duration.seconds
            if progress >= 0.85 {
                hasMarkedWatched = true
                onMarkWatched()
            }
        }

        // Also check for item status errors
        avPlayer.currentItem?.publisher(for: \.status)
            .receive(on: RunLoop.main)
            .sink { status in
                if status == .failed {
                    loadError = true
                }
            }
            .store(in: &cancellables)

        avPlayer.play()
    }

    @State private var cancellables = Set<AnyCancellable>()

    private func teardownPlayer() {
        if let observer = timeObserver, let player {
            player.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func replay() {
        showReplay = false
        player?.seek(to: .zero)
        player?.play()
    }
}

import Combine

//
//  ViewController.swift
//  StreamingVideo
//
//  Created by Don Clore on 1/24/23.
//

import UIKit
import AVFoundation
import Combine

enum AVURLAssetLoadingError: Error {
  case tracksloadfailure(NSError?)
  case durationloadfailure(NSError?)
}

class ViewController: UIViewController {
    private static let videoURL =
    URL(
        string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"
    )!
    
    override func loadView() {
        super.loadView()
        let asset = AVURLAsset(url: ViewController.videoURL)
        view = PlayerView(asset: asset)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }
}

extension ViewController {
    class PlayerView: UIView {
        private var subscriptions = Set<AnyCancellable>()
        private let tracksKey: String = "tracks"
        private let durationKey: String = "duration"
        private let group: DispatchGroup = DispatchGroup()

        private var player: AVPlayer?
        var loadingError: AVURLAssetLoadingError?
        
        var playerLayer: AVPlayerLayer {
            return layer as! AVPlayerLayer
        }
        
        override class var layerClass: AnyClass {
            return AVPlayerLayer.self
        }
        
        private let asset: AVURLAsset
        private var isLoaded: Bool = false
        private var tracksLoaded: Bool = false
        private var durationLoaded: Bool = false
        private var isLoadedPublisher: PassthroughSubject<Bool, Never> = PassthroughSubject<Bool, Never>()
        private var playerItemObserver: NSKeyValueObservation?
        
        init(asset: AVURLAsset) {
            self.asset = asset
            super.init(frame: CGRect.zero)
            playerLayer.contentsGravity = CALayerContentsGravity.resizeAspect
            playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
            contentMode = UIView.ContentMode.scaleAspectFit
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(PlayerView.playerDidFinishPlaying(_:)),
                name: Notification.Name.AVPlayerItemDidPlayToEndTime,
                object: nil
            )
                        
            doAllThePropertyLoadingAndThenFireOffTheVideo(asset)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()

            playerLayer.frame = bounds            
        }
    }
}

extension ViewController.PlayerView {
    private func doAllThePropertyLoadingAndThenFireOffTheVideo(_ asset: AVURLAsset) {
        group.enter()  // once for tracks
        group.enter()  // once for duration
                
        // There's a new async-await style way of doing this in iOS 16, and I'm just doing it
        // this way to show I know the old way, because most apps/libraries need to support
        // earlier versions of iOS at this juncture.
        asset.loadValuesAsynchronously(forKeys: [durationKey, tracksKey]) { [weak self] in
            guard let self = self else { return }
            self.assetPropertyLoadHandler()
        }
        
        firePublisherWhenAssetLoaded()
        
        subscribeToAssetLoad(asset)
    }
    
    private func assetPropertyLoadHandler() {
        let name = self.asset.url.lastPathComponent
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var error: NSError?
            let tracksStatus = self.asset.statusOfValue(forKey: self.tracksKey, error: &error)
            if tracksStatus != .loaded {
                let loadError = AVURLAssetLoadingError.tracksloadfailure(error)
                self.loadingError = loadError
                print("\(#function) - error loading tracks for \(name), error = \(loadError)")
            } else {
                self.tracksLoaded = true
                print("\(#function) - asset tracks loaded = \(self.tracksLoaded)")
                self.group.leave()
            }
            
            let durationStatus = self.asset.statusOfValue(forKey: self.durationKey, error: &error)
            if durationStatus != .loaded {
                let loadError = AVURLAssetLoadingError.durationloadfailure(error)
                self.loadingError = loadError
                print("\(#function) - error loading duration for \(name), error = \(loadError)")
                self.isLoaded = false
            } else {
                self.durationLoaded = true
                self.group.leave()
            }
        }
    }
        
    private func firePublisherWhenAssetLoaded() {
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            // The DispatchGroup told us we are ready; but now we're going to switch paradigms and
            // use Combine to publish that fact.
            self.isLoaded = self.durationLoaded && self.tracksLoaded
            self.isLoadedPublisher.send(self.isLoaded)
        }
    }
    
    private func subscribeToAssetLoad(_ asset: AVURLAsset) {
        isLoadedPublisher
            .sink{ isLoaded in
                guard isLoaded else { return } // already printed error messages.
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let playerItem = AVPlayerItem(asset: asset)

                    let playr = AVPlayer(playerItem: playerItem)
                    self.playerLayer.player = playr
                    self.player = playr
                    
                    self.playerItemObserver = playerItem.observe(\AVPlayerItem.status, options: [.new, .old]) { [weak self] _,_ in
                        guard let self = self else { return }
                        guard playerItem.status == .readyToPlay else {
                            return
                        }
                        let period = CMTime(seconds: 5.0, preferredTimescale: 2)
                        self.addPeriodicTimeObserver(withInterval: period) { seconds in
                            let formattedString = String(format: "%.0f", seconds)
                            print("\(#function) - \(formattedString) seconds of video playback elapsed.")
                        }

                        playr.play()
                    }
                }
            }
            .store(in: &subscriptions)
    }
    
    @objc private func playerDidFinishPlaying(_ note: Notification) {
        print("\(#function) - video be done.")
    }
    
    private func addPeriodicTimeObserver(withInterval interval: CMTime, completion: @escaping (_ seconds: TimeInterval) -> Void) {
        guard let player = player else { return }
        player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { progressTime in
            let seconds = CMTimeGetSeconds(progressTime)
            guard seconds > 0.0 else { return }
            completion(seconds)
        }
    }
}


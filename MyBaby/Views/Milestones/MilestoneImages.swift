import CoreData
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Turns picked or taken photos into small JPEGs for `MilestonePhoto` and `DiaryPhoto`, and decodes
/// them again for the screens, off the main thread so long timelines scroll smoothly.
///
/// Photos are stored inside their Core Data record so they're end-to-end encrypted with the rest
/// of the log (external storage would sync as a separate CKAsset, outside the encrypted fields). A CloudKit record
/// holds at most 1 MB, including encryption overhead, so each photo is downscaled to 1600 px on
/// its long side and compressed until it's under about 600 KB.
enum MilestoneImages {
    /// The long side of a stored photo, in pixels.
    static let maxPixelSize: CGFloat = 1600
    /// Comfortably below CloudKit's 1 MB record limit once encrypted.
    static let maxBytes = 600_000

    // MARK: Encoding

    /// A stored-size JPEG from any image file iOS can read (HEIC, JPEG, PNG…), or nil if it can't
    /// be read. Slow for big photos, so call it off the main thread.
    ///
    /// Only the pixels are kept: location and other metadata from the camera are left out.
    static func storableJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Lower the quality step by step; if even that's too big, shrink the picture and try again.
        // It starts at 0.75: at 1600 px that hardly differs from 0.8 on a phone or on paper, and each
        // photo takes roughly a tenth less space on the iPhone, in iCloud and in the partner's copy.
        for size in [maxPixelSize, 1200, 900] {
            guard let image = downsample(source, maxPixelSize: size) else { return nil }
            for quality in [0.75, 0.7, 0.6, 0.5, 0.4, 0.3] {
                if let encoded = jpeg(image, quality: quality), encoded.count <= maxBytes {
                    return encoded
                }
            }
        }
        return nil
    }

    /// The same, for a photo just taken with the camera.
    static func storableJPEG(from image: UIImage) -> Data? {
        // Written out first so ImageIO can apply the photo's orientation while downscaling.
        guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
        return storableJPEG(from: data)
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: Decoding

    /// Decodes `data` at no more than `maxPixelSize` on its long side, without ever holding the
    /// full-size picture in memory. Upright, whatever the camera's orientation was.
    static func downsample(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        return downsample(source, maxPixelSize: maxPixelSize)
    }

    private static func downsample(_ source: CGImageSource, maxPixelSize: CGFloat) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as [CFString: Any] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// Recently shown thumbnails, so scrolling back doesn't decode them again. Limited by the memory
    /// the decoded pixels take as well as by count: a grid thumbnail on a 3× screen is about 420 px
    /// square, some 700 KB, so 300 of them alone could hold 200 MB.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    /// What a decoded image costs in the cache: the bytes of its pixels.
    private static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }

    /// Forgets every cached thumbnail, after Delete all MyBaby data.
    static func removeCachedImages() {
        cache.removeAllObjects()
    }

    /// The photo with `id`, decoded at `maxPixelSize` on a background context. Thumbnails are
    /// cached; full-size pictures (for the viewer and sharing) aren't, since they're large.
    static func image(for id: NSManagedObjectID, maxPixelSize: CGFloat, caches: Bool = true) async -> UIImage? {
        let key = "\(id.uriRepresentation().absoluteString)@\(Int(maxPixelSize))" as NSString
        if caches, let cached = cache.object(forKey: key) { return cached }
        // Unsaved photos only exist in the view context, so there's nothing to read in the background.
        guard !id.isTemporaryID else { return nil }

        let context = PersistenceController.shared.container.newBackgroundContext()
        let decoded: UIImage? = await context.perform {
            // A `MilestonePhoto` or a `DiaryPhoto`: both keep their JPEG in `imageData`.
            guard let photo = try? context.existingObject(with: id),
                  let data = photo.value(forKey: "imageData") as? Data,
                  let cgImage = MilestoneImages.downsample(data, maxPixelSize: maxPixelSize)
            else { return nil }
            context.reset()
            return UIImage(cgImage: cgImage)
        }
        if caches, let decoded {
            cache.setObject(decoded, forKey: key, cost: decoded.cgImage.map(cost(of:)) ?? 0)
        }
        return decoded
    }

    /// Every photo of a milestone or diary entry at full stored size, for the share sheet.
    static func fullImages(for ids: [NSManagedObjectID]) async -> [UIImage] {
        var images: [UIImage] = []
        for id in ids {
            if let decoded = await image(for: id, maxPixelSize: maxPixelSize, caches: false) {
                images.append(decoded)
            }
        }
        return images
    }
}

/// A square photo thumbnail, decoded in the background. A soft placeholder shows meanwhile.
struct MilestoneThumbnail: View {
    let photoID: NSManagedObjectID
    /// Points on each side, or nil to fill the width it's given (in a grid).
    var side: CGFloat? = 64
    var cornerRadius: CGFloat = Radius.photo

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Palette.chipBackground
            .frame(width: side, height: side)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            // The button or row around it says what it is.
            .accessibilityHidden(true)
            .task(id: photoID) {
                // Grid cells are about a third of the screen wide.
                image = await MilestoneImages.image(for: photoID, maxPixelSize: (side ?? 140) * displayScale)
            }
    }
}

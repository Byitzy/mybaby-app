import CoreData
import SwiftUI

/// A milestone's photos full screen on black, swiping between them.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photoIDs: [NSManagedObjectID]
    let title: String
    @State private var selection: Int

    init(photoIDs: [NSManagedObjectID], startIndex: Int, title: String) {
        self.photoIDs = photoIDs
        self.title = title
        _selection = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(photoIDs.enumerated()), id: \.element) { index, id in
                    FullPhoto(photoID: id)
                        .tag(index)
                        .accessibilityLabel("\(title), photo \(index + 1) of \(photoIDs.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photoIDs.count > 1 ? .always : .never))
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(photoIDs.count > 1 ? "\(selection + 1) of \(photoIDs.count)" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .threeAMSheet()
    }
}

/// One photo at its stored size, decoded in the background.
private struct FullPhoto: View {
    let photoID: NSManagedObjectID
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Label("Couldn't open this photo", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .task(id: photoID) {
            image = await MilestoneImages.image(for: photoID, maxPixelSize: MilestoneImages.maxPixelSize, caches: false)
            failed = image == nil
        }
    }
}

import CoreData
import SwiftUI

/// "Sex (for growth charts)": Not set, Girl or Boy. Used in onboarding, Add a baby, Settings and Growth.
struct BabySexPicker: View {
    @Binding var selection: BabySex?

    var body: some View {
        Picker("Sex (for growth charts)", selection: $selection) {
            Text("Not set").tag(BabySex?.none)
            ForEach(BabySex.allCases) { sex in
                Text(sex.title).tag(BabySex?.some(sex))
            }
        }
    }
}

extension Baby {
    /// The baby's sex for a picker, saved as soon as it changes.
    func sexBinding(saving context: NSManagedObjectContext) -> Binding<BabySex?> {
        Binding(
            get: { self.sex },
            set: { newValue in
                self.sex = newValue
                context.saveIfChanged()
            }
        )
    }
}

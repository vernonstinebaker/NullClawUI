import SwiftUI

// MARK: - SearchView

/// Placeholder search tab for future search functionality.
/// This view will eventually provide unified search across all gateways and conversations.
struct SearchView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView.search(text: searchText)
                .navigationTitle("Search")
        }
        .searchable(text: $searchText, prompt: "Search conversations, tasks, agents…")
    }
}

#Preview {
    SearchView()
}


// Your imports remain the same
// Import SwiftUI and Combine only
import SwiftUI
import Combine

struct ContentView: View {
    @State private var key: String = ""
    @State private var value: String = ""
    @State private var storedValue: String = ""
    @State private var allStoredData: [(key: String, value: String)] = []
    @State private var keyUpdateCount: Int = 0

    // Add UserDefaultsPro instance to demonstrate Combine
    @StateObject private var settings = ObservableSettings()

    private let debounceDelay = 0.5
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter key", text: $key)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
                .onChange(of: key) { newValue in
                    handleKeyChange(newValue)
                }

            TextField("Enter value", text: $value)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            HStack(spacing: 20) {
                Button("Save") {
                    UserDefaults.standard.set(value, forKey: key)
                    loadAllStoredData()
                }
                .buttonStyle(.borderedProminent)

                Button("Load") {
                    if let stored = UserDefaults.standard.string(forKey: key) {
                        storedValue = stored
                    } else {
                        storedValue = "No value found for key"
                    }
                }
                .buttonStyle(.bordered)
            }

            Divider()

            Text("Combine Features Demo:")
                .font(.headline)

            Text("Key updates: \(keyUpdateCount)")
                .foregroundColor(.secondary)

            if settings.isDebouncingActive {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(allStoredData, id: \.key) { item in
                        HStack {
                            Text(item.key)
                                .bold()
                            Text(": ")
                            Text(item.value)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .onAppear {
            loadAllStoredData()
        }
    }

    // Add this class as a nested type
    class ObservableSettings: ObservableObject {
        @Published var isDebouncingActive = false
        @UserDefaultsPro(key: "demoValue", defaultValue: "")
        var demoValue: String
    }

    private func handleKeyChange(_ newValue: String) {
        settings.isDebouncingActive = true
        Just(newValue)
            .delay(for: .seconds(debounceDelay), scheduler: RunLoop.main)
            .sink { text in
                settings.isDebouncingActive = false
                keyUpdateCount += 1
                settings.demoValue = text
            }
            .store(in: &cancellables)
    }

    private func loadAllStoredData() {
        allStoredData = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.value is String }
            .map { (key: $0.key, value: $0.value as? String ?? "") }
            .sorted(by: { $0.key < $1.key })
    }
}

// Preview remains the same

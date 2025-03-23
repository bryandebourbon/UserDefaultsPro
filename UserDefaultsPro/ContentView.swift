//
//  ContentView.swift
//  UserDefaultsPro
//
//  Created by Bryan de Bourbon on 3/23/25.
//

import SwiftUI

// Your imports remain the same

struct ContentView: View {
    @State private var key: String = ""
    @State private var value: String = ""
    @State private var storedValue: String = ""
    @State private var allStoredData: [(key: String, value: String)] = []

    var body: some View {
        VStack(spacing: 20) {
            TextField("Enter key", text: $key)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

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

            Text("Stored value: \(storedValue)")
                .padding()

            Text("All Stored Key-Value Pairs:")
                .font(.headline)
                .padding(.top)

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

    private func loadAllStoredData() {
        allStoredData = UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.value is String }
            .map { (key: $0.key, value: $0.value as? String ?? "") }
            .sorted(by: { $0.key < $1.key })
    }
}

// Preview remains the same

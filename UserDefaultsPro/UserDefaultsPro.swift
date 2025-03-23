import Foundation
import Combine

enum UserDefaultError: Error {
    case decodingFailed
    case encodingFailed
    case keyNotFound
    case invalidData
    case typeMismatch
    case accessError
}

@propertyWrapper
final class UserDefaultsPro<T: Codable> {
    private let key: String
    private let defaultValue: T
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "UserDefaultQueue", attributes: .concurrent)
    private var cachedValue: T?

    // Using a private subject that will be recreated for each publisher
    private var updateSubject: PassthroughSubject<T, Never>?

    deinit {
        // Clean up the subject when being deallocated
        updateSubject = nil
    }

    init(key: String, defaultValue: T, userDefaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.userDefaults = userDefaults

        // Initialize with default value if not present
        queue.sync(flags: .barrier) {
            if userDefaults.data(forKey: key) == nil {
                do {
                    let encoded = try JSONEncoder().encode(defaultValue)
                    userDefaults.set(encoded, forKey: key)
                    userDefaults.synchronize()
                } catch {
                    print("Error encoding default value: \(error)")
                }
            }
            self.cachedValue = loadFromUserDefaults()
        }
    }

    var wrappedValue: T {
        get {
            queue.sync {
                if let cached = cachedValue { return cached }
                let value = loadFromUserDefaults()
                cachedValue = value
                return value
            }
        }
        set {
            queue.async(flags: .barrier) {
                self.cachedValue = newValue
                do {
                    let encoded = try JSONEncoder().encode(newValue)
                    self.userDefaults.set(encoded, forKey: self.key)
                    self.userDefaults.synchronize() // Ensure changes are flushed to disk

                    // Send the update via the subject if it exists
                    self.updateSubject?.send(newValue)
                } catch {
                    self.userDefaults.removeObject(forKey: self.key)
                    print("Error encoding value for key \(self.key): \(error)")
                    #if DEBUG
                    assertionFailure("Failed to encode value for UserDefault key \(self.key): \(error)")
                    #endif
                }
            }
        }
    }

    var projectedValue: UserDefaultsPro<T> { self }

    var publisher: AnyPublisher<T, Never> {
        // Create a new subject for this publisher to avoid retain cycles
        let subject = PassthroughSubject<T, Never>()
        updateSubject = subject

        // Return a publisher that starts with the current value and then emits updates
        return Just(wrappedValue)
            .merge(with: subject)
            .eraseToAnyPublisher()
    }

    func getValue() throws -> T {
        try queue.sync {
            // Don't use cached value for getValue() as we want error handling
            guard let data = userDefaults.data(forKey: key) else {
                throw UserDefaultError.keyNotFound
            }

            do {
                let value = try JSONDecoder().decode(T.self, from: data)
                cachedValue = value
                return value
            } catch let decodingError as DecodingError {
                switch decodingError {
                case .typeMismatch:
                    throw UserDefaultError.typeMismatch
                case .dataCorrupted:
                    throw UserDefaultError.invalidData
                default:
                    throw UserDefaultError.decodingFailed
                }
            } catch {
                throw UserDefaultError.accessError
            }
        }
    }

    private func loadFromUserDefaults() -> T {
        guard let data = userDefaults.data(forKey: key) else {
            return defaultValue
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            // Log the error but return the default value
            print("Error decoding value for key \(key): \(error)")
            return defaultValue
        }
    }

    func reset() {
        queue.async(flags: .barrier) {
            self.cachedValue = self.defaultValue
            do {
                let encoded = try JSONEncoder().encode(self.defaultValue)
                self.userDefaults.set(encoded, forKey: self.key)
                self.userDefaults.synchronize() // Ensure changes are flushed to disk

                // Also update any subscribers
                self.updateSubject?.send(self.defaultValue)
            } catch {
                print("Error encoding default value for key \(self.key): \(error)")
            }
        }
    }
}

// MARK: - Usage Example
struct AppSettings {
    @UserDefaultsPro(key: "isDarkMode", defaultValue: false)
    var isDarkMode: Bool

    @UserDefaultsPro(key: "userName", defaultValue: "Guest")
    var userName: String

    func demo() {
        var settings = AppSettings()

        // Direct property access
        settings.isDarkMode = true

        // Using the getValue() method with error handling
        do {
            let darkModeValue = try settings.$isDarkMode.getValue()
            print("Dark Mode is enabled: \(darkModeValue)")
        } catch {
            print("Error retrieving isDarkMode: \(error)")
        }

        // Using Combine to observe changes
        var cancellables = Set<AnyCancellable>()

        settings.$userName.publisher
            .sink { newName in
                print("Username changed to: \(newName)")
            }
            .store(in: &cancellables)

        // This will trigger the publisher
        settings.userName = "JohnDoe"
    }
}



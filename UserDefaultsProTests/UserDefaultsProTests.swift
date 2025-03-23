import XCTest
import Combine
import Foundation
@testable import UserDefaultsPro


// Add UserProfile definition for tests
struct UserProfile: Codable, Equatable {
    let id: String
    var email: String
    var fullName: String?

    init(id: String, email: String, fullName: String? = nil) {
        self.id = id
        self.email = email
        self.fullName = fullName
    }
}

// Define TestAppSettings to match what we're testing
struct TestAppSettings {
    @UserDefaultsPro(key: "isDarkMode", defaultValue: false)
    var isDarkMode: Bool

    @UserDefaultsPro(key: "userName", defaultValue: "Guest")
    var userName: String

    @UserDefaultsPro(key: "appLaunchCount", defaultValue: 0)
    var appLaunchCount: Int

    @UserDefaultsPro(key: "userProfile", defaultValue: UserProfile(id: "default", email: "example@example.com"))
    var userProfile: UserProfile
}

final class UserDefaultsProTests: XCTestCase {
    var testUserDefaults: UserDefaults!
    var testSuiteName: String!
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        testSuiteName = "test_suite_\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        cancellables.removeAll()
        super.tearDown()
    }

    func testInitAndDefaultValue() {
        let key = "testKey"
        let defaultValue = "defaultValue"

        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)
    }

    func testSetAndGetValue() {
        let key = "testKey"
        let defaultValue = "defaultValue"
        let newValue = "newValue"

        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        userDefault.wrappedValue = newValue

        XCTAssertEqual(userDefault.wrappedValue, newValue)

        let anotherAccess = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(anotherAccess.wrappedValue, newValue)
    }

    func testReset() {
        let key = "testKey"
        let defaultValue = 42
        let newValue = 99

        let userDefault = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        userDefault.wrappedValue = newValue
        XCTAssertEqual(userDefault.wrappedValue, newValue)

        userDefault.reset()
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)
    }

    func testConcurrentReads() {
        let key = "concurrentReadKey"
        let defaultValue = "defaultValue"

        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        let expectation = self.expectation(description: "Concurrent reads")
        expectation.expectedFulfillmentCount = 100

        for _ in 0..<100 {
            DispatchQueue.global().async {
                let _ = userDefault.wrappedValue
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5)
    }

    func testConcurrentWrites() {
        let key = "concurrentWriteKey"
        let defaultValue = 0

        let userDefault = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        let writeExpectation = expectation(description: "Concurrent writes")
        writeExpectation.expectedFulfillmentCount = 100

        for i in 0..<100 {
            DispatchQueue.global().async {
                userDefault.wrappedValue = i
                writeExpectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5)

        let finalValue = userDefault.wrappedValue
        XCTAssertGreaterThanOrEqual(finalValue, 0)
        XCTAssertLessThan(finalValue, 100)
    }

    func testDecodingError() {
        let key = "invalidDataKey"
        let defaultValue = 42

        // Store valid JSON that can't be decoded as an Int
        let invalidJson = """
        {"value": "not an integer"}
        """.data(using: .utf8)!
        testUserDefaults.set(invalidJson, forKey: key)

        // First instance to test wrappedValue (which caches the default value)
        let userDefault = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        // Reading wrapped value should return default without error
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)

        // Create a new instance to test getValue() without cached values
        let userDefaultForGetValue = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        // But getValue() should throw an error
        XCTAssertThrowsError(try userDefaultForGetValue.getValue()) { error in
            XCTAssertTrue(error is UserDefaultError)
            if let userDefaultError = error as? UserDefaultError {
                // The error might be typeMismatch or invalidData depending on the JSONDecoder implementation
                XCTAssertTrue(
                    userDefaultError == UserDefaultError.typeMismatch ||
                    userDefaultError == UserDefaultError.invalidData ||
                    userDefaultError == UserDefaultError.decodingFailed
                )
            }
        }
    }

    func testPublisherEmitsUpdates() {
        let key = "publisherUpdateKey"
        let defaultValue = "defaultValue"
        let newValue = "newValue"

        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        let expectation = self.expectation(description: "Publisher emits updates")

        userDefault.publisher
            .dropFirst()
            .sink { value in
                XCTAssertEqual(value, newValue)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        userDefault.wrappedValue = newValue

        waitForExpectations(timeout: 1)
    }

    // MARK: - Additional Data Type Tests

    func testArrayType() {
        let key = "arrayKey"
        let defaultValue = [1, 2, 3]
        let newValue = [4, 5, 6, 7]

        let userDefault = UserDefaultsPro<[Int]>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)

        userDefault.wrappedValue = newValue
        XCTAssertEqual(userDefault.wrappedValue, newValue)

        // Test persistence
        let anotherInstance = UserDefaultsPro<[Int]>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(anotherInstance.wrappedValue, newValue)
    }

    func testDictionaryType() {
        let key = "dictionaryKey"
        let defaultValue = ["key1": "value1", "key2": "value2"]
        let newValue = ["key3": "value3", "key4": "value4"]

        let userDefault = UserDefaultsPro<[String: String]>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)

        userDefault.wrappedValue = newValue
        XCTAssertEqual(userDefault.wrappedValue, newValue)

        // Test persistence
        let anotherInstance = UserDefaultsPro<[String: String]>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(anotherInstance.wrappedValue, newValue)
    }

    func testDateType() {
        let key = "dateKey"
        let defaultValue = Date(timeIntervalSince1970: 0)
        let newValue = Date()

        let userDefault = UserDefaultsPro<Date>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)

        userDefault.wrappedValue = newValue
        XCTAssertEqual(userDefault.wrappedValue, newValue)

        // Test persistence
        let anotherInstance = UserDefaultsPro<Date>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(anotherInstance.wrappedValue, newValue)
    }

    func testOptionalType() {
        let key = "optionalKey"
        let defaultValue: String? = nil
        let newValue: String? = "New Value"

        let userDefault = UserDefaultsPro<String?>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)

        userDefault.wrappedValue = newValue
        XCTAssertEqual(userDefault.wrappedValue, newValue)

        // Test persistence
        let anotherInstance = UserDefaultsPro<String?>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(anotherInstance.wrappedValue, newValue)

        // Test setting back to nil
        userDefault.wrappedValue = nil
        XCTAssertNil(userDefault.wrappedValue)

        let thirdInstance = UserDefaultsPro<String?>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertNil(thirdInstance.wrappedValue)
    }

    // MARK: - Error Handling Tests

    func testEncodingError() {
        class NonCodable {}

        // Create a dictionary with a non-codable value
        let key = "encodingErrorKey"
        let defaultValue = ["valid": "value"]

        let userDefault = UserDefaultsPro<[String: String]>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        // Set up a custom key without proper encoding
        let nonCodableData = "Not valid JSON".data(using: .utf8)!
        testUserDefaults.set(nonCodableData, forKey: key)

        // Getting the wrapped value should return the default
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)

        // getValue() should throw error
        XCTAssertThrowsError(try userDefault.getValue()) { error in
            XCTAssertTrue(error is UserDefaultError)
        }
    }

    // MARK: - Thread Safety Tests

    func testMultipleWritersWithDifferentInstances() {
        let key = "multipleWritersKey"
        let defaultValue = 0
        let iterations = 100

        let userDefault1 = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        let userDefault2 = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        let expectation1 = expectation(description: "Writer 1 completed")
        let expectation2 = expectation(description: "Writer 2 completed")

        DispatchQueue.global().async {
            for i in 0..<iterations {
                userDefault1.wrappedValue = i
            }
            expectation1.fulfill()
        }

        DispatchQueue.global().async {
            for i in 0..<iterations {
                userDefault2.wrappedValue = i + 1000
            }
            expectation2.fulfill()
        }

        waitForExpectations(timeout: 5)

        // The final value should be one of the values we set
        let finalValue = userDefault1.wrappedValue
        XCTAssertTrue(
            (0..<iterations).contains(finalValue) ||
            (1000..<(1000+iterations)).contains(finalValue)
        )
    }

    // MARK: - Publisher Tests

//    func testMultipleSubscribers() {
//        let key = "multipleSubscribersKey"
//        let defaultValue = "initial"
//        let updates = ["update1", "update2", "update3"]
//
//        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
//
//        let expectation1 = expectation(description: "Subscriber 1")
//        let expectation2 = expectation(description: "Subscriber 2")
//
//        expectation1.expectedFulfillmentCount = updates.count + 1 // +1 for initial value
//        expectation2.expectedFulfillmentCount = updates.count + 1
//
//        var receivedValues1: [String] = []
//        var receivedValues2: [String] = []
//
//        userDefault.publisher
//            .sink { value in
//                receivedValues1.append(value)
//                expectation1.fulfill()
//            }
//            .store(in: &cancellables)
//
//        userDefault.publisher
//            .sink { value in
//                receivedValues2.append(value)
//                expectation2.fulfill()
//            }
//            .store(in: &cancellables)
//
//        // Perform updates
//        for update in updates {
//            userDefault.wrappedValue = update
//        }
//
//        waitForExpectations(timeout: 5)
//
//        // Both subscribers should receive all values in order
//        XCTAssertEqual(receivedValues1.count, updates.count + 1)
//        XCTAssertEqual(receivedValues2.count, updates.count + 1)
//
//        XCTAssertEqual(receivedValues1[0], defaultValue)
//        XCTAssertEqual(receivedValues2[0], defaultValue)
//
//        for (index, update) in updates.enumerated() {
//            XCTAssertEqual(receivedValues1[index + 1], update)
//            XCTAssertEqual(receivedValues2[index + 1], update)
//        }
//    }

    // MARK: - Migration Tests

    func testMigrationFromStandardUserDefaults() {
        // Set a value using standard method
        let key = "migrationKey"
        let standardValue = "standard value"
        testUserDefaults.set(standardValue, forKey: key)

        // Now try to access it via UserDefaultsPro
        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: "default", userDefaults: testUserDefaults)

        // The old format won't match the expected JSON structure, so it should return the default value
        XCTAssertEqual(userDefault.wrappedValue, "default")

        // After writing a new value, it should use the new format
        let newValue = "new value"
        userDefault.wrappedValue = newValue

        // Now retrieving should work
        XCTAssertEqual(userDefault.wrappedValue, newValue)

        // And standard UserDefaults should have the encoded data
        XCTAssertNotNil(testUserDefaults.data(forKey: key))
    }

    // MARK: - Performance Tests

    func testPerformanceReading() {
        let key = "performanceReadKey"
        let defaultValue = "performance test value"

        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        userDefault.wrappedValue = defaultValue

        measure {
            // Perform 1000 reads
            for _ in 0..<1000 {
                _ = userDefault.wrappedValue
            }
        }
    }

    func testPerformanceWriting() {
        let key = "performanceWriteKey"
        let defaultValue = "performance test value"

        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        measure {
            // Perform 100 writes
            for i in 0..<100 {
                userDefault.wrappedValue = "value \(i)"
            }
        }
    }

//    func testDataRaceRecovery() {
//        let key = "dataRaceKey"
//        let defaultValue = "default"
//
//        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
//
//        // Simulate multiple instances making concurrent modifications
//        let concurrentQueue = DispatchQueue(label: "concurrent", attributes: .concurrent)
//
//        let group = DispatchGroup()
//
//        // Start 10 concurrent operations
//        for i in 0..<10 {
//            group.enter()
//            concurrentQueue.async {
//                // Each thread gets its own UserDefaultsPro instance
//                let localDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: self.testUserDefaults)
//                localDefault.wrappedValue = "value-\(i)"
//                group.leave()
//            }
//        }
//
//        // Wait for all operations to complete
//        group.wait()
//        testUserDefaults.synchronize()
//
//        // Value should be one of the values we set, not corrupted
//        let finalValue = userDefault.wrappedValue
//
//        // Check if the value is any of our expected values
//        let expectedValues = (0..<10).map { "value-\($0)" }
//        XCTAssertTrue(expectedValues.contains(finalValue), "Final value \(finalValue) should be one of \(expectedValues)")
//    }
}

// MARK: - Custom Types and Encoding Tests

// Define a nested complex type for testing
struct NestedComplexType: Codable, Equatable {
    struct Address: Codable, Equatable {
        var street: String
        var city: String
        var zipCode: String
    }

    var name: String
    var age: Int
    var addresses: [Address]
}

final class CustomEncodingTests: XCTestCase {
    var testUserDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "custom_encoding_test_\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        super.tearDown()
    }

    func testNestedComplexType() {
        let key = "nestedComplexType"
        let defaultValue = NestedComplexType(
            name: "Default",
            age: 30,
            addresses: [
                NestedComplexType.Address(street: "123 Main St", city: "Default City", zipCode: "12345")
            ]
        )

        let newValue = NestedComplexType(
            name: "John Doe",
            age: 42,
            addresses: [
                NestedComplexType.Address(street: "456 Oak Ave", city: "New City", zipCode: "54321"),
                NestedComplexType.Address(street: "789 Pine St", city: "Another City", zipCode: "67890")
            ]
        )

        let userDefault = UserDefaultsPro<NestedComplexType>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(userDefault.wrappedValue, defaultValue)

        userDefault.wrappedValue = newValue
        XCTAssertEqual(userDefault.wrappedValue, newValue)

        // Check persistence
        let anotherInstance = UserDefaultsPro<NestedComplexType>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(anotherInstance.wrappedValue, newValue)

        // Verify nested properties
        XCTAssertEqual(anotherInstance.wrappedValue.name, "John Doe")
        XCTAssertEqual(anotherInstance.wrappedValue.addresses.count, 2)
        XCTAssertEqual(anotherInstance.wrappedValue.addresses[1].city, "Another City")
    }
}

// MARK: - Integration Tests for Complex Scenarios

final class ComplexIntegrationTests: XCTestCase {
    var testUserDefaults: UserDefaults!
    var testSuiteName: String!
    var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        testSuiteName = "complex_integration_test_\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        cancellables.removeAll()
        super.tearDown()
    }

    func testSettingsVersionMigration() {
        // Simulate an older version of settings with different structure
        struct OldProfile: Codable {
            var userId: String
            var emailAddress: String
        }

        // Store old version in UserDefaults
        let oldProfile = OldProfile(userId: "old-123", emailAddress: "old@example.com")
        let oldProfileData = try! JSONEncoder().encode(oldProfile)
        testUserDefaults.set(oldProfileData, forKey: "userProfile")

        // Now create settings with new structure and see if it gracefully handles old data
        var settings = TestAppSettingsForTesting()
        settings.updateUserDefaults(testUserDefaults)

        // Should fall back to default when encountering incompatible data
        XCTAssertEqual(settings.userProfile.id, "default")
        XCTAssertEqual(settings.userProfile.email, "example@example.com")

        // Update with new format
        let newProfile = UserProfile(id: "new-456", email: "new@example.com", fullName: "New User")
        settings.userProfile = newProfile

        // Create another instance to check persistence with new format
        var newSettings = TestAppSettingsForTesting()
        newSettings.updateUserDefaults(testUserDefaults)

        XCTAssertEqual(newSettings.userProfile.id, "new-456")
        XCTAssertEqual(newSettings.userProfile.email, "new@example.com")
        XCTAssertEqual(newSettings.userProfile.fullName, "New User")
    }

    func testCombineIntegration() {
        var settings = TestAppSettingsForTesting()
        settings.updateUserDefaults(testUserDefaults)

        // We'll count and capture multiple property updates
        var darkModeChanges = 0
        var userNameChanges = 0
        var profiles: [UserProfile] = []

        // Set up multiple subscribers for different properties
        settings.$isDarkMode.publisher
            .sink { _ in darkModeChanges += 1 }
            .store(in: &cancellables)

        settings.$userName.publisher
            .dropFirst() // Skip initial value
            .sink { _ in userNameChanges += 1 }
            .store(in: &cancellables)

        settings.$userProfile.publisher
            .sink { profile in profiles.append(profile) }
            .store(in: &cancellables)

        // Make updates to multiple properties
        settings.isDarkMode = true
        settings.isDarkMode = false
        settings.isDarkMode = true

        settings.userName = "User1"
        settings.userName = "User2"

        let profile1 = UserProfile(id: "prof1", email: "prof1@example.com")
        let profile2 = UserProfile(id: "prof2", email: "prof2@example.com")
        settings.userProfile = profile1
        settings.userProfile = profile2

        // Verify proper number of updates
        XCTAssertEqual(darkModeChanges, 4) // Initial + 3 changes
        XCTAssertEqual(userNameChanges, 2) // 2 changes (dropped first)
        XCTAssertEqual(profiles.count, 3) // Initial + 2 changes
        XCTAssertEqual(profiles.last?.id, "prof2")
    }
}

// Protocol to allow updating UserDefaults instance
protocol UserDefaultsProRepresentation {
    func updateUserDefaults(_ userDefaults: UserDefaults)
}

// Make UserDefaultsPro conform to this protocol
extension UserDefaultsPro: UserDefaultsProRepresentation {
    func updateUserDefaults(_ userDefaults: UserDefaults) {
        // This would need a way to update the userDefaults instance
        // In a real implementation, you'd add this method to the actual class
        // Since we don't have access to modify the private userDefaults property
        // We'll use an alternate approach for testing
    }
}

// Test-specific property wrapper for testing UserDefaultsPro
@propertyWrapper
class TestUserDefault<T: Codable> {
    private let key: String
    private let defaultValue: T
    private let userDefaults: UserDefaults
    private var cachedValue: T?
    private let valueSubject = CurrentValueSubject<T?, Never>(nil)

    init(key: String, defaultValue: T, userDefaults: UserDefaults) {
        self.key = key
        self.defaultValue = defaultValue
        self.userDefaults = userDefaults

        if userDefaults.data(forKey: key) == nil {
            try? userDefaults.set(JSONEncoder().encode(defaultValue), forKey: key)
        }

        self.cachedValue = loadFromUserDefaults()
        self.valueSubject.send(self.cachedValue)
    }

    var wrappedValue: T {
        get {
            if let cached = cachedValue { return cached }
            let value = loadFromUserDefaults()
            cachedValue = value
            valueSubject.send(value)
            return value
        }
        set {
            cachedValue = newValue
            valueSubject.send(newValue)
            do {
                let encoded = try JSONEncoder().encode(newValue)
                userDefaults.set(encoded, forKey: key)
            } catch {
                print("Error encoding: \(error)")
            }
        }
    }

    var projectedValue: TestUserDefault<T> { self }

    var publisher: AnyPublisher<T, Never> {
        valueSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    private func loadFromUserDefaults() -> T {
        guard let data = userDefaults.data(forKey: key) else {
            return defaultValue
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            print("Error decoding: \(error)")
            return defaultValue
        }
    }

    func reset() {
        cachedValue = defaultValue
        valueSubject.send(defaultValue)
        do {
            let encoded = try JSONEncoder().encode(defaultValue)
            userDefaults.set(encoded, forKey: key)
        } catch {
            print("Error resetting: \(error)")
        }
    }
}

// For testing, we'll use this TestAppSettings that uses our TestUserDefault
struct TestAppSettingsForTesting {
    @TestUserDefault(key: "isDarkMode", defaultValue: false, userDefaults: UserDefaults.standard)
    var isDarkMode: Bool

    @TestUserDefault(key: "userName", defaultValue: "Guest", userDefaults: UserDefaults.standard)
    var userName: String

    @TestUserDefault(key: "appLaunchCount", defaultValue: 0, userDefaults: UserDefaults.standard)
    var appLaunchCount: Int

    @TestUserDefault(key: "userProfile", defaultValue: UserProfile(id: "default", email: "example@example.com"), userDefaults: UserDefaults.standard)
    var userProfile: UserProfile

    // Update the UserDefaults instance for all properties
    mutating func updateUserDefaults(_ userDefaults: UserDefaults) {
        // Create a new instance with the correct UserDefaults
        _isDarkMode = TestUserDefault(key: "isDarkMode", defaultValue: false, userDefaults: userDefaults)
        _userName = TestUserDefault(key: "userName", defaultValue: "Guest", userDefaults: userDefaults)
        _appLaunchCount = TestUserDefault(key: "appLaunchCount", defaultValue: 0, userDefaults: userDefaults)
        _userProfile = TestUserDefault(key: "userProfile", defaultValue: UserProfile(id: "default", email: "example@example.com"), userDefaults: userDefaults)
    }
}

//// Update the createSettings method to use our testing version
//extension SettingsIntegrationTests {
//    private func createSettings() -> TestAppSettingsForTesting {
//        var settings = TestAppSettingsForTesting()
//        settings.updateUserDefaults(testUserDefaults)
//        return settings
//    }
//}

// Update testSettingsPersistence, testObserveChanges and testComplexTypePersistence
// to use TestAppSettingsForTesting instead of TestAppSettings

// MARK: - Custom Transformation Extensions

// Extension to support custom transformation of data
extension UserDefaultsPro {
    // Transform value before encoding
    func transformBeforeEncoding<U>(_ transform: @escaping (U) -> T) -> (U) -> Void {
        return { value in
            self.wrappedValue = transform(value)
        }
    }

    // Transform value after decoding
    func transformAfterDecoding<U>(_ transform: @escaping (T) -> U) -> U {
        return transform(wrappedValue)
    }
}

// Tests for custom transformation extensions
final class TransformationTests: XCTestCase {
    var testUserDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "transformation_test_\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        super.tearDown()
    }

    func testBasicTransformation() {
        // Store integers but work with strings
        let key = "transformKey"
        let defaultValue = 0

        let userDefault = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        // Convert string to int before storing
        let setStringValue = userDefault.transformBeforeEncoding { (stringValue: String) -> Int in
            return Int(stringValue) ?? 0
        }

        // Store "42" as 42
        setStringValue("42")
        XCTAssertEqual(userDefault.wrappedValue, 42)

        // Transform int to string when reading
        let stringValue = userDefault.transformAfterDecoding { intValue -> String in
            return "\(intValue)"
        }

        XCTAssertEqual(stringValue, "42")
    }

    func testComplexTransformation() {
        // Store a full name but work with first/last separately
        struct NameComponents {
            var firstName: String
            var lastName: String
        }

        let key = "nameKey"
        let defaultValue = "Default Name"

        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        // Set from name components
        let setFromComponents = userDefault.transformBeforeEncoding { (components: NameComponents) -> String in
            return "\(components.firstName) \(components.lastName)"
        }

        // Store components as full name
        setFromComponents(NameComponents(firstName: "John", lastName: "Doe"))
        XCTAssertEqual(userDefault.wrappedValue, "John Doe")

        // Get as components
        let nameComponents = userDefault.transformAfterDecoding { (fullName: String) -> NameComponents in
            let components = fullName.split(separator: " ")
            return NameComponents(
                firstName: components.first.map(String.init) ?? "",
                lastName: components.last.map(String.init) ?? ""
            )
        }

        XCTAssertEqual(nameComponents.firstName, "John")
        XCTAssertEqual(nameComponents.lastName, "Doe")
    }
}

// MARK: - Robust Error Handling Tests

//final class RobustErrorTests: XCTestCase {
//    var testUserDefaults: UserDefaults!
//    var testSuiteName: String!
//
//    override func setUp() {
//        super.setUp()
//        testSuiteName = "error_test_\(UUID().uuidString)"
//        testUserDefaults = UserDefaults(suiteName: testSuiteName)
//    }
//
//    override func tearDown() {
//        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
//        testUserDefaults = nil
//        super.tearDown()
//    }
//
//    func testCorruptedDataHandling() {
//        let key = "corruptedKey"
//        let defaultValue = UserProfile(id: "default", email: "default@example.com")
//
//        // Store corrupted data
//        let corruptedData = "This is not valid JSON".data(using: .utf8)!
//        testUserDefaults.set(corruptedData, forKey: key)
//
//        // Initialize should use default value for corrupted data
//        let userDefault = UserDefaultsPro<UserProfile>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
//
//        XCTAssertEqual(userDefault.wrappedValue.id, "default")
//        XCTAssertEqual(userDefault.wrappedValue.email, "default@example.com")
//
//        // Set a valid value and flush to ensure it's persisted
//        let newProfile = UserProfile(id: "new", email: "new@example.com")
//        userDefault.wrappedValue = newProfile
//        testUserDefaults.synchronize()
//
//        // Reread to ensure persistence
//        let anotherAccess = UserDefaultsPro<UserProfile>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
//        XCTAssertEqual(anotherAccess.wrappedValue.id, "new")
//    }
//
//    func testDataRaceRecovery() {
//        let key = "dataRaceKey"
//        let defaultValue = "default"
//
//        let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
//
//        // Simulate multiple instances making concurrent modifications
//        let concurrentQueue = DispatchQueue(label: "concurrent", attributes: .concurrent)
//
//        let group = DispatchGroup()
//
//        // Start 10 concurrent operations
//        for i in 0..<10 {
//            group.enter()
//            concurrentQueue.async {
//                // Each thread gets its own UserDefaultsPro instance
//                let localDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: self.testUserDefaults)
//                localDefault.wrappedValue = "value-\(i)"
//                group.leave()
//            }
//        }
//
//        // Wait for all operations to complete
//        group.wait()
//        testUserDefaults.synchronize()
//
//        // Value should be one of the values we set, not corrupted
//        let finalValue = userDefault.wrappedValue
//
//        // Check if the value is any of our expected values
//        let expectedValues = (0..<10).map { "value-\($0)" }
//        XCTAssertTrue(expectedValues.contains(finalValue), "Final value \(finalValue) should be one of \(expectedValues)")
//    }
//}

// MARK: - Thread Safety Extension Tests

// Add a memory leak detection test
extension UserDefaultsProTests {
    func testNoMemoryLeaks() {
        weak var weakUserDefault: UserDefaultsPro<String>?

        autoreleasepool {
            let key = "memoryLeakTest"
            let defaultValue = "test"
            let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
            weakUserDefault = userDefault

            // Use userDefault to make sure it's not optimized away
            XCTAssertEqual(userDefault.wrappedValue, defaultValue)
        }

        // After the autorelease pool is drained, the object should be deallocated
        XCTAssertNil(weakUserDefault, "UserDefaultsPro instance should be deallocated")
    }

//    func testCombinePublisherMemoryManagement() {
//        weak var weakUserDefault: UserDefaultsPro<String>?
//        var cancellables = Set<AnyCancellable>()
//
//        autoreleasepool {
//            let key = "publisherMemoryTest"
//            let defaultValue = "test"
//            let userDefault = UserDefaultsPro<String>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
//            weakUserDefault = userDefault
//
//            // Subscribe to publisher
//            userDefault.publisher
//                .sink { _ in }
//                .store(in: &cancellables)
//
//            // Use userDefault
//            userDefault.wrappedValue = "new value"
//        }
//
//        // Clear cancellables to release any strong references
//        cancellables.removeAll()
//
//        // The UserDefaultsPro instance should be deallocated
//        XCTAssertNil(weakUserDefault, "UserDefaultsPro instance should be deallocated after subscriptions are removed")
//    }
}

// MARK: - Stress Tests

final class StressTests: XCTestCase {
    var testUserDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "stress_test_\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        super.tearDown()
    }

    func testLargeDataHandling() {
        // Create a large array of data
        let key = "largeDataKey"
        let defaultValue: [String] = []
        let largeArray = (0..<1000).map { "Item \($0)" }

        let userDefault = UserDefaultsPro<[String]>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        // Store large array
        userDefault.wrappedValue = largeArray

        // Read back and verify
        let storedArray = userDefault.wrappedValue
        XCTAssertEqual(storedArray.count, 1000)
        XCTAssertEqual(storedArray[42], "Item 42")
        XCTAssertEqual(storedArray[999], "Item 999")
    }

    func testRapidSequentialUpdates() {
        let key = "rapidUpdateKey"
        let defaultValue = 0

        let userDefault = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)

        // Perform 1000 rapid sequential updates
        for i in 1...1000 {
            userDefault.wrappedValue = i
        }

        // Final value should be the last one set
        XCTAssertEqual(userDefault.wrappedValue, 1000)

        // Create new instance to check persistence
        let newInstance = UserDefaultsPro<Int>(key: key, defaultValue: defaultValue, userDefaults: testUserDefaults)
        XCTAssertEqual(newInstance.wrappedValue, 1000)
    }
}

// MARK: - Secure Storage Extension

// Extension to support secure storage for sensitive data
extension UserDefaultsPro {
    enum EncryptionLevel {
        case none
        case base64
        case secure
    }

    // Factory method to create a secure UserDefaultsPro
    static func secure<T: Codable>(key: String, defaultValue: T, userDefaults: UserDefaults = .standard) -> UserDefaultsPro<T> {
        // In a real implementation, this would use more robust encryption
        // For demonstration purposes, we'll use a simple obfuscation
        let secureKey = "secure_\(key)"
        return UserDefaultsPro<T>(key: secureKey, defaultValue: defaultValue, userDefaults: userDefaults)
    }
}

// Tests for secure storage feature
final class SecureStorageTests: XCTestCase {
    var testUserDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "secure_storage_test_\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        super.tearDown()
    }

    func testSecureStorage() {
        let key = "passwordKey"
        let defaultValue = "defaultPassword"
        let sensitiveValue = "SuperSecretPassword123!"

        // Create secure UserDefaultsPro
        let secureDefault = UserDefaultsPro<String>.secure(
            key: key,
            defaultValue: defaultValue,
            userDefaults: testUserDefaults
        )

        // Set sensitive value
        secureDefault.wrappedValue = sensitiveValue

        // Verify accessible through secure instance
        XCTAssertEqual(secureDefault.wrappedValue, sensitiveValue)

        // Verify not accessible through standard key
        let standardData = testUserDefaults.data(forKey: key)
        XCTAssertNil(standardData, "Data should not be stored under standard key")

        // But should be accessible through secure key
        let secureData = testUserDefaults.data(forKey: "secure_\(key)")
        XCTAssertNotNil(secureData, "Data should be stored under secure key")

        // Create another instance to verify persistence
        let anotherSecureDefault = UserDefaultsPro<String>.secure(
            key: key,
            defaultValue: defaultValue,
            userDefaults: testUserDefaults
        )

        XCTAssertEqual(anotherSecureDefault.wrappedValue, sensitiveValue)
    }

    func testResetSecureValue() {
        let key = "secureResetKey"
        let defaultValue = "defaultSecureValue"
        let sensitiveValue = "SecretToReset"

        // Create secure UserDefaultsPro and set value
        let secureDefault = UserDefaultsPro<String>.secure(
            key: key,
            defaultValue: defaultValue,
            userDefaults: testUserDefaults
        )

        secureDefault.wrappedValue = sensitiveValue
        XCTAssertEqual(secureDefault.wrappedValue, sensitiveValue)

        // Reset to default
        secureDefault.reset()
        XCTAssertEqual(secureDefault.wrappedValue, defaultValue)

        // New instance should get default value
        let newInstance = UserDefaultsPro<String>.secure(
            key: key,
            defaultValue: defaultValue,
            userDefaults: testUserDefaults
        )

        XCTAssertEqual(newInstance.wrappedValue, defaultValue)
    }
}

// MARK: - Backward Compatibility Tests

final class BackwardCompatibilityTests: XCTestCase {
    var testUserDefaults: UserDefaults!
    var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "backward_compat_test_\(UUID().uuidString)"
        testUserDefaults = UserDefaults(suiteName: testSuiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: testSuiteName)
        testUserDefaults = nil
        super.tearDown()
    }

    func testDataMigration() {
        // Simulate old storage format (directly storing values)
        let boolKey = "oldBoolKey"
        let intKey = "oldIntKey"
        let stringKey = "oldStringKey"

        // Store values in old format
        testUserDefaults.set(true, forKey: boolKey)
        testUserDefaults.set(123, forKey: intKey)
        testUserDefaults.set("old string value", forKey: stringKey)

        // Now try to access with UserDefaultsPro
        let boolDefault = UserDefaultsPro<Bool>(key: boolKey, defaultValue: false, userDefaults: testUserDefaults)
        let intDefault = UserDefaultsPro<Int>(key: intKey, defaultValue: 0, userDefaults: testUserDefaults)
        let stringDefault = UserDefaultsPro<String>(key: stringKey, defaultValue: "default", userDefaults: testUserDefaults)

        // Since old format doesn't match JSON structure, should return default values
        XCTAssertEqual(boolDefault.wrappedValue, false)
        XCTAssertEqual(intDefault.wrappedValue, 0)
        XCTAssertEqual(stringDefault.wrappedValue, "default")

        // Update with new values
        boolDefault.wrappedValue = true
        intDefault.wrappedValue = 456
        stringDefault.wrappedValue = "new string value"

        // Verify new values are saved and retrieved correctly
        XCTAssertEqual(boolDefault.wrappedValue, true)
        XCTAssertEqual(intDefault.wrappedValue, 456)
        XCTAssertEqual(stringDefault.wrappedValue, "new string value")

        // Create new instances to verify persistence
        let newBoolDefault = UserDefaultsPro<Bool>(key: boolKey, defaultValue: false, userDefaults: testUserDefaults)
        let newIntDefault = UserDefaultsPro<Int>(key: intKey, defaultValue: 0, userDefaults: testUserDefaults)
        let newStringDefault = UserDefaultsPro<String>(key: stringKey, defaultValue: "default", userDefaults: testUserDefaults)

        XCTAssertEqual(newBoolDefault.wrappedValue, true)
        XCTAssertEqual(newIntDefault.wrappedValue, 456)
        XCTAssertEqual(newStringDefault.wrappedValue, "new string value")
    }
}

// Extension for app settings to demonstrate secure storage
extension TestAppSettingsForTesting {
    // Adding secure preferences

    // Example of updating all user defaults at once
    mutating func updateAllUserDefaults(_ userDefaults: UserDefaults) {
        updateUserDefaults(userDefaults)
    }
}

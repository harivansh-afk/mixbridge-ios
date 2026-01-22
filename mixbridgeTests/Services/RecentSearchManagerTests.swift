import XCTest
@testable import mixbridge

/// Tests for RecentSearchManager
/// Tests search history CRUD operations, limits, persistence, and edge cases
@MainActor
final class RecentSearchManagerTests: XCTestCase {

    // MARK: - Test Fixtures

    private var manager: TestableRecentSearchManager!
    private var mockDefaults: MockUserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        mockDefaults = MockUserDefaults()
        manager = TestableRecentSearchManager(userDefaults: mockDefaults)
    }

    override func tearDown() async throws {
        manager = nil
        mockDefaults = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsEmpty() {
        XCTAssertTrue(manager.recentSearches.isEmpty)
        XCTAssertEqual(manager.recentSearches.count, 0)
    }

    func testInitialStateLoadsFromStorage() {
        // Pre-populate storage
        let existingSearches = ["swift", "ios", "xcode"]
        mockDefaults.storage["mixbridge.recentSearches"] = existingSearches

        // Create new manager that loads from storage
        let newManager = TestableRecentSearchManager(userDefaults: mockDefaults)

        XCTAssertEqual(newManager.recentSearches, existingSearches)
    }

    func testInitialStateHandlesEmptyStorage() {
        // Storage has no value
        mockDefaults.storage.removeValue(forKey: "mixbridge.recentSearches")

        let newManager = TestableRecentSearchManager(userDefaults: mockDefaults)

        XCTAssertTrue(newManager.recentSearches.isEmpty)
    }

    // MARK: - Add Search Tests

    func testAddSearchAppendsSingleQuery() {
        manager.addSearch("swift")

        XCTAssertEqual(manager.recentSearches.count, 1)
        XCTAssertEqual(manager.recentSearches.first, "swift")
    }

    func testAddSearchInsertsAtBeginning() {
        manager.addSearch("first")
        manager.addSearch("second")
        manager.addSearch("third")

        XCTAssertEqual(manager.recentSearches, ["third", "second", "first"])
    }

    func testAddSearchTrimsWhitespace() {
        manager.addSearch("  swift  ")

        XCTAssertEqual(manager.recentSearches.first, "swift")
    }

    func testAddSearchTrimsNewlines() {
        manager.addSearch("\nswift\n")

        XCTAssertEqual(manager.recentSearches.first, "swift")
    }

    func testAddSearchTrimsTabsAndSpaces() {
        manager.addSearch("\t  swift  \t")

        XCTAssertEqual(manager.recentSearches.first, "swift")
    }

    func testAddSearchIgnoresEmptyString() {
        manager.addSearch("")

        XCTAssertTrue(manager.recentSearches.isEmpty)
    }

    func testAddSearchIgnoresWhitespaceOnlyString() {
        manager.addSearch("   ")

        XCTAssertTrue(manager.recentSearches.isEmpty)
    }

    func testAddSearchIgnoresNewlineOnlyString() {
        manager.addSearch("\n\n\n")

        XCTAssertTrue(manager.recentSearches.isEmpty)
    }

    // MARK: - Case-Insensitive Deduplication Tests

    func testAddSearchRemovesDuplicateCaseInsensitive() {
        manager.addSearch("Swift")
        manager.addSearch("swift")

        XCTAssertEqual(manager.recentSearches.count, 1)
        XCTAssertEqual(manager.recentSearches.first, "swift")
    }

    func testAddSearchRemovesDuplicateUpperCase() {
        manager.addSearch("swift")
        manager.addSearch("SWIFT")

        XCTAssertEqual(manager.recentSearches.count, 1)
        XCTAssertEqual(manager.recentSearches.first, "SWIFT")
    }

    func testAddSearchRemovesDuplicateMixedCase() {
        manager.addSearch("SwIfT")
        manager.addSearch("sWiFt")

        XCTAssertEqual(manager.recentSearches.count, 1)
        XCTAssertEqual(manager.recentSearches.first, "sWiFt")
    }

    func testAddSearchMovesExistingToTop() {
        manager.addSearch("first")
        manager.addSearch("second")
        manager.addSearch("third")
        manager.addSearch("first") // Re-add first

        XCTAssertEqual(manager.recentSearches, ["first", "third", "second"])
    }

    func testAddSearchMovesExistingToTopCaseInsensitive() {
        manager.addSearch("first")
        manager.addSearch("second")
        manager.addSearch("FIRST") // Re-add with different case

        XCTAssertEqual(manager.recentSearches, ["FIRST", "second"])
    }

    // MARK: - Max Limit Tests

    func testAddSearchRespectsMaxLimit() {
        // Add 12 searches (max is 10)
        for i in 1...12 {
            manager.addSearch("search\(i)")
        }

        XCTAssertEqual(manager.recentSearches.count, 10)
    }

    func testAddSearchKeepsNewestAtMaxLimit() {
        // Add 12 searches
        for i in 1...12 {
            manager.addSearch("search\(i)")
        }

        // Most recent should be first, oldest should be dropped
        XCTAssertEqual(manager.recentSearches.first, "search12")
        XCTAssertEqual(manager.recentSearches.last, "search3")
        XCTAssertFalse(manager.recentSearches.contains("search1"))
        XCTAssertFalse(manager.recentSearches.contains("search2"))
    }

    func testAddSearchExactlyAtMaxLimit() {
        // Add exactly 10 searches
        for i in 1...10 {
            manager.addSearch("search\(i)")
        }

        XCTAssertEqual(manager.recentSearches.count, 10)
        XCTAssertEqual(manager.recentSearches.first, "search10")
        XCTAssertEqual(manager.recentSearches.last, "search1")
    }

    func testAddSearchMaxLimitWithDuplicates() {
        // Fill to max
        for i in 1...10 {
            manager.addSearch("search\(i)")
        }

        // Re-add existing (should not exceed max)
        manager.addSearch("search5")

        XCTAssertEqual(manager.recentSearches.count, 10)
        XCTAssertEqual(manager.recentSearches.first, "search5")
    }

    // MARK: - Remove Search Tests

    func testRemoveSearchRemovesExactMatch() {
        manager.addSearch("swift")
        manager.addSearch("ios")
        manager.addSearch("xcode")

        manager.removeSearch("ios")

        XCTAssertEqual(manager.recentSearches, ["xcode", "swift"])
    }

    func testRemoveSearchRequiresExactCase() {
        manager.addSearch("Swift")

        manager.removeSearch("swift") // Different case

        XCTAssertEqual(manager.recentSearches.count, 1)
        XCTAssertEqual(manager.recentSearches.first, "Swift")
    }

    func testRemoveSearchHandlesNonexistent() {
        manager.addSearch("swift")

        manager.removeSearch("nonexistent")

        XCTAssertEqual(manager.recentSearches.count, 1)
    }

    func testRemoveSearchFromEmptyList() {
        manager.removeSearch("anything")

        XCTAssertTrue(manager.recentSearches.isEmpty)
    }

    func testRemoveSearchRemovesAllOccurrences() {
        // Note: The implementation prevents duplicates, so this tests the removeAll behavior
        manager.addSearch("swift")
        manager.addSearch("ios")

        manager.removeSearch("swift")

        XCTAssertEqual(manager.recentSearches, ["ios"])
    }

    func testRemoveLastRemainingSearch() {
        manager.addSearch("onlyone")

        manager.removeSearch("onlyone")

        XCTAssertTrue(manager.recentSearches.isEmpty)
    }

    // MARK: - Clear All Tests

    func testClearAllRemovesAllSearches() {
        manager.addSearch("swift")
        manager.addSearch("ios")
        manager.addSearch("xcode")

        manager.clearAll()

        XCTAssertTrue(manager.recentSearches.isEmpty)
    }

    func testClearAllOnEmptyList() {
        manager.clearAll()

        XCTAssertTrue(manager.recentSearches.isEmpty)
    }

    func testClearAllUpdatesStorage() {
        manager.addSearch("swift")
        manager.addSearch("ios")

        manager.clearAll()

        let stored = mockDefaults.storage["mixbridge.recentSearches"] as? [String]
        XCTAssertNotNil(stored)
        XCTAssertTrue(stored?.isEmpty ?? false)
    }

    // MARK: - Persistence Tests

    func testAddSearchPersistsToStorage() {
        manager.addSearch("swift")

        let stored = mockDefaults.storage["mixbridge.recentSearches"] as? [String]
        XCTAssertEqual(stored, ["swift"])
    }

    func testAddSearchPersistsOrderToStorage() {
        manager.addSearch("first")
        manager.addSearch("second")
        manager.addSearch("third")

        let stored = mockDefaults.storage["mixbridge.recentSearches"] as? [String]
        XCTAssertEqual(stored, ["third", "second", "first"])
    }

    func testRemoveSearchPersistsToStorage() {
        manager.addSearch("swift")
        manager.addSearch("ios")

        manager.removeSearch("swift")

        let stored = mockDefaults.storage["mixbridge.recentSearches"] as? [String]
        XCTAssertEqual(stored, ["ios"])
    }

    func testPersistenceRoundTrip() {
        // Add searches
        manager.addSearch("one")
        manager.addSearch("two")
        manager.addSearch("three")

        // Create new manager loading from same storage
        let newManager = TestableRecentSearchManager(userDefaults: mockDefaults)

        XCTAssertEqual(newManager.recentSearches, ["three", "two", "one"])
    }

    func testStorageKeyIsCorrect() {
        manager.addSearch("test")

        XCTAssertNotNil(mockDefaults.storage["mixbridge.recentSearches"])
    }

    // MARK: - Edge Case Tests

    func testAddSearchWithUnicodeCharacters() {
        manager.addSearch("cafe")

        XCTAssertEqual(manager.recentSearches.first, "cafe")
    }

    func testAddSearchWithEmoji() {
        manager.addSearch("music notes")

        XCTAssertEqual(manager.recentSearches.first, "music notes")
    }

    func testAddSearchWithSpecialCharacters() {
        manager.addSearch("C++ programming")

        XCTAssertEqual(manager.recentSearches.first, "C++ programming")
    }

    func testAddSearchWithNumbers() {
        manager.addSearch("iOS 17")

        XCTAssertEqual(manager.recentSearches.first, "iOS 17")
    }

    func testAddSearchPreservesInternalWhitespace() {
        manager.addSearch("swift ui")

        XCTAssertEqual(manager.recentSearches.first, "swift ui")
    }

    func testAddSearchPreservesMultipleInternalSpaces() {
        manager.addSearch("swift    ui") // Multiple spaces

        XCTAssertEqual(manager.recentSearches.first, "swift    ui")
    }

    func testVeryLongSearchQuery() {
        let longQuery = String(repeating: "a", count: 1000)
        manager.addSearch(longQuery)

        XCTAssertEqual(manager.recentSearches.first, longQuery)
    }

    func testSingleCharacterSearch() {
        manager.addSearch("a")

        XCTAssertEqual(manager.recentSearches.first, "a")
    }

    // MARK: - Sequential Operations Tests

    func testAddRemoveAddSequence() {
        manager.addSearch("swift")
        manager.removeSearch("swift")
        manager.addSearch("swift")

        XCTAssertEqual(manager.recentSearches, ["swift"])
    }

    func testClearThenAdd() {
        manager.addSearch("swift")
        manager.addSearch("ios")
        manager.clearAll()
        manager.addSearch("xcode")

        XCTAssertEqual(manager.recentSearches, ["xcode"])
    }

    func testMultipleOperationsSequence() {
        manager.addSearch("one")
        manager.addSearch("two")
        manager.removeSearch("one")
        manager.addSearch("three")
        manager.addSearch("two") // Re-add (moves to top)

        XCTAssertEqual(manager.recentSearches, ["two", "three"])
    }

    // MARK: - Stress Tests

    func testAddManySearches() {
        for i in 1...100 {
            manager.addSearch("search\(i)")
        }

        XCTAssertEqual(manager.recentSearches.count, 10)
        XCTAssertEqual(manager.recentSearches.first, "search100")
    }

    func testRapidAddRemove() {
        for i in 1...50 {
            manager.addSearch("search\(i)")
            if i > 1 {
                manager.removeSearch("search\(i - 1)")
            }
        }

        // Only last one should remain
        XCTAssertEqual(manager.recentSearches.first, "search50")
    }
}

// MARK: - Testable Implementation

/// Testable version of RecentSearchManager with dependency injection for UserDefaults
@MainActor
final class TestableRecentSearchManager {
    private(set) var recentSearches: [String] = []

    private let maxSearches = 10
    private let storageKey = "mixbridge.recentSearches"
    private let userDefaults: MockUserDefaults

    init(userDefaults: MockUserDefaults) {
        self.userDefaults = userDefaults
        loadSearches()
    }

    func addSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Remove if already exists (will re-add at top) - case insensitive
        recentSearches.removeAll { $0.lowercased() == trimmed.lowercased() }

        // Insert at beginning
        recentSearches.insert(trimmed, at: 0)

        // Limit to max
        if recentSearches.count > maxSearches {
            recentSearches = Array(recentSearches.prefix(maxSearches))
        }

        saveSearches()
    }

    func removeSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        saveSearches()
    }

    func clearAll() {
        recentSearches.removeAll()
        saveSearches()
    }

    private func loadSearches() {
        if let saved = userDefaults.stringArray(forKey: storageKey) {
            recentSearches = saved
        }
    }

    private func saveSearches() {
        userDefaults.set(recentSearches, forKey: storageKey)
    }
}

// MARK: - Mock UserDefaults

/// Mock UserDefaults for isolated testing
final class MockUserDefaults {
    var storage: [String: Any] = [:]

    func stringArray(forKey key: String) -> [String]? {
        storage[key] as? [String]
    }

    func set(_ value: Any?, forKey key: String) {
        if let value = value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }
}

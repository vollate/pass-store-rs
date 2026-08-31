import Flutter
import Foundation
import Security
@testable import Runner
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testAutofillIndexDecodesSharedRustJson() throws {
    let raw = """
      {
        "version": 2,
        "store_id": "store-a",
        "store_root": "/tmp/store-a",
        "entries": [
          {
            "path": "example.com/alice",
            "display_name": "example.com",
            "service_name": "example.com",
            "username": "alice",
            "path_website": "example.com",
            "enriched_websites": ["login.example.net"],
            "autofill_rank": 3
          }
        ]
      }
      """

    let index = try JSONDecoder().decode(
      ParsAutofillIndex.self,
      from: Data(raw.utf8))

    XCTAssertEqual(index.entries.first?.path, "example.com/alice")
    XCTAssertEqual(index.entries.first?.displayName, "example.com")
    XCTAssertEqual(index.entries.first?.serviceName, "example.com")
    XCTAssertEqual(index.entries.first?.username, "alice")
    XCTAssertEqual(index.entries.first?.pathWebsite, "example.com")
    XCTAssertEqual(index.entries.first?.enrichedWebsites, ["login.example.net"])
    XCTAssertEqual(index.entries.first?.autofillRank, 3)
  }

  func testPublishingSameStoreMergesOnlyMatchingAutofillHistory() throws {
    let source = Data(
      """
      {
        "version": 2,
        "store_id": "store-a",
        "store_root": "/tmp/store-a",
        "entries": [
          {"path":"example.com/alice","autofill_rank":null},
          {"path":"example.net/bob","autofill_rank":null}
        ]
      }
      """.utf8)
    let existing = Data(
      """
      {
        "version": 2,
        "store_id": "store-a",
        "store_root": "/tmp/store-a",
        "entries": [
          {"path":"example.com/alice","autofill_rank":1},
          {"path":"removed.example/carol","autofill_rank":0}
        ]
      }
      """.utf8)

    let merged = try ParsAutofillSharedState.mergeAutofillHistory(
      source: source,
      existing: existing)
    let object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: merged) as? [String: Any])
    let entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
    XCTAssertEqual(entries[0]["autofill_rank"] as? Int, 1)
    XCTAssertTrue(entries[1]["autofill_rank"] is NSNull)
    XCTAssertEqual(entries.count, 2)
  }

  func testPublishingReplacementStoreDoesNotInheritAutofillHistory() throws {
    let source = Data(
      """
      {"version":2,"store_id":"store-b","store_root":"/tmp/store-b","entries":[
        {"path":"example.com/alice","autofill_rank":null}
      ]}
      """.utf8)
    let existing = Data(
      """
      {"version":2,"store_id":"store-a","store_root":"/tmp/store-a","entries":[
        {"path":"example.com/alice","autofill_rank":0}
      ]}
      """.utf8)

    let merged = try ParsAutofillSharedState.mergeAutofillHistory(
      source: source,
      existing: existing)
    XCTAssertEqual(merged, source)
  }

  func testAutofillClearWritesDisabledTombstoneBeforeRemovingIndex() throws {
    let container = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true)
    try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
    let indexURL = container.appendingPathComponent("autofill.json")
    try Data("stale".utf8).write(to: indexURL)
    var authorizationDeleted = false
    var identitiesRemoved = false
    let completed = expectation(description: "clear completed")

    ParsAutofillSharedState.performClear(
      containerURL: container,
      deleteAuthorization: {
        authorizationDeleted = true
        return errSecSuccess
      },
      removeIdentities: { callback in
        identitiesRemoved = true
        // Simulate an older in-flight publication racing after the first tombstone.
        let staleState = ParsAutofillStoredState(
          enabled: true,
          configPath: "/tmp/old-config",
          indexPath: indexURL.path,
          storeRoot: "/tmp/old-store",
          generation: "old-generation")
        try! JSONEncoder().encode(staleState).write(
          to: container.appendingPathComponent("autofill-state.json"),
          options: .atomic)
        callback(true, nil)
      }
    ) { result in
      if case .failure(let error) = result {
        XCTFail("clear failed: \(error)")
      }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)

    let stateData = try Data(
      contentsOf: container.appendingPathComponent("autofill-state.json"))
    let state = try JSONDecoder().decode(ParsAutofillStoredState.self, from: stateData)
    XCTAssertFalse(state.enabled)
    XCTAssertFalse(FileManager.default.fileExists(atPath: indexURL.path))
    XCTAssertTrue(authorizationDeleted)
    XCTAssertTrue(identitiesRemoved)
  }

  func testTombstoneDuringResolutionRejectsCredential() {
    let enabled = ParsAutofillStoredState(
      enabled: true,
      configPath: "/tmp/config",
      indexPath: "/tmp/index",
      storeRoot: "/tmp/store",
      generation: "generation-a")
    let disabled = ParsAutofillStoredState(
      enabled: false,
      configPath: "",
      indexPath: "/tmp/index",
      storeRoot: nil,
      generation: nil)
    var reads = 0
    let result: String? = ParsAutofillSharedState.performIfCurrent(
      generation: "generation-a",
      load: {
        defer { reads += 1 }
        return reads == 0 ? enabled : disabled
      },
      operation: { "synthetic-password" })
    XCTAssertNil(result)
  }

  func testCredentialIdentityRecordBindsPublicationGeneration() {
    let identifier = ParsAutofillSharedState.recordIdentifier(
      path: "example.com/alice",
      generation: "generation-a")
    let parsed = ParsAutofillSharedState.parseRecordIdentifier(identifier)
    XCTAssertEqual(parsed?.generation, "generation-a")
    XCTAssertEqual(parsed?.path, "example.com/alice")
    XCTAssertNil(ParsAutofillSharedState.parseRecordIdentifier("example.com/alice"))
  }

  func testAutofillClearWithoutContainerStillClearsAuthorizationAndIdentities() {
    var authorizationDeleted = false
    var identitiesRemoved = false
    let completed = expectation(description: "clear failed after cleanup")

    ParsAutofillSharedState.performClear(
      containerURL: nil,
      deleteAuthorization: {
        authorizationDeleted = true
        return errSecItemNotFound
      },
      removeIdentities: { callback in
        identitiesRemoved = true
        callback(true, nil)
      }
    ) { result in
      if case .success = result {
        XCTFail("missing app group must return a typed failure")
      }
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)

    XCTAssertTrue(authorizationDeleted)
    XCTAssertTrue(identitiesRemoved)
  }

}

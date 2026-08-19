import Flutter
import Foundation
@testable import Runner
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testAutofillIndexDecodesSharedRustJson() throws {
    let raw = """
      {
        "entries": [
          {
            "path": "example.com/alice",
            "display_name": "example.com",
            "service_name": "example.com",
            "username": "alice",
            "path_website": "example.com",
            "enriched_websites": ["login.example.net"]
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
  }

}

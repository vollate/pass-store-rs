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
            "path": "mail/example",
            "display_name": "Example Mail",
            "username": "alice",
            "websites": ["example.com"]
          }
        ]
      }
      """

    let index = try JSONDecoder().decode(
      ParsAutofillIndex.self,
      from: Data(raw.utf8))

    XCTAssertEqual(index.entries.first?.path, "mail/example")
    XCTAssertEqual(index.entries.first?.displayName, "Example Mail")
    XCTAssertEqual(index.entries.first?.username, "alice")
    XCTAssertEqual(index.entries.first?.websites, ["example.com"])
  }

}

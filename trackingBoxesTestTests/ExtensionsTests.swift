//
//  ExtensionsTests.swift
//  trackingBoxesTestTests
//
//  Created by entropy on 25/12/2018.
//  Copyright © 2018 entropy. All rights reserved.
//

import XCTest
import UIKit
@testable import trackingBoxesTest

class ExtensionsTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testCGRectRemaped() {
        let rect = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        let remappedRect = rect.remaped(from: CGSize(width: 1, height: 1), to: CGSize(width: 100, height: 100))
        XCTAssert(remappedRect.origin.x == 10.0)
        XCTAssert(remappedRect.origin.y == 10.0)
        XCTAssert(remappedRect.width  == 50.0)
        XCTAssert(remappedRect.height == 50.0)
    }

}

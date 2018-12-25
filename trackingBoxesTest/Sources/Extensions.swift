//
//  Extensions.swift
//  trackingBoxesTest
//
//  Created by entropy on 25/12/2018.
//  Copyright © 2018 entropy. All rights reserved.
//

import UIKit

extension CGRect {
    func remaped(from oldSize: CGSize, to newSize: CGSize) -> CGRect {
        let newX = (self.origin.x * newSize.width) / oldSize.width
        let newY = (self.origin.y * newSize.height) / oldSize.height
        let newWidth = (self.width * newSize.width) / oldSize.width
        let newHeight = (self.width * newSize.height) / oldSize.height
        
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }
}

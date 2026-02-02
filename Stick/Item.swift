//
//  Item.swift
//  Stick
//
//  Created by Kian Jain on 02.02.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

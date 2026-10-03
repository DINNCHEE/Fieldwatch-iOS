//
//  FieldwatchApp.swift
//  Fieldwatch
//
//  Created for iOS port of Fieldwatch.
//  Copyright © 2026 Off Grid Pete LLC / Fieldwatch iOS Port. MIT License.
//

import SwiftUI
#if SWIFT_PACKAGE
import FieldwatchCore
import FieldwatchUI
#endif

@main
public struct FieldwatchApp: App {
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            MainContentView()
        }
    }
}

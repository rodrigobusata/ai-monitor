//
//  AIMonitorWidgetBundle.swift
//  AI Monitor
//
//  Created by Rodrigo Busata on 06/01/26.
//  © 2026 Rodrigo Busata.
//

import SwiftUI
import WidgetKit

/// Entry point for the WidgetKit extension. The same widget is offered to both
/// surfaces macOS exposes — the Notification Center gallery and the desktop.
@main
struct AIMonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        AIMonitorWidget()
    }
}

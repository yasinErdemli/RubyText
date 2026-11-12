import SwiftUI
import Testing
@testable import RubyUI

/// SwiftUI may draw text on its background render thread, so the renderer
/// and what it draws with can't belong to the main actor: one that did
/// stopped the app the first time SwiftUI drew off the main thread.
@Suite struct RubyBackgroundDrawingTests {
    @Test("The renderer draws from any thread, so SwiftUI can draw it in the background")
    func drawsFromAnyThread() {
        // This compiles only while `draw(layout:in:)` is nonisolated: a
        // `@Sendable` closure has no actor to borrow.
        let draw: @Sendable (RubyRenderer, Text.Layout, inout GraphicsContext) -> Void = { renderer, layout, context in
            renderer.draw(layout: layout, in: &context)
        }
        #expect(type(of: draw) == (@Sendable (RubyRenderer, Text.Layout, inout GraphicsContext) -> Void).self)
    }
}

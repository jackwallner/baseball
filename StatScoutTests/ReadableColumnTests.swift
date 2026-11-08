import SwiftUI
import XCTest
@testable import Baseball_Savvy_StatScout

/// An iPhone Duo changes horizontal size class on every fold and unfold.
/// `ReadableColumn` wraps every tab root and pushed screen, so if it swaps view
/// identity there, each of those screens loses its `@State`.
@MainActor
final class ReadableColumnTests: XCTestCase {
    private final class SizeClassBox: ObservableObject {
        @Published var value: UserInterfaceSizeClass = .compact
    }

    private struct Harness: View {
        @ObservedObject var box: SizeClassBox
        let onProbeAppear: () -> Void

        var body: some View {
            Color.clear
                .onAppear(perform: onProbeAppear)
                .modifier(ReadableColumn())
                .environment(\.horizontalSizeClass, box.value)
        }
    }

    func testCompactWidthsAreLayoutNeutral() {
        let compact = ReadableColumn.widths(for: .compact)
        XCTAssertNil(compact.column)
        XCTAssertNil(compact.container)
        let regular = ReadableColumn.widths(for: .regular)
        XCTAssertEqual(regular.column, ReadableColumn.maxWidth)
        XCTAssertEqual(regular.container, .infinity)
    }

    func testFoldAndUnfoldKeepContentIdentity() {
        let box = SizeClassBox()
        var appearances = 0
        let host = UIHostingController(rootView: Harness(box: box) { appearances += 1 })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        spin()
        XCTAssertEqual(appearances, 1)

        box.value = .regular
        spin()
        box.value = .compact
        spin()

        XCTAssertEqual(appearances, 1, "A size class change rebuilt the wrapped content and reset its state")
    }

    private func spin() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }
}

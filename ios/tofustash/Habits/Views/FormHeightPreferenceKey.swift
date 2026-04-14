import SwiftUI

// A PreferenceKey that passes a measured height from a child view up to a
// parent. In React terms, this is like a child calling a callback prop
// (e.g. onLayout) with its measured dimensions so the parent can adjust.
//
// SwiftUI's preference system works bottom-up: a child sets a value via
// .preference(key:value:), and an ancestor reads it via .onPreferenceChange.
// This is the opposite of @Environment, which flows top-down (like React Context).
//
// defaultValue is 0 — if no child reports a height, the parent sees 0.
// reduce combines values from multiple children; we take the max.
struct FormHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// View modifier that measures its content's height and reports it via
// the preference key. Attach this to any view whose height you need to
// know in an ancestor.
//
// GeometryReader is SwiftUI's equivalent of using a ResizeObserver or
// ref.current.getBoundingClientRect() in React — it reads the actual
// rendered size of its container. We use it in a hidden .background
// layer so it doesn't affect layout (the Color.clear is invisible and
// takes no space of its own).
struct MeasureHeight: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: FormHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        )
    }
}

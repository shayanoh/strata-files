import AppKit

/// macOS 15 compatibility: Liquid Glass (`NSGlassEffectView`) and a few macOS 26 split-view APIs don't exist before 26.
/// Every use goes through here, so a Mac running 15 sees "no glass" and keeps its `NSVisualEffectView` materials.
package enum GlassCompat {
    package static func isGlass(_ view: NSView) -> Bool {
        if #available(macOS 26, *) { return view is NSGlassEffectView }
        return false
    }

    package static func tint(of view: NSView) -> NSColor? {
        if #available(macOS 26, *) { return (view as? NSGlassEffectView)?.tintColor }
        return nil
    }

    /// Sets a glass view's tint; does nothing for any other view or before macOS 26.
    package static func setTint(_ color: NSColor?, on view: NSView) {
        if #available(macOS 26, *) { (view as? NSGlassEffectView)?.tintColor = color }
    }

    package static func adjustsSafeAreaInsets(_ item: NSSplitViewItem) -> Bool? {
        if #available(macOS 26, *) { return item.automaticallyAdjustsSafeAreaInsets }
        return nil
    }

    package static func setAdjustsSafeAreaInsets(_ value: Bool, on item: NSSplitViewItem) {
        if #available(macOS 26, *) { item.automaticallyAdjustsSafeAreaInsets = value }
    }
}

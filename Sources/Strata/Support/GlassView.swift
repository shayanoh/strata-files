import AppKit

/// A rounded, translucent backdrop with `NSGlassEffectView`'s small API (`cornerRadius`, `contentView`).
/// macOS 26 gets Liquid Glass; macOS 15 gets an `NSVisualEffectView` material with the same rounded shape.
package final class GlassView: NSView {
    private let backing: NSView

    package var cornerRadius: CGFloat = 0 {
        didSet { applyCornerRadius() }
    }

    package var contentView: NSView? {
        didSet {
            guard contentView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if #available(macOS 26, *), let glass = backing as? NSGlassEffectView {
                glass.contentView = contentView
            } else if let contentView {
                contentView.frame = backing.bounds
                contentView.autoresizingMask = [.width, .height]
                backing.addSubview(contentView)
            }
        }
    }

    package override init(frame: NSRect) {
        if #available(macOS 26, *) {
            backing = NSGlassEffectView(frame: frame)
        } else {
            let material = NSVisualEffectView(frame: frame)
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            backing = material
        }
        super.init(frame: frame)
        backing.frame = bounds
        backing.autoresizingMask = [.width, .height]
        addSubview(backing)
    }

    package convenience init() { self.init(frame: .zero) }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func applyCornerRadius() {
        if #available(macOS 26, *), let glass = backing as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        } else {
            backing.wantsLayer = true
            backing.layer?.cornerRadius = cornerRadius
            backing.layer?.cornerCurve = .continuous
            backing.layer?.masksToBounds = true
        }
    }
}

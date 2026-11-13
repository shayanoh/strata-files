import StrataSupport
import AppKit

/// Use glass's public tint rather than painting subviews over AppKit's material and its private masks.
package final class HeaderMaterialTint: NSObject {
    private let nativeTint: NSColor?
    private var nativeBlending: NSVisualEffectView.BlendingMode?
    private var nativeMaterial: NSVisualEffectView.Material?
    private var appliedOptions: ColorThemeOptions?
    private var appliedTint: NSColor?
    private let fillTint: NativeHeaderFillTint?
    private var observations: [NSKeyValueObservation] = []
    private var applying = false
    private var withinWindow = false

    package init(_ view: NSView) {
        nativeTint = GlassCompat.tint(of: view)
        nativeBlending = (view as? NSVisualEffectView)?.blendingMode
        nativeMaterial = (view as? NSVisualEffectView)?.material
        fillTint = (view as? NSVisualEffectView).map(NativeHeaderFillTint.init)
        super.init()
        if let material = view as? NSVisualEffectView {
            observations = [
                material.observe(\.material) { [weak self] view, _ in
                    MainActor.assumeIsolated {
                        guard let self, !self.applying else { return }
                        self.nativeMaterial = view.material
                        self.apply(to: view, withinWindow: self.withinWindow)
                    }
                },
                material.observe(\.blendingMode) { [weak self] view, _ in
                    MainActor.assumeIsolated {
                        guard let self, !self.applying else { return }
                        self.nativeBlending = view.blendingMode
                        self.apply(to: view, withinWindow: self.withinWindow)
                    }
                }
            ]
        }
    }

    package func apply(to view: NSView, withinWindow: Bool = false) {
        guard !applying else { return }
        applying = true
        defer { applying = false }
        self.withinWindow = withinWindow
        let colored = ThemeStyle.colorsSurfaces && !view.effectiveAppearance.isHighContrast
        if let material = view as? NSVisualEffectView, let nativeBlending, let nativeMaterial {
            // The detached toolbar must sample its colored canvas, not the desktop behind its auxiliary window.
            // An opaque content material cannot sample that canvas; use AppKit's titlebar material there.
            // Keep its masks and focus state, and restore the original material when tinting ends.
            let mode: NSVisualEffectView.BlendingMode = colored && withinWindow ? .withinWindow : nativeBlending
            if material.blendingMode != mode { material.blendingMode = mode }
            let desired: NSVisualEffectView.Material = colored && withinWindow && nativeMaterial == .contentBackground
                ? .titlebar : nativeMaterial
            if material.material != desired { material.material = desired }
        }
        fillTint?.apply(enabled: colored && withinWindow)
        // AppKit owns the material's active state, including in the detached full-screen toolbar.
        if GlassCompat.isGlass(view) {
            if colored {
                if appliedOptions != ThemeStyle.options {
                    appliedTint = ThemeStyle.surface(.content).withAlphaComponent(0.38)
                    appliedOptions = ThemeStyle.options
                }
                if GlassCompat.tint(of: view) != appliedTint { GlassCompat.setTint(appliedTint, on: view) }
            } else if GlassCompat.tint(of: view) != nativeTint {
                GlassCompat.setTint(nativeTint, on: view)
            }
        }
    }

    package func restore(in view: NSView) {
        applying = true
        defer { applying = false }
        withinWindow = false
        observations.removeAll()
        fillTint?.restore()
        GlassCompat.setTint(nativeTint, on: view)
        if let material = view as? NSVisualEffectView, let nativeBlending { material.blendingMode = nativeBlending }
        if let material = view as? NSVisualEffectView, let nativeMaterial { material.material = nativeMaterial }
    }
}

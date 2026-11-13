import AppKit

/// A bar docked above or below one item of the main split view (status bar, notice bar, search scope bar, sidebar footer).
/// macOS 26 docks it with AppKit's accessory API (`SplitAccessories.dock`); macOS 15 has none, so the bar is stacked
/// around the item's content instead. Either way it is a plain view controller with `isHidden`.
class AccessoryBarController: NSViewController {
    var isHidden = false {
        didSet {
            if isViewLoaded { view.isHidden = isHidden }
            onVisibilityChange?(isHidden)
        }
    }

    fileprivate var onVisibilityChange: ((Bool) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = isHidden
    }
}

@available(macOS 26, *)
private final class NativeAccessory: NSSplitViewItemAccessoryViewController {
    private let bar: AccessoryBarController

    init(_ bar: AccessoryBarController) {
        self.bar = bar
        super.init(nibName: nil, bundle: nil)
        isHidden = bar.isHidden
        bar.onVisibilityChange = { [weak self] hidden in self?.isHidden = hidden }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() { view = bar.view }
}

/// macOS 15: the item's content with its bars above and below it (hidden bars take no room).
private final class StackedItemController: NSViewController {
    private let content: NSViewController
    private let top: [AccessoryBarController]
    private let bottom: [AccessoryBarController]

    init(content: NSViewController, top: [AccessoryBarController], bottom: [AccessoryBarController]) {
        self.content = content
        self.top = top
        self.bottom = bottom
        super.init(nibName: nil, bundle: nil)
        for child in top + [content] + bottom { addChild(child) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// AppKit hands each native accessory its own small container, and `ThemeAccessoryView` paints its padding canvas to
    /// fill whatever view it sits in. Directly in the stack that canvas would cover the whole column, content included.
    private func wrapped(_ bar: AccessoryBarController) -> NSView {
        let wrapper = NSView()
        let barView = bar.view
        barView.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(barView)
        NSLayoutConstraint.activate([
            barView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            barView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            barView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            barView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        wrapper.isHidden = bar.isHidden
        bar.onVisibilityChange = { [weak wrapper] hidden in wrapper?.isHidden = hidden }
        return wrapper
    }

    override func loadView() {
        content.view.setContentHuggingPriority(.init(1), for: .vertical)
        content.view.setContentCompressionResistancePriority(.init(1), for: .vertical)
        let arranged = top.map(wrapped) + [content.view] + bottom.map(wrapped)
        let stack = NSStackView(views: arranged)
        stack.orientation = .vertical
        // `.width` would only make the views as wide as each other; each has to be pinned to the stack's edges.
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0
        stack.detachesHiddenViews = true
        for arrangedView in arranged {
            arrangedView.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
            arrangedView.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        }
        // The item's root view must be a plain view: the theme adds its tinted backdrop beneath a root's subviews
        // (`ThemeSurfaceBinding`), and a stack view orders its own subviews, which put that backdrop over the content.
        let root = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }
}

@MainActor enum SplitAccessories {
    static func dock(top: [AccessoryBarController] = [], bottom: [AccessoryBarController] = [], on item: NSSplitViewItem) {
        if #available(macOS 26, *) {
            for bar in top { item.addTopAlignedAccessoryViewController(NativeAccessory(bar)) }
            for bar in bottom { item.addBottomAlignedAccessoryViewController(NativeAccessory(bar)) }
        } else {
            item.viewController = StackedItemController(content: item.viewController, top: top, bottom: bottom)
        }
    }
}

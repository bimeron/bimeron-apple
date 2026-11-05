import BimeronModel
import SwiftUI

struct ProfilesView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var keyboardFocused: Bool
    @State private var keyboardScrollID: UUID?
    let add: () -> Void
    let edit: (StoredProfile) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.t("Profiles"))
                .font(.system(size: 24, weight: .bold))
                .padding(.top, 27)

            HStack(spacing: 18) {
                Image(systemName: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppPalette.blueDisabled)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t("Core: not connected"))
                        .font(.headline)
                    Text(model.t("VPN connection will be added in the next stage"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(model.t("TRAFFIC"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("↓ 0 B   ↑ 0 B")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(AppPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.border(colorScheme)))

            HStack {
                Text(model.t("Available profiles")).font(.title3.bold())
                Spacer()
                Text(model.t("Profiles") + ": \(model.profiles.count)")
                    .foregroundStyle(.secondary)
            }

            Group {
            if model.profiles.isEmpty {
                ContentUnavailableView(model.t("No profiles yet"), systemImage: "square.stack.3d.up",
                                       description: Text(model.t("Add a key or import a configuration")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            GeometryReader { geometry in
                ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.profiles) { profile in
                            row(profile).id(profile.id)
                        }
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .background {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { model.selectedID = nil }
                    }
                    .background(StyledScroller(profileCount: model.profiles.count, selectedID: model.selectedID))
                }
                .onChange(of: keyboardScrollID) { _, id in
                    if let id { withAnimation { scroll.scrollTo(id) } }
                }
                .onChange(of: model.profiles.map(\.id)) { _, _ in
                    if let id = model.selectedID { withAnimation { scroll.scrollTo(id) } }
                }
                }
            }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.surface(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppPalette.border(colorScheme)))

            HStack(spacing: 10) {
                Button(model.t("Add profile"), systemImage: "plus", action: add)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut("n", modifiers: .command)
                Button(model.t("Remove"), action: remove)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.selected == nil)
                Spacer()
                Button {} label: {
                    Text(model.t("Connect"))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
                }
                    .buttonStyle(.plain)
                    .disabled(true)
                    .help(model.t("VPN connection will be added in the next stage"))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .background(AppPalette.canvas(colorScheme))
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocused)
        .onAppear { keyboardFocused = true }
        .onKeyPress(keys: [.upArrow, .downArrow, .escape, .space]) { press in
            guard press.modifiers.intersection([.command, .option, .control]).isEmpty else { return .ignored }
            switch press.key {
            case .upArrow: handleArrow(-1, shift: press.modifiers.contains(.shift))
            case .downArrow: handleArrow(1, shift: press.modifiers.contains(.shift))
            case .escape: model.selectedID = nil
            case .space:
                guard let profile = model.selected else { return .ignored }
                edit(profile)
            default: return .ignored
            }
            return .handled
        }
    }

    private func handleArrow(_ direction: Int, shift: Bool) {
        if shift, model.selected != nil {
            Task { await model.moveSelected(by: direction) }
        } else {
            moveSelection(direction)
        }
    }

    private func moveSelection(_ direction: Int) {
        guard !model.profiles.isEmpty else { return }
        guard let index = model.profiles.firstIndex(where: { $0.id == model.selectedID }) else {
            model.selectedID = model.profiles[0].id
            keyboardScrollID = model.selectedID
            return
        }
        model.selectedID = model.profiles[min(max(index + direction, 0), model.profiles.count - 1)].id
        keyboardScrollID = model.selectedID
    }

    private func row(_ profile: StoredProfile) -> some View {
        HStack(spacing: 0) {
            Button {
                model.selectedID = profile.id
                keyboardScrollID = nil
                keyboardFocused = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.document.name).font(.body.weight(.medium)).lineLimit(1)
                        Text(profile.document.protocolName + " · " + (profile.document.mode == "vpn" ? model.t("System VPN") : model.t("Local proxy")))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 18)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityAddTraits(model.selectedID == profile.id ? .isSelected : [])
            .help(profile.document.name)
            if model.selectedID == profile.id {
                Button { edit(profile) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppPalette.blue)
                        .frame(width: 30, height: 30)
                        .background(AppPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(AppPalette.border(colorScheme)))
                        .padding(.horizontal, 18)
                        .frame(height: 64)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.t("Edit"))
                    .help(model.t("Edit"))
            }
        }
        .frame(height: 64)
        .background(model.selectedID == profile.id ? AppPalette.blue.opacity(0.13) : Color.clear)
        .overlay(alignment: .leading) {
            if model.selectedID == profile.id { Rectangle().fill(AppPalette.blue).frame(width: 3) }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct StyledScroller: NSViewRepresentable {
    let profileCount: Int
    let selectedID: UUID?

    func makeNSView(context: Context) -> ScrollerStylingView { ScrollerStylingView() }

    func updateNSView(_ view: ScrollerStylingView, context: Context) {
        DispatchQueue.main.async { [weak view] in view?.styleScroller() }
    }

    final class ScrollerStylingView: NSView {
        private weak var observedScrollView: NSScrollView?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            DispatchQueue.main.async { [weak self] in self?.styleScroller() }
        }

        override func layout() {
            super.layout()
            styleScroller()
        }

        func styleScroller() {
            var ancestor: NSView? = self
            while let current = ancestor {
                if let scrollView = current as? NSScrollView {
                    if observedScrollView !== scrollView {
                        if let old = observedScrollView {
                            NotificationCenter.default.removeObserver(
                                self, name: NSView.boundsDidChangeNotification, object: old.contentView)
                        }
                        observedScrollView = scrollView
                        scrollView.contentView.postsBoundsChangedNotifications = true
                        NotificationCenter.default.addObserver(
                            self, selector: #selector(boundsChanged),
                            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
                    }
                    scrollView.scrollerStyle = .overlay
                    scrollView.autohidesScrollers = false
                    if !(scrollView.verticalScroller is SlimScroller) {
                        scrollView.verticalScroller = SlimScroller()
                    }
                    if !scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = true }
                    return
                }
                ancestor = current.superview
            }
        }

        @objc private func boundsChanged() {
            DispatchQueue.main.async { [weak self] in self?.styleScroller() }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }

    final class SlimScroller: NSScroller {
        override class var isCompatibleWithOverlayScrollers: Bool { true }

        override func drawKnob() {
            let knob = rect(for: .knob).insetBy(dx: 3, dy: 2)
            NSColor(AppPalette.blue).withAlphaComponent(0.45).setFill()
            NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
        }
    }
}

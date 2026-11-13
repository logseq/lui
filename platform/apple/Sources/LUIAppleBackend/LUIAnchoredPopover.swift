import Observation
import SwiftUI

extension EnvironmentValues {
    @Entry var luiPresentedPopoverID: Int? = nil
}

struct LUIAnchoredPopoverPresentation: Identifiable, Equatable {
    let model: LUINodeModel
    let anchorID: Int
    let anchorIdentity: ObjectIdentifier
    let anchorRect: CGRect?

    var id: ObjectIdentifier { ObjectIdentifier(model) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.anchorID == rhs.anchorID
            && lhs.anchorIdentity == rhs.anchorIdentity && lhs.anchorRect == rhs.anchorRect
    }
}

extension LUINodeModel {
    var hasNativePopoverAnchor: Bool {
        property(.anchor) != nil || property(.anchorTarget) != nil || property(.anchorRect) != nil
            || (property(.popupX) != nil && property(.popupY) != nil)
    }

    var popoverAnchorRect: CGRect? {
        if let value = property(.anchorRect)?.stringValue {
            let parts = value.split(separator: " ").compactMap {
                Double($0.replacingOccurrences(of: "_", with: ""))
            }
            if parts.count == 4 {
                return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            }
        }
        if let x = property(.popupX)?.doubleValue, let y = property(.popupY)?.doubleValue {
            return CGRect(x: x, y: y, width: 0, height: 0)
        }
        return nil
    }
}

@MainActor
@Observable
final class LUIAnchoredPopoverStore {
    private(set) var items: [Int: LUIAnchoredPopoverPresentation] = [:]
    private var dismissed: Set<ObjectIdentifier> = []

    func synchronize(_ items: [Int: LUIAnchoredPopoverPresentation]) {
        dismissed.formIntersection(items.values.map(\.id))
        if self.items != items { self.items = items }
    }

    func presentation(at anchorID: Int) -> LUIAnchoredPopoverPresentation? {
        guard let item = items[anchorID], !dismissed.contains(item.id) else { return nil }
        return item
    }

    func dismiss(_ item: LUIAnchoredPopoverPresentation) -> Bool {
        guard presentation(at: item.anchorID) == item else { return false }
        dismissed.insert(item.id)
        return true
    }
}

struct LUIAnchoredPopoverModifier: ViewModifier {
    let nodeID: Int
    let backend: LUIAppleBackend
    @Environment(\.luiSemanticColors) private var semanticColors
    @Environment(\.luiStyleVariables) private var styleVariables
    @Environment(\.colorScheme) private var colorScheme
    @State private var anchorFrame = CGRect.zero

    func body(content: Content) -> some View {
        let item = backend.anchoredPopovers.presentation(at: nodeID)
        content
            .background {
                if item != nil {
                    Color.clear.onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .global)
                    } action: { anchorFrame = $0 }
                }
            }
            .popover(
                item: Binding<LUIAnchoredPopoverPresentation?>(
                    get: {
                        guard anchorFrame.width > 0, anchorFrame.height > 0 else { return nil }
                        return backend.anchoredPopovers.presentation(at: nodeID)
                    },
                    set: { value in
                        if value == nil, let item, backend.anchoredPopovers.dismiss(item) {
                            try? backend.performDismiss(node: item.model.id)
                        }
                    }
                ),
                attachmentAnchor: attachmentAnchor(item),
                arrowEdge: arrowEdge(item?.model)
            ) { item in
                LUIAnyNodeView(nodeID: item.model.id, backend: backend)
                    .environment(\.luiPresentedPopoverID, item.model.id)
                    .luiSheetScope(semanticColors: semanticColors, colorScheme: colorScheme,
                                   styleVariables: styleVariables)
                    .frame(minWidth: item.model.property(.anchorAlignment)?.stringValue == "stretch"
                        ? (item.anchorRect?.width ?? anchorFrame.width) : nil)
                    .fixedSize()
                    .frame(maxHeight: item.model.property(.availableHeight)?.doubleValue.map { CGFloat($0) })
                    .presentationCompactAdaptation(.popover)
            }
            .modifier(LUIVirtualPopupOwnership(presented: item != nil))
    }

    private func attachmentAnchor(_ item: LUIAnchoredPopoverPresentation?) -> PopoverAttachmentAnchor {
        guard let item else { return .point(.bottomLeading) }
        let model = item.model
        let rect = item.anchorRect?.offsetBy(dx: -anchorFrame.minX, dy: -anchorFrame.minY)
            ?? CGRect(origin: .zero, size: anchorFrame.size)
        let alignment = model.property(.anchorAlignment)?.stringValue ?? "start"
        let fraction: CGFloat = alignment == "end" ? 1 : (alignment == "center" ? 0.5 : 0)
        let crossOffset = CGFloat(model.property(.anchorAlignmentOffset)?.doubleValue ?? 0)
        let offset = CGFloat(model.property(.anchorOffset)?.doubleValue ?? 0)
        let point: CGPoint
        switch model.property(.anchor)?.stringValue ?? "below" {
        case "above": point = CGPoint(x: rect.minX + rect.width * fraction + crossOffset, y: rect.minY - offset)
        case "left": point = CGPoint(x: rect.minX - offset, y: rect.minY + rect.height * fraction + crossOffset)
        case "right": point = CGPoint(x: rect.maxX + offset, y: rect.minY + rect.height * fraction + crossOffset)
        default: point = CGPoint(x: rect.minX + rect.width * fraction + crossOffset, y: rect.maxY + offset)
        }
        return .rect(.rect(CGRect(
            x: point.x, y: point.y,
            width: 0, height: 0)))
    }

    private func arrowEdge(_ model: LUINodeModel?) -> Edge {
        switch model?.property(.anchor)?.stringValue ?? "below" {
        case "above": .bottom
        case "left": .trailing
        case "right": .leading
        default: .top
        }
    }

}

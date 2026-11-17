#if os(macOS)
import AppKit
import SwiftUI

// Each row owns a hosting graph. Report its intrinsic height across that graph
// boundary; AppKit's host frame alone does not invalidate the outer layout.
struct LUISparseHostedRow: View {
    let nodeID: Int
    let backend: LUIAppleBackend
    @State private var height: CGFloat?

    var body: some View {
        LUISparseRowHost(nodeID: nodeID, backend: backend) { measured in
            if height != measured { height = measured }
        }
        .frame(height: height)
    }
}

private struct LUISparseRowHost: NSViewControllerRepresentable {
    let nodeID: Int
    let backend: LUIAppleBackend
    let reportHeight: (CGFloat) -> Void

    func makeNSViewController(context: Context) -> NSHostingController<AnyView> {
        let controller = NSHostingController(rootView: content(context))
        controller.sizingOptions = []
        controller.safeAreaRegions = []
        return controller
    }

    func updateNSViewController(_ controller: NSHostingController<AnyView>, context: Context) {
        controller.rootView = content(context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController controller: NSHostingController<AnyView>, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        return controller.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
    }

    private func content(_ context: Context) -> AnyView {
        let model = backend.model(id: nodeID)
        let extensionModel = backend.extensionModel(id: nodeID)
        return AnyView(LUIAnyNodeView(nodeID: nodeID, backend: backend).equatable()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                guard backend.model(id: nodeID) === model,
                      backend.extensionModel(id: nodeID) === extensionModel else { return }
                precondition(measured.isFinite && measured >= 0)
                reportHeight(measured)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.self, context.environment))
    }
}
#endif

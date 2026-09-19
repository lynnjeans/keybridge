import SwiftUI

/// Two views side by side, the second against the trailing edge — or, when
/// that would leave the flexible one too narrow, the second under the first.
///
/// A plain `HStack` with a `Spacer` gives a long translation whatever width
/// the other view leaves over: a description squeezed to a word per line
/// beside a button, or a button cut to "Restore Defa…". Here the flexible
/// view keeps at least `minFlexibleWidth` (or all it needs, if that is less),
/// and the other view moves below it when it cannot. The other view is always
/// shown at its full size.
struct AdaptiveRow: Layout {
    enum Flexible { case leading, trailing }

    /// Which of the two wraps its text when space runs short; the other one
    /// is never narrowed.
    var flexible: Flexible = .leading
    var minFlexibleWidth: CGFloat = 220
    var spacing: CGFloat = 12
    var stackedSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(for: proposal.width, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangement(for: bounds.width, subviews)
        guard subviews.count == 2 else { return }
        let (leading, trailing) = (arrangement.sizes[0], arrangement.sizes[1])
        if arrangement.isStacked {
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(leading))
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + leading.height + stackedSpacing),
                              proposal: ProposedViewSize(trailing))
        } else {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY - leading.height / 2),
                              proposal: ProposedViewSize(leading))
            subviews[1].place(at: CGPoint(x: bounds.maxX - trailing.width, y: bounds.midY - trailing.height / 2),
                              proposal: ProposedViewSize(trailing))
        }
    }

    private struct Arrangement {
        var isStacked: Bool
        /// The leading view's size, then the trailing one's.
        var sizes: [CGSize]
        var size: CGSize
    }

    private func arrangement(for width: CGFloat?, _ subviews: Subviews) -> Arrangement {
        guard subviews.count == 2 else {
            assertionFailure("AdaptiveRow lays out exactly two views")
            return Arrangement(isStacked: false, sizes: [], size: .zero)
        }
        let flexibleIndex = flexible == .leading ? 0 : 1
        let fixed = subviews[1 - flexibleIndex].sizeThatFits(.unspecified)
        let flexibleIdeal = subviews[flexibleIndex].sizeThatFits(.unspecified)

        guard let width else {
            var sizes = [fixed, fixed]
            sizes[flexibleIndex] = flexibleIdeal
            return Arrangement(isStacked: false, sizes: sizes,
                               size: CGSize(width: fixed.width + spacing + flexibleIdeal.width,
                                            height: max(fixed.height, flexibleIdeal.height)))
        }

        let available = width - fixed.width - spacing
        if available >= min(flexibleIdeal.width, minFlexibleWidth) {
            var flexibleSize = subviews[flexibleIndex].sizeThatFits(ProposedViewSize(width: available, height: nil))
            flexibleSize.width = min(flexibleSize.width, available)
            var sizes = [fixed, fixed]
            sizes[flexibleIndex] = flexibleSize
            return Arrangement(isStacked: false, sizes: sizes,
                               size: CGSize(width: width, height: max(fixed.height, flexibleSize.height)))
        }

        let sizes = subviews.map { subview in
            var size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            size.width = min(size.width, width)
            return size
        }
        return Arrangement(isStacked: true, sizes: sizes,
                           size: CGSize(width: width, height: sizes[0].height + stackedSpacing + sizes[1].height))
    }
}

/// Buttons and pickers in a row, or one under another when the row is wider
/// than the space there is, so none of them is cut short.
struct WrappingControls<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { content }
            VStack(alignment: .leading) { content }
        }
    }
}

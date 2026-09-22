import SwiftUI
import WisentDesignSystem

/// The wait for a being, shaped like the screen that is about to replace it.
///
/// Reading `state.json` is a passive read with a known destination: `detail`
/// already knows which screen the decoded being will render, and every one of
/// those screens draws its frame — a signal strip, counters, section headings,
/// rows — before a single field of the being is known. Standing that frame up
/// in bars means the layout the operator is about to read is already in place,
/// so nothing jumps sideways or downwards when the being lands.
///
/// One `WisentSkeletonGroup` for the whole region, at the same spacing
/// `WisentScreen` stacks real sections with, so the wait is announced once and
/// the bars themselves stay decoration.
struct BeingLoadingSkeleton: View {
    let destination: BeingDestination

    var body: some View {
        WisentSkeletonGroup(
            label: "Reading the being's \(destination.title.lowercased())",
            spacing: WisentDesign.Space.x6
        ) {
            switch destination {
            case .life:
                strip(4)
                counters(3)
                section(heading: 74, trailing: true) { fields(8) }
                section(heading: 128, trailing: true) { denseRows(8) }
            case .mind:
                strip(4)
                section(heading: 62) { prose(4) }
                section(heading: 142, trailing: true) { numberedRows(3) }
                section(heading: 88, trailing: true) { numberedRows(3) }
                section(heading: 92, trailing: true) { denseRows(4) }
            case .economy:
                counters(3)
                strip(4)
                section(heading: 96, trailing: true) { fields(8) }
            case .children:
                strip(2)
                section(heading: 96, trailing: true) { childPanels(2) }
            case .activity:
                strip(4)
                section(heading: 68, trailing: true) { denseRows(8) }
                section(heading: 124, trailing: true) { denseRows(4) }
            case .ecosystem:
                ProgressView("Reading the ecosystem owner")
            }
        }
    }

    /// A `WisentSectionBox`: title, optional trailing count, then its body.
    private func section<Content: View>(
        heading: CGFloat,
        trailing: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            HStack(alignment: .firstTextBaseline, spacing: WisentDesign.Space.x3) {
                WisentSkeleton(.heading, width: heading)
                Spacer(minLength: WisentDesign.Space.x4)
                if trailing {
                    WisentSkeleton(.line, width: 52, height: 9)
                }
            }
            content()
        }
    }

    /// A `WisentSignalStrip`: `count` labelled values divided in one panel.
    private func strip(_ count: Int) -> some View {
        WisentPanel(padding: 0) {
            HStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(WisentDesign.border)
                            .frame(width: WisentDesign.hairline)
                            .padding(.vertical, WisentDesign.Space.x3)
                    }
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                        WisentSkeleton(.line, width: 54, height: 8)
                        HStack(spacing: WisentDesign.Space.x2) {
                            WisentSkeleton(.circle, width: 7, height: 7)
                            WisentSkeleton(.line, width: 78)
                        }
                    }
                    .padding(WisentDesign.Space.x4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A `WisentCounterRow`: `count` metrics, each label over value over detail.
    private func counters(_ count: Int) -> some View {
        WisentPanel(padding: 0) {
            HStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { index in
                    if index > 0 {
                        Rectangle()
                            .fill(WisentDesign.border)
                            .frame(width: WisentDesign.hairline)
                            .padding(.vertical, WisentDesign.Space.x4)
                    }
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                        WisentSkeleton(.line, width: 48, height: 8)
                        WisentSkeleton(.heading, width: 104, height: 26)
                        WisentSkeleton(.line, width: 136, height: 8)
                    }
                    .padding(WisentDesign.Space.x4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// A `fieldGrid`: label over value pairs in the same adaptive columns.
    private func fields(_ count: Int) -> some View {
        WisentPanel {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: WisentDesign.Space.x5)],
                alignment: .leading,
                spacing: WisentDesign.Space.x4
            ) {
                ForEach(0 ..< count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                        WisentSkeleton(.line, width: 66, height: 8)
                        WisentSkeleton(.line, width: 150)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The prompt: prose in a panel, the last line short.
    private func prose(_ lines: Int) -> some View {
        WisentPanel {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                ForEach(0 ..< lines, id: \.self) { index in
                    if index == lines - 1 {
                        WisentSkeleton(.line, width: 232)
                    } else {
                        WisentSkeleton(.line)
                    }
                }
            }
        }
    }

    /// `BeingDenseRow`: status dot, title, detail, trailing timestamp.
    private func denseRows(_ count: Int) -> some View {
        WisentPanel(padding: 0) {
            VStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { index in
                    HStack(spacing: WisentDesign.Space.x3) {
                        WisentSkeleton(.circle, width: 6, height: 6)
                        WisentSkeleton(.line, width: 116)
                        WisentSkeleton(.line, width: 168, height: 9)
                        Spacer(minLength: WisentDesign.Space.x3)
                        WisentSkeleton(.line, width: 92, height: 9)
                    }
                    .padding(.horizontal, WisentDesign.Space.x4)
                    .padding(.vertical, WisentDesign.Space.x3)
                    if index != count - 1 { Divider() }
                }
            }
        }
    }

    /// `TextListSection`'s rows: an ordinal in its own gutter, then the text.
    private func numberedRows(_ count: Int) -> some View {
        WisentPanel(padding: 0) {
            VStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { index in
                    HStack(alignment: .top, spacing: WisentDesign.Space.x3) {
                        WisentSkeleton(.line, width: 10, height: 9)
                            .frame(width: 24, alignment: .trailing)
                        WisentSkeleton(.line)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, WisentDesign.Space.x4)
                    .padding(.vertical, WisentDesign.Space.x3)
                    if index != count - 1 { Divider() }
                }
            }
        }
    }

    /// A child being's card: the status badge, then name, chips and one field.
    private func childPanels(_ count: Int) -> some View {
        VStack(spacing: WisentDesign.Space.x3) {
            ForEach(0 ..< count, id: \.self) { _ in
                WisentPanel {
                    HStack(alignment: .top, spacing: WisentDesign.Space.x4) {
                        WisentSkeleton(.block, width: 40, height: 40)
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
                            HStack(spacing: WisentDesign.Space.x3) {
                                WisentSkeleton(.heading, width: 132)
                                WisentSkeleton(.pill, width: 64)
                                Spacer(minLength: 0)
                                WisentSkeleton(.pill, width: 72)
                            }
                            VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                                WisentSkeleton(.line, width: 66, height: 8)
                                WisentSkeleton(.line, width: 150)
                            }
                        }
                    }
                }
            }
        }
    }
}

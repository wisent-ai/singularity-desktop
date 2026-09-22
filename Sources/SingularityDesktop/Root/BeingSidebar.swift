import SwiftUI
import WisentDesignSystem

struct BeingSidebar: View {
    @ObservedObject var store: BeingStore
    @Binding var destination: BeingDestination
    let chooseDirectory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x5) {
                    ForEach(BeingDestinationGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                            Text(group.rawValue.uppercased())
                                .font(WisentTypeScale.eyebrow())
                                .tracking(0.8)
                                .foregroundStyle(WisentDesign.muted)
                                .padding(.horizontal, WisentDesign.Space.x4)
                                .padding(.bottom, WisentDesign.Space.x1)
                            ForEach(group.destinations) { item in
                                row(item)
                            }
                        }
                    }
                }
                .padding(.vertical, WisentDesign.Space.x4)
            }
        }
        .frame(width: WisentAppLayout.sidebarWidth)
        .background(WisentDesign.canvasMuted)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(WisentDesign.border)
                .frame(width: WisentDesign.hairline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WisentDesign.Space.x3) {
            HStack(spacing: WisentDesign.Space.x3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WisentDesign.brandStrong)
                    .frame(width: 34, height: 34)
                    .background(
                        WisentDesign.brandSoft,
                        in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                    )
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Singularity")
                        .font(WisentTypography.heading(15))
                        .foregroundStyle(WisentDesign.ink)
                    Text("DIGITAL BEING")
                        .font(WisentTypeScale.eyebrow())
                        .tracking(0.7)
                        .foregroundStyle(WisentDesign.muted)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Menu {
                Button("Choose folder…", action: chooseDirectory)
                Button("Show in Finder", action: store.openDirectory)
            } label: {
                VStack(alignment: .leading, spacing: WisentDesign.Space.x1) {
                    HStack(spacing: WisentDesign.Space.x2) {
                        Circle()
                            .fill(statusTone.color)
                            .frame(width: 6, height: 6)
                        Text(store.state?.identity.name ?? "No being loaded")
                            .font(WisentTypeScale.bodyStrong())
                            .foregroundStyle(WisentDesign.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(WisentDesign.muted)
                    }
                    Text(store.state.map { "\($0.identity.ticker) · \($0.status.capitalized)" } ?? "Choose a folder to begin")
                        .font(WisentTypeScale.identifierSmall())
                        .foregroundStyle(WisentDesign.secondary)
                        .lineLimit(1)
                }
                .padding(WisentDesign.Space.x2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    WisentDesign.surface,
                    in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                        .stroke(WisentDesign.border, lineWidth: WisentDesign.hairline)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Singularity folder")
        }
        .padding(WisentDesign.Space.x4)
    }

    private func row(_ item: BeingDestination) -> some View {
        let isSelected = destination == item
        return Button { destination = item } label: {
            HStack(spacing: WisentDesign.Space.x2) {
                Image(systemName: item.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? WisentDesign.brand : WisentDesign.muted)
                    .frame(width: 16)
                Text(item.title)
                    .font(isSelected ? WisentTypography.bodyMedium(12) : WisentTypography.body(12))
                    .foregroundStyle(isSelected ? WisentDesign.ink : WisentDesign.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if item == .children, let count = store.state?.mind.children.count, count > 0 {
                    WisentStatusChip(text: "\(count)", tone: .brand)
                }
            }
            .padding(.horizontal, WisentDesign.Space.x3)
            .frame(height: WisentAppLayout.denseRowHeight)
            .background(
                isSelected ? WisentDesign.surface : Color.clear,
                in: RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WisentDesign.Radius.small)
                    .stroke(isSelected ? WisentDesign.border : Color.clear, lineWidth: WisentDesign.hairline)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, WisentDesign.Space.x2)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(item.rationale)
    }


    private var statusTone: WisentTone {
        guard let state = store.state else { return .neutral }
        return beingStatusTone(state.status)
    }
}

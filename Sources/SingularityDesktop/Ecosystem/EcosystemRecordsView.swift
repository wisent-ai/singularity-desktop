import SwiftUI
import WisentDesignSystem

struct EcosystemRecordsView: View {
    let directory: URL
    @ObservedObject var store: EcosystemStore
    @Binding var expanded: Bool
    @State private var kindFilter = ""
    @State private var initiativeFilter = ""
    @State private var recordKind = ""
    @State private var recordId = ""
    @State private var selected: EcosystemRecordKey?
    @State private var previousOffsets: [UInt64] = []

    var body: some View {
        DisclosureGroup("Recorded evidence", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                HStack {
                    TextField("Kind, or leave blank for all", text: $kindFilter)
                    TextField("Initiative ID, or leave blank for all", text: $initiativeFilter)
                    Button("Read newest records") {
                        Task {
                            await store.loadRecords(directory, kind: optional(kindFilter), initiativeId: optional(initiativeFilter))
                        }
                    }
                }
                .disabled(store.busy)
                Text("Showing \(store.records.count) records · \(store.recordsKind ?? "all kinds") · \(store.recordsInitiative ?? "all initiatives")")
                    .font(WisentTypeScale.body())
                Text("Pages show the newest inserts first. Previews are shortened; Read record opens the retained contents without shortening them.")
                    .foregroundStyle(WisentDesign.secondary)
                ForEach(store.records, id: \.key) { record in
                    WisentPanel {
                        VStack(alignment: .leading, spacing: WisentDesign.Space.x2) {
                            Text(record.preview).font(WisentTypeScale.bodyStrong())
                            Text("\(record.kind) · \(record.state ?? "recorded") · \(record.totalBytes) bytes")
                            Text(record.id).font(WisentTypeScale.identifierSmall()).textSelection(.enabled)
                            Text("Created \(record.createdAt) · updated \(record.updatedAt)")
                                .foregroundStyle(WisentDesign.secondary)
                            Button("Read record") { open(record.key) }
                                .disabled(store.busy)
                                .accessibilityLabel("Read \(record.kind) \(record.id)")
                        }
                    }
                }
                if let before = store.recordsNext {
                    Button("Read older records") {
                        Task {
                            await store.loadRecords(directory, kind: store.recordsKind,
                                initiativeId: store.recordsInitiative, before: before)
                        }
                    }
                    .disabled(store.busy)
                }
                if store.records.isEmpty { Text("No records are shown on this page.") }
                HStack {
                    TextField("Record kind", text: $recordKind)
                    TextField("Record ID", text: $recordId)
                    Button("Read by ID") {
                        if let kind = optional(recordKind), let id = optional(recordId) {
                            open(.init(kind: kind, id: id))
                        }
                    }
                    .disabled(store.busy || optional(recordKind) == nil || optional(recordId) == nil)
                }
                .disabled(store.busy)
                if let selected {
                    WisentSectionBox(title: "\(selected.kind) / \(selected.id)") {
                        Button("Reload current record") { open(selected) }
                            .disabled(store.busy)
                        if let chunk = store.recordChunk, chunk.kind == selected.kind, chunk.id == selected.id {
                            Text("Bytes \(chunk.offset)..<\(chunk.offset + UInt64(chunk.text.utf8.count)) of \(chunk.totalBytes)")
                            Text("SHA-256: \(chunk.contentSha256)")
                                .font(WisentTypeScale.identifierSmall()).textSelection(.enabled)
                            ScrollView {
                                Text(chunk.text)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 320)
                            HStack {
                                if let offset = previousOffsets.last {
                                    Button("Previous fragment") {
                                        Task {
                                            if await store.readRecord(directory, kind: chunk.kind, id: chunk.id,
                                                offset: offset, revision: chunk.contentSha256) {
                                                previousOffsets.removeLast()
                                            }
                                        }
                                    }
                                }
                                if let offset = chunk.nextOffset {
                                    Button("Next fragment") {
                                        Task {
                                            if await store.readRecord(directory, kind: chunk.kind, id: chunk.id,
                                                offset: offset, revision: chunk.contentSha256) {
                                                previousOffsets.append(chunk.offset)
                                            }
                                        }
                                    }
                                }
                            }
                            .disabled(store.busy)
                            Text("Fragments keep this exact version. If the record changes, reload it explicitly; the owner refuses to mix versions.")
                                .foregroundStyle(WisentDesign.secondary)
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func open(_ key: EcosystemRecordKey) {
        selected = key
        recordKind = key.kind
        recordId = key.id
        previousOffsets = []
        Task { _ = await store.readRecord(directory, kind: key.kind, id: key.id) }
    }

    private func optional(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

//
//  ContextSummaryViews.swift
//  Dex
//
//  Created by Prateek Prakash on 10/15/26.
//

import SwiftUI

/// A summary the server made when it compacted a chat, as the summary
/// sheet shows it: what it says, and which messages it stands for.
struct ContextSummarySelection: Identifiable, Equatable {
    /// The message the model's memory starts at.
    let id: String
    let summary: String
    /// How many messages before it the summary covers, and when they were.
    let count: Int
    let from: Date?
    let to: Date?

    init(at message: ChatMessage, in messages: [ChatMessage]) {
        id = message.id
        summary = message.contextSummary ?? ""
        let earlier = messages.filter { $0.sequence < message.sequence && $0.notice == nil }
        count = earlier.count
        from = earlier.first?.createdAt
        to = earlier.last?.createdAt
    }

    /// "14 Messages, Oct 14, 5:03 PM – 9:58 PM".
    var covers: String {
        let noun = count == 1 ? "1 Message" : "\(count) Messages"
        guard let from, let to else { return noun }
        let range = (from..<max(to, from)).formatted(.interval.month(.abbreviated).day().hour().minute())
        return "\(noun), \(range)"
    }
}

/// Where the model's memory now starts: everything above reaches it only
/// as the server's summary. Tapping it shows that summary.
struct SummaryMarker: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            Rectangle().fill(Color.border).frame(height: 1.0)
            Button(action: action) {
                Text("Earlier Messages Summarized")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.s)
                    .background(Color.surfaceCode, in: Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityHint("Shows what the model remembers of them")
            Rectangle().fill(Color.border).frame(height: 1.0)
        }
    }
}

/// The summary itself, in a resizable sheet: its grabber, no close button.
struct ContextSummarySheet: View {
    let selection: ContextSummarySelection

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxxl) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        caption("SUMMARY")
                        ChatMarkdownView(text: selection.summary)
                            .equatable()
                            .textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: Space.m) {
                        caption("COVERS")
                        Text(selection.covers)
                            .font(.subheadline)
                    }
                }
                // The chat's text column; below the bar, every screen's gap.
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.xxxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbarGlassEdge()
            .background(Color.surfaceBase.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Context Summary")
                        .font(.headline)
                        .fontDesign(.rounded)
                }
            }
            .toolbarTitleDisplayMode(.inline)
        }
        .tint(Color.ink)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .tracking(1.0)
            .foregroundStyle(.secondary)
    }
}

/// The server summarizing the chat before this reply: in place of the
/// waiting dots, so the pause has a reason.
struct CompactingRow: View {
    var body: some View {
        HStack(spacing: Space.s) {
            ProgressView()
                .controlSize(.mini)
            Text("Compacting Context")
                .font(.subheadline)
                .fontDesign(.rounded)
        }
        .foregroundStyle(.secondary)
    }
}

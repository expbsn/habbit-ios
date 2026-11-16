//
//  MessageComposerSheet.swift
//  Stick
//
//  Sheet for selecting and sending motivational messages.
//

import SwiftUI
import SwiftData

struct MessageComposerSheet: View {
    let friend: FriendProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]

    @StateObject private var friendSyncService = FriendSyncService.shared

    @State private var customMessage = ""
    @State private var selectedTemplate: MessageTemplate?
    @State private var isSending = false
    @State private var showingSentConfirmation = false
    @State private var errorMessage: String?

    private var accentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.primary
        }
        return Color(hex: colorValue)
    }

    /// Color for solid button backgrounds (falls back to blue when adaptive)
    private var solidAccentColor: Color {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        if colorValue == UserPreferences.adaptiveAccentColor {
            return Color.blue
        }
        return Color(hex: colorValue)
    }

    private var canSend: Bool {
        !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedTemplate != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Text(friend.avatarEmoji)
                        .font(.system(size: 44))
                        .frame(width: 70, height: 70)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())

                    Text(String(format: String(localized: "friends_send_to"), friend.displayName))
                        .font(.headline)
                }
                .padding(.top, 8)

                // Custom Message Input
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "friends_custom_message"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField(String(localized: "friends_custom_placeholder"), text: $customMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .onChange(of: customMessage) { _, newValue in
                            if !newValue.isEmpty {
                                selectedTemplate = nil
                            }
                        }
                }
                .padding(.horizontal)

                // Quick Templates
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(localized: "friends_or_quick_message"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    // Compact template grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(MessageTemplate.allCases) { template in
                            Button {
                                withAnimation(.spring(duration: 0.2)) {
                                    selectedTemplate = template
                                    customMessage = ""
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(template.emoji)
                                        .font(.body)
                                    Text(template.shortLabel)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(selectedTemplate == template ? accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedTemplate == template ? accentColor : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Error Message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                // Send Button
                Button {
                    Task {
                        await sendMessage()
                    }
                } label: {
                    HStack {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text(String(localized: "friends_send"))
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSend ? solidAccentColor : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSend || isSending)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(String(localized: "friends_send_message"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings_cancel")) {
                        dismiss()
                    }
                }
            }
            .alert(String(localized: "friends_message_sent"), isPresented: $showingSentConfirmation) {
                Button(String(localized: "timer_done")) {
                    dismiss()
                }
            } message: {
                Text(String(format: String(localized: "friends_message_sent_to"), friend.displayName))
            }
        }
    }

    // MARK: - Send Message

    private func sendMessage() async {
        isSending = true
        errorMessage = nil

        do {
            if !customMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Send custom message
                try await friendSyncService.sendCustomMessage(to: friend, message: customMessage, context: modelContext)
            } else if let template = selectedTemplate {
                // Send template message
                try await friendSyncService.sendMessage(to: friend, template: template, context: modelContext)
            }
            showingSentConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }
}

#Preview {
    let friend = FriendProfile(
        cloudUserID: "test123",
        displayName: "Sarah",
        avatarEmoji: "😊",
        connectionStatus: .accepted
    )

    return MessageComposerSheet(friend: friend)
        .modelContainer(.preview)
}

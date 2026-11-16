//
//  FriendChatView.swift
//  Stick
//
//  Chat view for messaging with a friend.
//

import SwiftUI
import SwiftData

struct FriendChatView: View {
    let friend: FriendProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var preferences: [UserPreferences]
    @Query private var myProfile: [MyCloudProfile]

    // Live @Query properties — auto-update when SwiftData changes (real-time messages)
    @Query private var receivedMessages: [ReceivedMessage]
    @Query private var sentMessages: [SentMessage]

    @StateObject private var friendSyncService = FriendSyncService.shared

    @State private var messageText = ""
    @State private var isSending = false
    @State private var showingProfile = false

    init(friend: FriendProfile) {
        self.friend = friend
        let friendID = friend.cloudUserID
        _receivedMessages = Query(
            filter: #Predicate<ReceivedMessage> { $0.senderUserID == friendID },
            sort: \.sentDate
        )
        _sentMessages = Query(
            filter: #Predicate<SentMessage> { $0.recipientUserID == friendID },
            sort: \.sentDate
        )
    }

    // Combined and sorted chat messages
    private var allMessages: [ChatMessageItem] {
        var items: [ChatMessageItem] = []

        for msg in receivedMessages {
            items.append(ChatMessageItem(
                id: "received_\(msg.id)",
                displayText: msg.displayText,
                sentDate: msg.sentDate,
                relativeTime: msg.relativeTime,
                isFromMe: false,
                senderEmoji: msg.senderAvatarEmoji
            ))
        }

        for msg in sentMessages {
            items.append(ChatMessageItem(
                id: "sent_\(msg.id)",
                displayText: msg.displayText,
                sentDate: msg.sentDate,
                relativeTime: msg.relativeTime,
                isFromMe: true,
                senderEmoji: currentProfile?.avatarEmoji ?? "😊"
            ))
        }

        return items.sorted { $0.sentDate < $1.sentDate }
    }

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

    /// Whether we're in adaptive color mode
    private var isAdaptiveMode: Bool {
        let colorValue = preferences.first?.appAccentColor ?? UserPreferences.adaptiveAccentColor
        return colorValue == UserPreferences.adaptiveAccentColor
    }

    private var currentProfile: MyCloudProfile? {
        myProfile.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                messagesView

                // Input area
                inputArea
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        showingProfile = true
                    } label: {
                        HStack(spacing: 10) {
                            Text(friend.avatarEmoji)
                                .font(.title3)
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 4) {
                                    Text(friend.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }

                                Text(String(format: String(localized: "friends_percent_today"), Int(friend.todayCompletionPercentage * 100)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showingProfile) {
                FriendDetailSheet(friend: friend)
            }
        }
        .onAppear {
            markMessagesAsRead()
        }
        .onChange(of: receivedMessages.count) {
            // Mark newly arrived messages as read
            markMessagesAsRead()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudKitDataChanged)) { notification in
            let subscriptionID = notification.userInfo?["subscriptionID"] as? String ?? ""
            guard subscriptionID.contains("messages-") || subscriptionID.isEmpty else { return }
            Task {
                await friendSyncService.syncMessagesOnly(context: modelContext)
            }
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if allMessages.isEmpty {
                        emptyMessagesView
                    } else {
                        ForEach(allMessages) { message in
                            ChatBubble(message: message, accentColor: accentColor, isAdaptiveMode: isAdaptiveMode)
                                .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: allMessages.count) { _, _ in
                if let lastMessage = allMessages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(String(localized: "friends_no_messages_yet"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(String(localized: "friends_send_first_message"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            // Text field
            TextField(String(localized: "friends_type_message"), text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .lineLimit(1...4)

            // Send button
            Button {
                Task {
                    await sendMessage()
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? solidAccentColor : Color.gray)
            }
            .disabled(!canSend || isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        messageText = ""

        do {
            try await friendSyncService.sendCustomMessage(to: friend, message: text, context: modelContext)

        } catch {
            // Show error - could add error state
            print("Failed to send message: \(error)")
        }

        isSending = false
    }

    private func markMessagesAsRead() {
        Task {
            for message in receivedMessages where !message.isRead {
                await friendSyncService.markMessageAsRead(message, context: modelContext)
            }
        }
    }
}

// MARK: - Chat Message Item

struct ChatMessageItem: Identifiable {
    let id: String
    let displayText: String
    let sentDate: Date
    let relativeTime: String
    let isFromMe: Bool
    let senderEmoji: String
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessageItem
    let accentColor: Color
    let isAdaptiveMode: Bool

    @Environment(\.colorScheme) private var colorScheme

    /// Background color for sent messages
    private var sentMessageBackground: Color {
        if isAdaptiveMode {
            // In adaptive mode, use gray for dark mode to ensure readability
            return colorScheme == .dark ? Color(.systemGray3) : Color.primary
        }
        return accentColor
    }

    /// Text color for sent messages
    private var sentMessageTextColor: Color {
        if isAdaptiveMode {
            return colorScheme == .dark ? .white : Color(.systemBackground)
        }
        return .white
    }

    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                // Message content
                HStack(alignment: .top, spacing: 8) {
                    if !message.isFromMe {
                        Text(message.senderEmoji)
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }

                    VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 2) {
                        Text(message.displayText)
                            .font(.body)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(message.isFromMe ? sentMessageBackground : Color(.secondarySystemGroupedBackground))
                            .foregroundStyle(message.isFromMe ? sentMessageTextColor : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        Text(message.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                    }
                }
            }

            if !message.isFromMe {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Activity Day Cell

struct ActivityDayCell: View {
    let date: Date
    let progress: Double  // -1 means no data available
    let isToday: Bool
    let accentColor: Color

    private var hasData: Bool {
        progress >= 0
    }

    private var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(1))
    }

    var body: some View {
        VStack(spacing: 4) {
            // Day letter
            Text(dayName)
                .font(.caption2)
                .foregroundStyle(isToday ? accentColor : .secondary)

            // Progress ring
            ZStack {
                if hasData {
                    // Has data - show progress ring
                    Circle()
                        .stroke(isToday ? accentColor.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 3)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            progress >= 1.0 ? Color.green : accentColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                } else {
                    // No data - show dashed circle
                    Circle()
                        .stroke(
                            Color.gray.opacity(0.3),
                            style: StrokeStyle(lineWidth: 2, dash: [4, 4])
                        )
                }

                // Today indicator
                if isToday && hasData {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 28, height: 28)
        }
    }
}

#Preview {
    let friend = FriendProfile(
        cloudUserID: "test123",
        displayName: "Sarah",
        avatarEmoji: "😊",
        connectionStatus: .accepted
    )
    friend.todayCompletionPercentage = 0.85
    friend.currentStreak = 12
    friend.weeklyAverageCompletion = 0.78

    return FriendChatView(friend: friend)
        .modelContainer(.preview)
}

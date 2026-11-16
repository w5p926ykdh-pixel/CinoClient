import SwiftUI
import UIKit
import Foundation

@main
struct CinoMatrixApp: App {
    @StateObject private var matrix = MatrixStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(matrix)
                .preferredColorScheme(.dark)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// Colors sampled from the design mockup.
private enum CinoStyle {
    static let background = Color(hex: 0x332F30)
    static let chrome = Color(hex: 0x332F30)        // rail, top bar, room list
    static let header = Color(hex: 0x91868C)        // room header
    static let headerText = Color(hex: 0x3D3639)
    static let chat = Color(hex: 0x595355)          // message area
    static let label = Color(hex: 0x332D2F)         // "them" / "you"
    static let composer = Color(hex: 0xAC9DA4)
    static let composerText = Color(hex: 0x2E282B)
    static let toolbar = Color(hex: 0x4C454C)
    static let toolbarIcon = Color(hex: 0xC4B5DD)
    static let bubble = Color(hex: 0x572D21)
    static let badge = Color(hex: 0x8C888E)
    static let status = Color(hex: 0xE2A2B2)
    static let accent = Color(red: 0.78, green: 0.68, blue: 0.78)
}

struct RootView: View {
    @EnvironmentObject private var matrix: MatrixStore

    var body: some View {
        Group {
            if matrix.isLoggedIn {
                MatrixHomeView()
            } else {
                LoginView()
            }
        }
        .tint(CinoStyle.accent)
    }
}

struct LoginView: View {
    @EnvironmentObject private var matrix: MatrixStore
    @State private var user = ""
    @State private var password = ""
    @State private var homeserver = "https://matrix.unredacted.org"

    var body: some View {
        ZStack {
            CinoStyle.background.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 44))
                    .foregroundColor(CinoStyle.accent)
                Text("Cino Matrix").font(.largeTitle.bold())
                Text("Sign in to your Matrix account")
                    .foregroundColor(.secondary)
                VStack(spacing: 12) {
                    TextField("Matrix ID or username", text: $user)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                    TextField("Homeserver URL", text: $homeserver)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(15)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))

                Button {
                    Task { await matrix.login(user: user, password: password, homeserver: homeserver) }
                } label: {
                    HStack {
                        if matrix.isLoading { ProgressView().padding(.trailing, 5) }
                        Text("Sign in")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(13)
                }
                .buttonStyle(.borderedProminent)
                .disabled(matrix.isLoading || user.isEmpty || password.isEmpty)

                if let error = matrix.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                Text("Your password is sent only to the homeserver entered above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: 440)
        }
    }
}

// MARK: - Main layout
// Left rail (home / DMs / spaces) | top bar + conversation | room list of the selected space.
struct MatrixHomeView: View {
    @EnvironmentObject private var matrix: MatrixStore
    @State private var draft = ""
    @State private var showingRoomList = true

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 700
            let sidebarWidth = min(280, max(235, geometry.size.width * 0.21))

            HStack(spacing: 0) {
                NavigationRail(compact: compact)

                VStack(spacing: 0) {
                    TopBar(compact: compact) { showingRoomList.toggle() }
                    conversation(compact: compact)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showingRoomList && !compact {
                    RoomSidebar(onSelect: {})
                        .frame(width: sidebarWidth)
                }
            }
            .overlay(alignment: .trailing) {
                if showingRoomList && compact {
                    RoomSidebar(onSelect: { showingRoomList = false })
                        .frame(width: 270)
                        .shadow(color: .black.opacity(0.4), radius: 12)
                }
            }
            .background(CinoStyle.background)
            .onAppear { showingRoomList = geometry.size.width >= 700 }
        }
        .task { await matrix.startSync() }
    }

    @ViewBuilder
    private func conversation(compact: Bool) -> some View {
        if let room = matrix.selectedRoom {
            VStack(spacing: 0) {
                RoomHeader(room: room, compact: compact)

                if let error = matrix.error {
                    HStack {
                        Text(error).font(.caption).foregroundColor(.red).lineLimit(2)
                        Spacer()
                        Button { matrix.error = nil } label: { Image(systemName: "xmark") }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.12))
                }

                MessageTimeline(room: room, ownUserID: matrix.userID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Composer(draft: $draft, compact: compact, send: sendMessage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CinoStyle.chat)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 42))
                    .foregroundColor(.white.opacity(0.5))
                Text("Select a room")
                    .font(.title2.weight(.semibold))
                Text("Pick a room from the list on the right.")
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CinoStyle.chat)
        }
    }

    private func sendMessage() {
        guard let room = matrix.selectedRoom else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await matrix.send(text, to: room.id) }
    }
}

// MARK: - Left rail

struct NavigationRail: View {
    @EnvironmentObject private var matrix: MatrixStore
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: compact ? 14 : 20) {
                    RailIcon(symbol: "house", label: "Rooms", selected: matrix.nav == .rooms) {
                        matrix.select(.rooms)
                    }
                    RailIcon(symbol: "person.2", label: "Direct messages", selected: matrix.nav == .directs) {
                        matrix.select(.directs)
                    }
                }
                .padding(.top, compact ? 12 : 18)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(matrix.topLevelSpaces) { space in
                            SpaceButton(space: space, size: compact ? 40 : 46)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .padding(.top, compact ? 10 : 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(Color.black).frame(width: 8)
        }
        .frame(width: (compact ? 60 : 78) + 8)
        .frame(maxHeight: .infinity)
        .background(CinoStyle.chrome)
    }
}

struct RailIcon: View {
    let symbol: String
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: selected ? "\(symbol).fill" : symbol)
                .font(.system(size: 22))
                .foregroundColor(.white.opacity(selected ? 1 : 0.85))
                .frame(width: 44, height: 44)
                .background(selected ? Color.white.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct SpaceButton: View {
    @EnvironmentObject private var matrix: MatrixStore
    let space: MatrixRoom
    let size: CGFloat

    var body: some View {
        let selected = matrix.nav == .space(space.id)
        Button {
            matrix.select(.space(space.id))
        } label: {
            AvatarView(name: space.name, mxc: space.avatarURL, size: size, cornerRadius: size * 0.28)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(Color.white, lineWidth: selected ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(space.name)
    }
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject private var matrix: MatrixStore
    let compact: Bool
    let toggleRoomList: () -> Void

    var body: some View {
        HStack(spacing: compact ? 18 : 26) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(
                    name: matrix.displayName.isEmpty ? matrix.userID : matrix.displayName,
                    mxc: matrix.ownAvatarURL,
                    size: compact ? 34 : 42,
                    cornerRadius: 21
                )
                Circle()
                    .fill(CinoStyle.status)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(CinoStyle.chrome, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }

            Menu {
                Text(matrix.userID)
                Button(role: .destructive) {
                    matrix.logout()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")

            Button(action: toggleRoomList) {
                Image(systemName: "text.magnifyingglass")
            }
            .accessibilityLabel("Room list")

            Button {} label: { Image(systemName: "bell") }
                .accessibilityLabel("Notifications")

            Spacer(minLength: 0)
        }
        .font(.system(size: 20))
        .foregroundColor(.white.opacity(0.92))
        .buttonStyle(.plain)
        .padding(.horizontal, compact ? 16 : 40)
        .frame(height: compact ? 56 : 100)
        .frame(maxWidth: .infinity)
        .background(CinoStyle.chrome)
    }
}

// MARK: - Room header

struct RoomHeader: View {
    @EnvironmentObject private var matrix: MatrixStore
    let room: MatrixRoom
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 12 : 22) {
            AvatarView(
                name: room.name,
                mxc: matrix.avatarURL(for: room),
                size: compact ? 42 : 66,
                cornerRadius: 5
            )
            Text(room.name)
                .font(.system(size: compact ? 20 : 28))
                .foregroundColor(CinoStyle.headerText)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: compact ? 18 : 34) {
                HeaderIcon(symbol: "magnifyingglass", label: "Search")
                HeaderIcon(symbol: "pin", label: "Pinned messages")
                if !compact {
                    HeaderIcon(symbol: "bubble.left.and.bubble.right", label: "Threads")
                    HeaderIcon(symbol: "tray", label: "Inbox")
                    HeaderIcon(symbol: "photo.on.rectangle", label: "Media")
                    HeaderIcon(symbol: "person.crop.circle", label: "People")
                }
                HeaderIcon(symbol: "ellipsis", label: "More", rotated: true)
            }
        }
        .padding(.horizontal, compact ? 14 : 12)
        .padding(.trailing, compact ? 0 : 14)
        .frame(height: compact ? 64 : 105)
        .background(CinoStyle.header)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
        }
    }
}

private struct HeaderIcon: View {
    let symbol: String
    let label: String
    var rotated = false

    var body: some View {
        Button {} label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.white.opacity(0.95))
                .rotationEffect(.degrees(rotated ? 90 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Composer

struct Composer: View {
    @Binding var draft: String
    let compact: Bool
    let send: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "",
                text: $draft,
                prompt: Text("Message the room").foregroundColor(CinoStyle.composerText.opacity(0.85))
            )
            .font(.system(size: compact ? 18 : 22))
            .foregroundColor(CinoStyle.composerText)
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .onSubmit(send)

            HStack(alignment: .center, spacing: 10) {
                Button {} label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(CinoStyle.composerText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Attach")

                Spacer(minLength: 8)

                if canSend {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(CinoStyle.toolbar)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send")
                }

                ComposerToolbar()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(CinoStyle.composer, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.horizontal, compact ? 12 : 32)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }
}

private struct ComposerToolbar: View {
    var body: some View {
        HStack(spacing: 16) {
            Button {} label: {
                Text("GIF").font(.system(size: 11, weight: .bold))
            }
            .accessibilityLabel("GIF")
            Button {} label: { Image(systemName: "note.text") }
                .accessibilityLabel("Stickers")
            Button {} label: { Image(systemName: "face.smiling") }
                .accessibilityLabel("Emoji")
            Button {} label: { Image(systemName: "textformat.size") }
                .accessibilityLabel("Formatting")
            Button {} label: { Image(systemName: "mic") }
                .accessibilityLabel("Voice message")
        }
        .font(.system(size: 14))
        .foregroundColor(CinoStyle.toolbarIcon)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(CinoStyle.toolbar, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Right sidebar (rooms of the selected space)

struct RoomSidebar: View {
    @EnvironmentObject private var matrix: MatrixStore
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(matrix.sidebarTitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                Spacer()
                Button {} label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Space options")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            let rooms = matrix.sidebarRooms
            if rooms.isEmpty {
                Text("No rooms here yet.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(rooms) { room in
                            RoomRow(room: room, selected: matrix.selectedRoomID == room.id) {
                                matrix.open(room.id)
                                onSelect()
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(CinoStyle.chrome)
    }
}

struct RoomRow: View {
    @EnvironmentObject private var matrix: MatrixStore
    let room: MatrixRoom
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let unread = room.unreadCount > 0
        Button(action: action) {
            HStack(spacing: 12) {
                AvatarView(name: room.name, mxc: matrix.avatarURL(for: room), size: 28, cornerRadius: 7)
                Text(room.name)
                    .font(.system(size: 14, weight: unread ? .bold : .regular))
                    .foregroundColor(.white.opacity(unread ? 1 : 0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if unread {
                    Text(room.unreadCount > 999 ? "999+" : "\(room.unreadCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(CinoStyle.badge, in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(selected ? Color.white.opacity(0.10) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Avatars

struct AvatarView: View {
    @EnvironmentObject private var matrix: MatrixStore
    let name: String
    let mxc: String?
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 10
    @State private var image: UIImage?

    private static let palette: [Color] = [
        Color(hex: 0x6B4F7A), Color(hex: 0x4F6B7A), Color(hex: 0x7A5A4F),
        Color(hex: 0x4F7A62), Color(hex: 0x7A4F63), Color(hex: 0x5A5F8A)
    ]

    private var fallbackColor: Color {
        var total = 0
        for scalar in name.unicodeScalars { total = total &+ Int(scalar.value) }
        return Self.palette[total % Self.palette.count]
    }

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "#@! ").union(.whitespaces))
        return String(trimmed.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(fallbackColor)
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: mxc) { await load() }
    }

    private func load() async {
        guard let mxc, !mxc.isEmpty else {
            image = nil
            return
        }
        image = await matrix.avatarImage(mxc: mxc, size: Int(size * 3))
    }
}

// MARK: - Messages

struct MessageTimeline: View {
    let room: MatrixRoom
    let ownUserID: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(room.messages) { message in
                        MessageBubble(message: message, ownUserID: ownUserID)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .defaultScrollAnchor(.bottom)
            .background(CinoStyle.chat)
            .onChange(of: room.messages.count) { _, _ in
                if let last = room.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .id(room.id)
    }
}

struct MessageBubble: View {
    let message: MatrixMessage
    let ownUserID: String
    private var isOwn: Bool { message.sender == ownUserID }

    var body: some View {
        HStack(spacing: 0) {
            if isOwn { Spacer(minLength: 40) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(isOwn ? "You" : message.displaySender)
                        .font(.system(size: 19))
                        .foregroundColor(CinoStyle.label)
                        .lineLimit(1)
                    Text(message.time, style: .time)
                        .font(.caption2)
                        .foregroundColor(CinoStyle.label.opacity(0.8))
                }
                Text(message.body)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minWidth: 120, alignment: .leading)
                    .background(CinoStyle.bubble, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(maxWidth: 620, alignment: isOwn ? .trailing : .leading)
            if !isOwn { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Matrix store

@MainActor
final class MatrixStore: ObservableObject {
    @Published var rooms: [MatrixRoom] = []
    @Published var selectedRoomID: String?
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var userID = ""
    @Published var nav: NavSelection = .rooms
    @Published var displayName = ""
    @Published var ownAvatarURL: String?

    private var directRoomIDs: Set<String> = []
    private let avatarCache = NSCache<NSString, UIImage>()
    private var failedAvatars: Set<String> = []
    private var baseURL: URL?
    private var accessToken: String?
    private var nextBatch: String?
    private var syncTask: Task<Void, Never>?

    var selectedRoom: MatrixRoom? { rooms.first { $0.id == selectedRoomID } }

    // MARK: Navigation (home / DMs / spaces)

    var topLevelSpaces: [MatrixRoom] {
        var childIDs = Set<String>()
        for room in rooms where room.isSpace {
            childIDs.formUnion(room.spaceChildren.keys)
        }
        return rooms.filter { $0.isSpace && !childIDs.contains($0.id) }
    }

    func isDirect(_ room: MatrixRoom) -> Bool {
        if directRoomIDs.isEmpty { return room.looksLikeDirectMessage }
        return directRoomIDs.contains(room.id)
    }

    var sidebarRooms: [MatrixRoom] {
        switch nav {
        case .rooms:
            return rooms.filter { !$0.isSpace && !isDirect($0) }
        case .directs:
            return rooms.filter { !$0.isSpace && isDirect($0) }
        case .space(let spaceID):
            var seen = Set<String>()
            let ids = orderedRoomIDs(inSpace: spaceID, visited: [spaceID], seen: &seen)
            return ids.compactMap { id in rooms.first { $0.id == id && !$0.isSpace } }
        }
    }

    var sidebarTitle: String {
        switch nav {
        case .rooms: return "Rooms"
        case .directs: return "Direct Messages"
        case .space(let spaceID):
            return rooms.first { $0.id == spaceID }?.name ?? "Space"
        }
    }

    private func orderedRoomIDs(inSpace spaceID: String, visited: Set<String>, seen: inout Set<String>) -> [String] {
        guard let space = rooms.first(where: { $0.id == spaceID }) else { return [] }
        let children = space.spaceChildren.sorted { lhs, rhs in
            let l = lhs.value
            let r = rhs.value
            if l.isEmpty != r.isEmpty { return !l.isEmpty }
            if l != r { return l < r }
            return lhs.key < rhs.key
        }
        var result: [String] = []
        for child in children {
            let childID = child.key
            if let childRoom = rooms.first(where: { $0.id == childID }), childRoom.isSpace {
                if !visited.contains(childID) {
                    result += orderedRoomIDs(inSpace: childID, visited: visited.union([childID]), seen: &seen)
                }
            } else if seen.insert(childID).inserted {
                result.append(childID)
            }
        }
        return result
    }

    func select(_ target: NavSelection) {
        nav = target
        let visible = sidebarRooms
        if let current = selectedRoomID, visible.contains(where: { $0.id == current }) { return }
        if let first = visible.first {
            open(first.id)
        } else {
            selectedRoomID = nil
        }
    }

    func open(_ roomID: String) {
        selectedRoomID = roomID
        markRead(roomID)
    }

    func avatarURL(for room: MatrixRoom) -> String? {
        if let url = room.avatarURL, !url.isEmpty { return url }
        if isDirect(room) { return room.otherMemberAvatar(ownUserID: userID) }
        return nil
    }

    private func markRead(_ roomID: String) {
        guard let index = rooms.firstIndex(where: { $0.id == roomID }),
              let last = rooms[index].messages.last else { return }
        rooms[index].unreadCount = 0
        let room = pathComponent(roomID)
        let event = pathComponent(last.id)
        Task {
            _ = try? await request(
                path: "/_matrix/client/v3/rooms/\(room)/receipt/m.read/\(event)",
                method: "POST",
                body: [:]
            )
        }
    }

    private func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: Profile + avatars

    func loadProfile() async {
        let id = pathComponent(userID)
        guard let data = try? await request(path: "/_matrix/client/v3/profile/\(id)", method: "GET"),
              let profile = try? JSONDecoder().decode(ProfileResponse.self, from: data) else { return }
        displayName = profile.displayName ?? MatrixRoom.shortUserID(userID)
        ownAvatarURL = profile.avatarURL
    }

    func avatarImage(mxc: String, size: Int) async -> UIImage? {
        let cacheKey = "\(mxc)#\(size)"
        if let cached = avatarCache.object(forKey: cacheKey as NSString) { return cached }
        if failedAvatars.contains(cacheKey) { return nil }
        guard mxc.hasPrefix("mxc://") else { return nil }
        let rest = String(mxc.dropFirst("mxc://".count))
        let parts = rest.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let query = "?width=\(size)&height=\(size)&method=crop"
        // Newer homeservers need the authenticated media endpoint; older ones use v3.
        let paths = [
            "/_matrix/client/v1/media/thumbnail/\(parts[0])/\(parts[1])\(query)",
            "/_matrix/media/v3/thumbnail/\(parts[0])/\(parts[1])\(query)"
        ]
        for path in paths {
            if let data = try? await request(path: path, method: "GET"),
               let image = UIImage(data: data) {
                avatarCache.setObject(image, forKey: cacheKey as NSString)
                return image
            }
        }
        failedAvatars.insert(cacheKey)
        return nil
    }

    func login(user: String, password: String, homeserver: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let server = try await discover(homeserver: homeserver, matrixID: user)
            baseURL = server
            let payload: [String: Any] = [
                "type": "m.login.password",
                "identifier": ["type": "m.id.user", "user": normalizedUser(user)],
                "password": password
            ]
            let data = try await request(path: "/_matrix/client/v3/login", method: "POST", body: payload, authenticated: false)
            let result = try JSONDecoder().decode(LoginResponse.self, from: data)
            accessToken = result.accessToken
            userID = result.userID
            isLoggedIn = true
            await loadProfile()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startSync() async {
        guard isLoggedIn, syncTask == nil else { return }
        syncTask = Task {
            while !Task.isCancelled {
                do {
                    var path = "/_matrix/client/v3/sync?timeout=25000"
                    if let since = nextBatch {
                        let encoded = since.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? since
                        path += "&since=\(encoded)"
                    }
                    let data = try await request(path: path, method: "GET")
                    let sync = try JSONDecoder().decode(SyncResponse.self, from: data)
                    nextBatch = sync.nextBatch
                    apply(sync)
                } catch {
                    if !Task.isCancelled {
                        self.error = error.localizedDescription
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                }
            }
        }
    }

    func send(_ text: String, to roomID: String) async {
        do {
            let txn = UUID().uuidString
            let room = pathComponent(roomID)
            _ = try await request(
                path: "/_matrix/client/v3/rooms/\(room)/send/m.room.message/\(txn)",
                method: "PUT",
                body: ["msgtype": "m.text", "body": text]
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() {
        syncTask?.cancel()
        syncTask = nil
        accessToken = nil
        baseURL = nil
        nextBatch = nil
        userID = ""
        rooms = []
        selectedRoomID = nil
        isLoggedIn = false
        error = nil
        nav = .rooms
        directRoomIDs = []
        displayName = ""
        ownAvatarURL = nil
        failedAvatars = []
        avatarCache.removeAllObjects()
    }

    private func apply(_ sync: SyncResponse) {
        for event in sync.accountData?.events ?? [] where event.type == "m.direct" {
            var ids = Set<String>()
            for list in event.content.direct.values { ids.formUnion(list) }
            directRoomIDs = ids
        }

        for (roomID, joined) in sync.rooms?.join ?? [:] {
            let incomingState = joined.state.events + joined.timeline.events.filter { $0.stateKey != nil }
            var room = rooms.first(where: { $0.id == roomID }) ?? MatrixRoom(id: roomID)

            for event in incomingState {
                switch event.type {
                case "m.room.name":
                    room.explicitName = event.content.name
                case "m.room.canonical_alias":
                    room.canonicalAlias = event.content.alias
                case "m.room.avatar":
                    room.avatarURL = event.content.url
                case "m.room.create":
                    room.isSpace = event.content.roomType == "m.space"
                case "m.space.child":
                    guard let childID = event.stateKey else { continue }
                    if let via = event.content.via, !via.isEmpty {
                        room.spaceChildren[childID] = event.content.order ?? ""
                    } else {
                        room.spaceChildren.removeValue(forKey: childID)
                    }
                case "m.room.member":
                    guard let memberID = event.stateKey else { continue }
                    if event.content.membership == "leave" || event.content.membership == "ban" {
                        room.memberNames.removeValue(forKey: memberID)
                        room.memberAvatars.removeValue(forKey: memberID)
                    } else if event.content.membership == "join" {
                        room.memberNames[memberID] = event.content.displayName ?? MatrixRoom.shortUserID(memberID)
                        room.memberAvatars[memberID] = event.content.avatarURL
                    }
                default:
                    break
                }
            }

            let newMessages = joined.timeline.events.compactMap { event -> MatrixMessage? in
                guard event.type == "m.room.message", let body = event.content.body else { return nil }
                return MatrixMessage(
                    id: event.eventID ?? UUID().uuidString,
                    sender: event.sender,
                    displaySender: event.content.senderDisplayName ?? MatrixRoom.shortUserID(event.sender),
                    body: body,
                    time: Date(timeIntervalSince1970: Double(event.originServerTS ?? 0) / 1000)
                )
            }
            for message in newMessages where !room.messages.contains(where: { $0.id == message.id }) {
                room.messages.append(message)
            }
            room.messages.sort { $0.time < $1.time }
            room.name = room.resolvedName(ownUserID: userID)
            if let count = joined.unreadNotifications?.notificationCount {
                room.unreadCount = count
            }

            if let index = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[index] = room
            } else {
                rooms.append(room)
            }
        }
        rooms.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if selectedRoomID == nil, let first = sidebarRooms.first { selectedRoomID = first.id }
        if let selected = selectedRoom, selected.unreadCount > 0 { markRead(selected.id) }
    }

    private func normalizedUser(_ input: String) -> String {
        if input.hasPrefix("@"), let colon = input.firstIndex(of: ":") {
            return String(input[input.index(after: input.startIndex)..<colon])
        }
        return input
    }

    private func discover(homeserver: String, matrixID: String) async throws -> URL {
        let trimmed = homeserver.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }
        let domain = matrixID.split(separator: ":").last.map(String.init) ?? trimmed
        guard let wellKnown = URL(string: "https://\(domain)/.well-known/matrix/client") else {
            throw MatrixError.badURL
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: wellKnown)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hs = (json["m.homeserver"] as? [String: Any])?["base_url"] as? String,
               let url = URL(string: hs) {
                return url
            }
        } catch {
            // Fall through to the Matrix ID domain as the standard default.
        }
        guard let fallback = URL(string: "https://\(domain)") else { throw MatrixError.badURL }
        return fallback
    }

    private func request(path: String, method: String, body: [String: Any]? = nil, authenticated: Bool = true) async throws -> Data {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else { throw MatrixError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MatrixError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(MatrixAPIError.self, from: data)
            throw MatrixError.server(apiError?.error ?? "HTTP \(http.statusCode)")
        }
        return data
    }
}

struct MatrixRoom: Identifiable {
    let id: String
    var name = ""
    var explicitName: String?
    var canonicalAlias: String?
    var avatarURL: String?
    var memberNames: [String: String] = [:]
    var memberAvatars: [String: String] = [:]
    var messages: [MatrixMessage] = []
    var isSpace = false
    var spaceChildren: [String: String] = [:]   // child room ID -> `order` ("" if none)
    var unreadCount = 0
    var preview: String? { messages.last?.body }

    /// Fallback when the account has no `m.direct` data: unnamed room with exactly two members.
    var looksLikeDirectMessage: Bool {
        let hasName = !(explicitName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !isSpace && !hasName && canonicalAlias == nil && memberNames.count == 2
    }

    func otherMemberAvatar(ownUserID: String) -> String? {
        for (memberID, url) in memberAvatars where memberID != ownUserID && !url.isEmpty {
            return url
        }
        return nil
    }

    init(id: String) { self.id = id }

    func resolvedName(ownUserID: String) -> String {
        if let explicitName, !explicitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitName
        }
        if let canonicalAlias, !canonicalAlias.isEmpty { return canonicalAlias }
        let names = memberNames
            .filter { $0.key != ownUserID }
            .map { $0.value }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        switch names.count {
        case 0: return "Unnamed room"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        case 3: return "\(names[0]), \(names[1]), and \(names[2])"
        default: return "\(names[0]), \(names[1]), and \(names.count - 2) others"
        }
    }

    static func shortUserID(_ userID: String) -> String {
        guard userID.hasPrefix("@"), let colon = userID.firstIndex(of: ":") else { return userID }
        return String(userID[userID.index(after: userID.startIndex)..<colon])
    }
}

struct MatrixMessage: Identifiable {
    let id: String
    let sender: String
    let displaySender: String
    let body: String
    let time: Date
}

struct LoginResponse: Decodable {
    let accessToken: String
    let userID: String
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case userID = "user_id"
    }
}
struct MatrixAPIError: Decodable { let error: String? }
struct ProfileResponse: Decodable {
    let displayName: String?
    let avatarURL: String?
    enum CodingKeys: String, CodingKey {
        case displayName = "displayname"
        case avatarURL = "avatar_url"
    }
}
struct SyncResponse: Decodable {
    let nextBatch: String
    let rooms: SyncRooms?
    let accountData: AccountDataList?
    enum CodingKeys: String, CodingKey {
        case nextBatch = "next_batch"
        case rooms
        case accountData = "account_data"
    }
}
struct SyncRooms: Decodable {
    let join: [String: JoinedRoom]
    enum CodingKeys: String, CodingKey { case join }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        join = try c.decodeIfPresent([String: JoinedRoom].self, forKey: .join) ?? [:]
    }
}
struct JoinedRoom: Decodable {
    let state: EventList
    let timeline: EventList
    let unreadNotifications: UnreadNotifications?
    enum CodingKeys: String, CodingKey {
        case state, timeline
        case unreadNotifications = "unread_notifications"
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(EventList.self, forKey: .state) ?? EventList()
        timeline = try c.decodeIfPresent(EventList.self, forKey: .timeline) ?? EventList()
        unreadNotifications = try? c.decodeIfPresent(UnreadNotifications.self, forKey: .unreadNotifications)
    }
}
struct UnreadNotifications: Decodable {
    let notificationCount: Int?
    enum CodingKeys: String, CodingKey { case notificationCount = "notification_count" }
}
struct EventList: Decodable {
    let events: [MatrixEvent]
    enum CodingKeys: String, CodingKey { case events }
    init(events: [MatrixEvent] = []) { self.events = events }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent([MatrixEvent].self, forKey: .events) ?? []
    }
}
struct AccountDataList: Decodable { let events: [AccountDataEvent] }
struct AccountDataEvent: Decodable {
    let type: String
    let content: AccountDataContent
}
/// Only `m.direct` is used: a map of user ID -> room IDs. Other account data decodes to an empty map.
struct AccountDataContent: Decodable {
    let direct: [String: [String]]
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        direct = (try? container.decode([String: [String]].self)) ?? [:]
    }
}
struct MatrixEvent: Decodable {
    let type: String
    let sender: String
    let eventID: String?
    let originServerTS: Int64?
    let stateKey: String?
    let content: EventContent
    enum CodingKeys: String, CodingKey {
        case type, sender, content
        case eventID = "event_id"
        case originServerTS = "origin_server_ts"
        case stateKey = "state_key"
    }
}
struct EventContent: Decodable {
    let body: String?
    let name: String?
    let alias: String?
    let url: String?
    let displayName: String?
    let senderDisplayName: String?
    let membership: String?
    let avatarURL: String?
    let roomType: String?      // m.room.create: "m.space" for spaces
    let order: String?         // m.space.child
    let via: [String]?         // m.space.child (empty/missing = removed)
    enum CodingKeys: String, CodingKey {
        case body, name, alias, url, membership, order, via
        case displayName = "displayname"
        case senderDisplayName = "sender_display_name"
        case avatarURL = "avatar_url"
        case roomType = "type"
    }
    // Lenient: one oddly-typed field in some event must not break the whole sync.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        body = try? c.decodeIfPresent(String.self, forKey: .body)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        alias = try? c.decodeIfPresent(String.self, forKey: .alias)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        displayName = try? c.decodeIfPresent(String.self, forKey: .displayName)
        senderDisplayName = try? c.decodeIfPresent(String.self, forKey: .senderDisplayName)
        membership = try? c.decodeIfPresent(String.self, forKey: .membership)
        avatarURL = try? c.decodeIfPresent(String.self, forKey: .avatarURL)
        roomType = try? c.decodeIfPresent(String.self, forKey: .roomType)
        order = try? c.decodeIfPresent(String.self, forKey: .order)
        via = try? c.decodeIfPresent([String].self, forKey: .via)
    }
}

enum NavSelection: Hashable {
    case rooms
    case directs
    case space(String)
}

enum MatrixError: LocalizedError {
    case badURL, invalidResponse, server(String)
    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid homeserver URL."
        case .invalidResponse: return "The homeserver returned an invalid response."
        case .server(let message): return message
        }
    }
}

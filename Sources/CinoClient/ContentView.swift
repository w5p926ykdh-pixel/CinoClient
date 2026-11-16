import SwiftUI
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

private enum CinoStyle {
    static let background = Color(red: 0.075, green: 0.075, blue: 0.085)
    static let rail = Color(red: 0.055, green: 0.055, blue: 0.065)
    static let panel = Color(red: 0.13, green: 0.125, blue: 0.14)
    static let header = Color(red: 0.29, green: 0.265, blue: 0.29)
    static let composer = Color(red: 0.22, green: 0.20, blue: 0.23)
    static let accent = Color(red: 0.78, green: 0.68, blue: 0.78)
    static let bubble = Color(red: 0.105, green: 0.105, blue: 0.12)
    static let ownBubble = Color(red: 0.30, green: 0.17, blue: 0.13)
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

// Layout: server/navigation rail | conversation | room list.
struct MatrixHomeView: View {
    @EnvironmentObject private var matrix: MatrixStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var draft = ""
    @State private var showingRoomList = true

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                NavigationRail(logout: matrix.logout)
                    .frame(width: 70)

                conversation
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if geometry.size.width > 700 && showingRoomList {
                    RoomSidebar()
                        .environmentObject(matrix)
                        .frame(width: min(280, max(235, geometry.size.width * 0.23)))
                }
            }
            .background(CinoStyle.background)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .task { await matrix.startSync() }
    }

    @ViewBuilder
    private var conversation: some View {
        if let room = matrix.selectedRoom {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.name)
                            .font(.system(size: 19, weight: .semibold))
                            .lineLimit(1)
                        Text(room.id)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button {} label: { Image(systemName: "magnifyingglass") }
                    Button {} label: { Image(systemName: "pin") }
                    Button {} label: { Image(systemName: "person.2") }
                    Button { showingRoomList.toggle() } label: { Image(systemName: "sidebar.right") }
                }
                .font(.system(size: 18))
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .frame(height: 82)
                .background(CinoStyle.header)

                if let error = matrix.error {
                    HStack {
                        Text(error).font(.caption).foregroundColor(.red).lineLimit(2)
                        Spacer()
                        Button { matrix.error = nil } label: { Image(systemName: "xmark") }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.08))
                }

                MessageTimeline(room: room, ownUserID: matrix.userID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack(alignment: .bottom, spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    TextField("Message the room", text: $draft)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 11))
                        .onSubmit(sendMessage)
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 27))
                            .foregroundColor(.purple)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(CinoStyle.composer)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 42))
                    .foregroundColor(.secondary)
                Text("Select a room")
                    .font(.title2.weight(.semibold))
                Text("Your joined Matrix rooms will appear on the right.")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CinoStyle.background)
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

struct NavigationRail: View {
    let logout: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 27))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(CinoStyle.header, in: RoundedRectangle(cornerRadius: 15))
                .padding(.top, 12)

            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            RailButton(symbol: "house.fill", selected: true)
            RailButton(symbol: "person.2.fill")
            RailButton(symbol: "bell")
            Spacer()
            Button(action: logout) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 46, height: 46)
            }
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity)
        .background(CinoStyle.rail)
    }
}

struct RailButton: View {
    let symbol: String
    var selected = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 21))
            .foregroundColor(selected ? .white : .white.opacity(0.7))
            .frame(width: 46, height: 46)
            .background(selected ? CinoStyle.header : Color.clear, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RoomSidebar: View {
    @EnvironmentObject private var matrix: MatrixStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Rooms")
                    .font(.headline)
                Spacer()
                Text("\(matrix.rooms.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 82)
            .background(CinoStyle.panel)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(matrix.rooms) { room in
                        Button {
                            matrix.selectedRoomID = room.id
                        } label: {
                            HStack(spacing: 10) {
                                RoomAvatar(name: room.name, avatarURL: room.avatarURL)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(room.name)
                                        .font(.system(size: 14, weight: matrix.selectedRoomID == room.id ? .semibold : .regular))
                                        .lineLimit(1)
                                    if let preview = room.preview {
                                        Text(preview)
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.52))
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(matrix.selectedRoomID == room.id ? Color.white.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 7)
                    }
                }
                .padding(.vertical, 9)
            }
            .background(CinoStyle.panel)
        }
        .background(CinoStyle.panel)
    }
}

struct RoomAvatar: View {
    let name: String
    let avatarURL: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11).fill(CinoStyle.header)
            Text(String(name.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: 38, height: 38)
    }
}

struct MessageTimeline: View {
    let room: MatrixRoom
    let ownUserID: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(room.messages) { message in
                        MessageBubble(message: message, ownUserID: ownUserID)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
            }
            .background(Color.black)
            .onChange(of: room.messages.count) { _ in
                if let last = room.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: MatrixMessage
    let ownUserID: String
    private var isOwn: Bool { message.sender == ownUserID }

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(message.displaySender)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                    Text(message.time, style: .time)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.38))
                }
                Text(message.body)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 760, alignment: .leading)
            .background(isOwn ? CinoStyle.ownBubble : CinoStyle.bubble, in: RoundedRectangle(cornerRadius: 13))
            if !isOwn { Spacer(minLength: 50) }
        }
    }
}

@MainActor
final class MatrixStore: ObservableObject {
    @Published var rooms: [MatrixRoom] = []
    @Published var selectedRoomID: String?
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var userID = ""

    private var baseURL: URL?
    private var accessToken: String?
    private var nextBatch: String?
    private var syncTask: Task<Void, Never>?

    var selectedRoom: MatrixRoom? { rooms.first { $0.id == selectedRoomID } }

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
            let room = roomID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomID
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
    }

    private func apply(_ sync: SyncResponse) {
        for (roomID, joined) in sync.rooms.join {
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
                case "m.room.member":
                    guard let memberID = event.stateKey else { continue }
                    if event.content.membership == "leave" || event.content.membership == "ban" {
                        room.memberNames.removeValue(forKey: memberID)
                    } else if event.content.membership == "join" {
                        room.memberNames[memberID] = event.content.displayName ?? MatrixRoom.shortUserID(memberID)
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

            if let index = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[index] = room
            } else {
                rooms.append(room)
            }
        }
        rooms.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if selectedRoomID == nil { selectedRoomID = rooms.first?.id }
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
    var messages: [MatrixMessage] = []
    var preview: String? { messages.last?.body }

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
struct SyncResponse: Decodable {
    let nextBatch: String
    let rooms: SyncRooms
    enum CodingKeys: String, CodingKey { case nextBatch = "next_batch", rooms }
}
struct SyncRooms: Decodable { let join: [String: JoinedRoom] }
struct JoinedRoom: Decodable { let state: EventList; let timeline: EventList }
struct EventList: Decodable { let events: [MatrixEvent] }
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
    enum CodingKeys: String, CodingKey {
        case body, name, alias, url, membership
        case displayName = "displayname"
        case senderDisplayName = "sender_display_name"
    }
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

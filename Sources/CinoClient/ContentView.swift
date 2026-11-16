import SwiftUI

@main
struct CinoMatrixApp: App {
    @StateObject private var matrix = MatrixStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(matrix)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var matrix: MatrixStore
    var body: some View {
        Group {
            if matrix.isLoggedIn { MatrixHomeView() }
            else { LoginView() }
        }
        .tint(Color(red: 0.78, green: 0.68, blue: 0.76))
    }
}

struct LoginView: View {
    @EnvironmentObject private var matrix: MatrixStore
    @State private var user = ""
    @State private var password = ""
    @State private var homeserver = "https://matrix.org"
    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.11, blue: 0.12).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 42)).foregroundStyle(.purple)
                Text("Cino Matrix").font(.largeTitle.bold())
                Text("Sign in to your Matrix account").foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    TextField("Matrix ID or username", text: $user)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $password).textContentType(.password)
                    TextField("Homeserver URL", text: $homeserver)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(14).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                Button {
                    Task { await matrix.login(user: user, password: password, homeserver: homeserver) }
                } label: {
                    HStack { if matrix.isLoading { ProgressView() }; Text("Sign in") }
                        .frame(maxWidth: .infinity).padding(14)
                }
                .buttonStyle(.borderedProminent).disabled(matrix.isLoading || user.isEmpty || password.isEmpty)
                if let error = matrix.error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                Text("Use your own trusted homeserver. Your password is sent only to the server you enter.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(28).frame(maxWidth: 440)
        }
    }
}

struct MatrixHomeView: View {
    @EnvironmentObject private var matrix: MatrixStore
    @State private var draft = ""
    @State private var showRooms = true
    var body: some View {
        NavigationSplitView {
            List(selection: $matrix.selectedRoomID) {
                Section("Rooms") {
                    ForEach(matrix.rooms) { room in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.name).font(.body.weight(.medium))
                            if let preview = room.preview { Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }.tag(room.id)
                    }
                }
            }
            .navigationTitle("Cino Matrix")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { matrix.logout() } label: { Image(systemName: "rectangle.portrait.and.arrow.right") }
                }
            }
        } detail: {
            if let room = matrix.selectedRoom {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name).font(.title3.weight(.semibold))
                            Text(room.id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "magnifyingglass").padding(.horizontal, 8)
                        Image(systemName: "pin").padding(.horizontal, 8)
                        Image(systemName: "person.2").padding(.horizontal, 8)
                    }
                    .padding().background(Color(red: 0.31, green: 0.28, blue: 0.31))
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(room.messages) { message in
                                    MessageBubble(message: message, ownUserID: matrix.userID)
                                        .id(message.id)
                                }
                            }.padding()
                        }
                        .onChange(of: room.messages.count) { _, _ in
                            if let last = room.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                        }
                    }
                    HStack(alignment: .bottom, spacing: 10) {
                        Image(systemName: "plus.circle").font(.title2).foregroundStyle(.secondary)
                        TextField("Message the room", text: $draft, axis: .vertical)
                            .lineLimit(1...5).padding(10)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        Button {
                            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            draft = ""
                            Task { await matrix.send(text, to: room.id) }
                        } label: { Image(systemName: "arrow.up.circle.fill").font(.title).foregroundStyle(.purple) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding().background(Color(red: 0.27, green: 0.24, blue: 0.27))
                }
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Select a room", systemImage: "bubble.left.and.bubble.right", description: Text("Your joined Matrix rooms will appear in the sidebar."))
            }
        }
        .navigationSplitViewStyle(.balanced)
        .task { await matrix.startSync() }
    }
}

struct MessageBubble: View {
    let message: MatrixMessage
    let ownUserID: String
    private var isOwn: Bool { message.sender == ownUserID }
    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 55) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(message.sender).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Text(message.time, style: .time).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(message.body).textSelection(.enabled)
            }
            .padding(11)
            .background(isOwn ? Color(red: 0.34, green: 0.23, blue: 0.19) : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            if !isOwn { Spacer(minLength: 55) }
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
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let server = try await discover(homeserver: homeserver, matrixID: user)
            baseURL = server
            let payload: [String: Any] = ["type": "m.login.password", "identifier": ["type": "m.id.user", "user": normalizedUser(user)], "password": password]
            let data = try await request(path: "/_matrix/client/v3/login", method: "POST", body: payload, authenticated: false)
            let result = try JSONDecoder().decode(LoginResponse.self, from: data)
            accessToken = result.accessToken; userID = result.userID; isLoggedIn = true
        } catch { self.error = error.localizedDescription }
    }

    func startSync() async {
        guard isLoggedIn, syncTask == nil else { return }
        syncTask = Task {
            while !Task.isCancelled {
                do {
                    var path = "/_matrix/client/v3/sync?timeout=25000"
                    if let since = nextBatch { path += "&since=\(since.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? since)" }
                    let data = try await request(path: path, method: "GET")
                    let sync = try JSONDecoder().decode(SyncResponse.self, from: data)
                    nextBatch = sync.nextBatch
                    apply(sync)
                } catch {
                    if !Task.isCancelled { self.error = error.localizedDescription; try? await Task.sleep(for: .seconds(3)) }
                }
            }
        }
    }

    func send(_ text: String, to roomID: String) async {
        do {
            let txn = UUID().uuidString
            let room = roomID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomID
            _ = try await request(path: "/_matrix/client/v3/rooms/\(room)/send/m.room.message/\(txn)", method: "PUT", body: ["msgtype": "m.text", "body": text])
        } catch { self.error = error.localizedDescription }
    }

    func logout() {
        syncTask?.cancel(); syncTask = nil
        accessToken = nil; baseURL = nil; nextBatch = nil; userID = ""
        rooms = []; selectedRoomID = nil; isLoggedIn = false
    }

    private func apply(_ sync: SyncResponse) {
        for (roomID, joined) in sync.rooms.join {
            let name = joined.state.events.first(where: { $0.type == "m.room.name" })?.content.name
                ?? joined.state.events.first(where: { $0.type == "m.room.canonical_alias" })?.content.alias
                ?? roomID
            let messages = joined.timeline.events.compactMap { event -> MatrixMessage? in
                guard event.type == "m.room.message", let body = event.content.body else { return nil }
                return MatrixMessage(id: event.eventID ?? UUID().uuidString, sender: event.sender, body: body, time: Date(timeIntervalSince1970: Double(event.originServerTS ?? 0) / 1000))
            }
            if let index = rooms.firstIndex(where: { $0.id == roomID }) {
                rooms[index].name = name
                for message in messages where !rooms[index].messages.contains(where: { $0.id == message.id }) { rooms[index].messages.append(message) }
            } else {
                rooms.append(MatrixRoom(id: roomID, name: name, messages: messages))
            }
        }
        rooms.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if selectedRoomID == nil { selectedRoomID = rooms.first?.id }
    }

    private func normalizedUser(_ input: String) -> String {
        if input.hasPrefix("@"), let colon = input.firstIndex(of: ":") { return String(input[input.index(after: input.startIndex)..<colon]) }
        return input
    }

    private func discover(homeserver: String, matrixID: String) async throws -> URL {
        if let url = URL(string: homeserver), url.scheme != nil { return url }
        let domain = matrixID.split(separator: ":").last.map(String.init) ?? homeserver
        guard let wellKnown = URL(string: "https://\(domain)/.well-known/matrix/client") else { throw MatrixError.badURL }
        do {
            let (data, _) = try await URLSession.shared.data(from: wellKnown)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let hs = (json?["m.homeserver"] as? [String: Any])?["base_url"] as? String
            if let hs, let url = URL(string: hs) { return url }
        } catch { }
        guard let fallback = URL(string: "https://\(domain)") else { throw MatrixError.badURL }
        return fallback
    }

    private func request(path: String, method: String, body: [String: Any]? = nil, authenticated: Bool = true) async throws -> Data {
        guard let baseURL, let url = URL(string: path, relativeTo: baseURL) else { throw MatrixError.badURL }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MatrixError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = (try? JSONDecoder().decode(MatrixAPIError.self, from: data))
            throw MatrixError.server(apiError?.error ?? "HTTP \(http.statusCode)")
        }
        return data
    }
}

struct MatrixRoom: Identifiable {
    let id: String
    var name: String
    var messages: [MatrixMessage]
    var preview: String? { messages.last?.body }
}
struct MatrixMessage: Identifiable {
    let id: String; let sender: String; let body: String; let time: Date
}
struct LoginResponse: Decodable { let accessToken: String; let userID: String
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", userID = "user_id" }
}
struct MatrixAPIError: Decodable { let error: String? }
struct SyncResponse: Decodable { let nextBatch: String; let rooms: SyncRooms
    enum CodingKeys: String, CodingKey { case nextBatch = "next_batch", rooms }
}
struct SyncRooms: Decodable { let join: [String: JoinedRoom] }
struct JoinedRoom: Decodable { let state: EventList; let timeline: EventList }
struct EventList: Decodable { let events: [MatrixEvent] }
struct MatrixEvent: Decodable {
    let type: String; let sender: String; let eventID: String?; let originServerTS: Int64?; let content: EventContent
    enum CodingKeys: String, CodingKey { case type, sender, content; case eventID = "event_id"; case originServerTS = "origin_server_ts" }
}
struct EventContent: Decodable { let body: String?; let name: String?; let alias: String?
    enum CodingKeys: String, CodingKey { case body, name; case alias = "alias" }
}
enum MatrixError: LocalizedError {
    case badURL, invalidResponse, server(String)
    var errorDescription: String? {
        switch self { case .badURL: return "Invalid homeserver URL."; case .invalidResponse: return "The homeserver returned an invalid response."; case .server(let message): return message }
    }
}

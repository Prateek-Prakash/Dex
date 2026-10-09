//
//  ListSyncTests.swift
//  DexTests
//
//  Created by Prateek Prakash on 10/9/26.
//

import Foundation
import SwiftData
import Testing
@testable import Dex

/// The drawer's chats and folders, made to match the server.
@MainActor
struct CacheApplyTests {
    private func summary(_ id: String, _ title: String, updated: Int = 100, read: Int? = 100, active: Bool = false,
                         archived: Bool = false) -> WebUIChatSummary {
        let json = #"{"id":"\#(id)","title":"\#(title)","updated_at":\#(updated),"created_at":1,"last_read_at":\#(read.map(String.init) ?? "null"),"active":\#(active),"archived":\#(archived)}"#
        return try! JSONDecoder().decode(WebUIChatSummary.self, from: Data(json.utf8))
    }

    private func folder(_ id: String, _ name: String) -> WebUIFolder {
        let json = #"{"id":"\#(id)","name":"\#(name)","meta":null,"parent_id":null,"created_at":1,"updated_at":2}"#
        return try! JSONDecoder().decode(WebUIFolder.self, from: Data(json.utf8))
    }

    private func fetch<T: PersistentModel>(_ context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    @Test func serverChatsAndFoldersArrive() throws {
        let context = ModelContext(Storage.inMemory())
        let snapshot = ServerSnapshot(
            chats: [summary("c1", "Trip Plans", updated: 200, read: 100), summary("c2", "Running", active: true),
                    summary("c3", "Old", archived: true)],
            pinned: ["c2"], folders: [folder("f1", "Lab")], folderOf: ["c1": "f1"])
        CacheSync.apply(snapshot, to: context, keep: [])
        let chats: [Chat] = fetch(context)
        #expect(Set(chats.map(\.id)) == ["c1", "c2"])
        let trip = try #require(chats.first { $0.id == "c1" })
        #expect(trip.title == "Trip Plans")
        #expect(trip.isUnread)
        #expect(trip.folder?.id == "f1")
        #expect(trip.messagesSyncedAt == nil)
        let running = try #require(chats.first { $0.id == "c2" })
        #expect(running.isActive)
        // Running isn't unread, however new.
        #expect(!running.isUnread)
        #expect(running.isPinned)
        #expect((fetch(context) as [Folder]).map(\.name) == ["Lab"])
    }

    @Test func changesAndRemovalsFollowTheServer() throws {
        let context = ModelContext(Storage.inMemory())
        let lab = Folder(id: "f1", name: "Lab")
        let gone = Folder(id: "f9", name: "Gone")
        let chat = Chat(id: "c1", title: "Old Name")
        chat.isPinned = true
        chat.folder = lab
        let deleted = Chat(id: "c2", title: "Deleted On Web")
        [lab, gone].forEach(context.insert)
        [chat, deleted].forEach(context.insert)
        CacheSync.apply(ServerSnapshot(chats: [summary("c1", "Renamed")], pinned: [], folders: [folder("f1", "Lab Notes")],
                                       folderOf: [:]), to: context, keep: [])
        #expect(chat.title == "Renamed")
        #expect(!chat.isPinned)
        #expect(chat.folder == nil)
        #expect(lab.name == "Lab Notes")
        #expect((fetch(context) as [Chat]).map(\.id) == ["c1"])
        #expect((fetch(context) as [Folder]).map(\.id) == ["f1"])
    }

    @Test func chatsOpenOrReplyingHereStay() throws {
        let context = ModelContext(Storage.inMemory())
        context.insert(Chat(id: "open", title: "Open"))
        CacheSync.apply(ServerSnapshot(chats: [], pinned: [], folders: [], folderOf: [:]), to: context, keep: ["open"])
        #expect((fetch(context) as [Chat]).map(\.id) == ["open"])
    }

    @Test func pinnedFollowTheChatsOrder() {
        let older = Chat(id: "a", title: "Older")
        older.isPinned = true
        let loose = Chat(id: "b", title: "Loose")
        let newer = Chat(id: "c", title: "Newer")
        newer.isPinned = true
        // The drawer's query gives them latest first.
        #expect(DrawerItem.pinned([newer, loose, older]).map(\.title) == ["Newer", "Older"])
        #expect(DrawerItem.recent([newer, loose, older]).map(\.title) == ["Loose"])
    }
}

extension StubbedNetworkTests {
    /// Refreshing the drawer from the server, and folder changes made here
    /// going to the server first.
    @Suite(.serialized)
    @MainActor
    struct ListSyncTests {
        private static func vm() -> (ChatVM, FakeServer, ModelContext) {
            let context = ModelContext(Storage.inMemory())
            let server = FakeServer()
            let vm = ChatVM()
            vm.context = context
            vm.server = server
            vm.listPollInterval = .milliseconds(50)
            UserDefaults.standard.set(true, forKey: "foldersUploaded")
            return (vm, server, context)
        }

        @Test func refreshFillsTheDrawer() async throws {
            let (vm, server, context) = Self.vm()
            server.state.setList(#"[{"id":"c1","title":"From Web","updated_at":5,"created_at":1,"last_read_at":5},{"id":"c2","title":"Foldered","updated_at":5,"created_at":1,"last_read_at":5}]"#)
            server.state.setPinned(#"[{"id":"c1","title":"From Web","updated_at":5,"created_at":1}]"#)
            server.state.setFolders(#"[{"id":"f1","name":"Lab","meta":null,"parent_id":null,"created_at":1,"updated_at":2}]"#)
            server.state.setFolderChats("f1", #"[{"id":"c2","title":"Foldered","updated_at":5,"created_at":1}]"#)
            await vm.refreshList()
            let chats = try context.fetch(FetchDescriptor<Chat>())
            #expect(Set(chats.map(\.title)) == ["From Web", "Foldered"])
            #expect(chats.first { $0.id == "c1" }?.isPinned == true)
            #expect(chats.first { $0.id == "c2" }?.folder?.name == "Lab")
        }

        @Test func runningRepliesKeepTheListFresh() async throws {
            let (vm, server, context) = Self.vm()
            server.state.setList(#"[{"id":"c1","title":"Busy","updated_at":5,"created_at":1,"last_read_at":4,"active":true}]"#)
            await vm.refreshList()
            #expect(try context.fetch(FetchDescriptor<Chat>()).first?.isActive == true)
            // Finished while the drawer looked on: the spinner becomes a dot.
            server.state.setList(#"[{"id":"c1","title":"Busy","updated_at":9,"created_at":1,"last_read_at":4,"active":false}]"#)
            try await Task.sleep(for: .milliseconds(300))
            let chat = try #require(try context.fetch(FetchDescriptor<Chat>()).first)
            #expect(!chat.isActive)
            #expect(chat.isUnread)
            // Nothing running: no more fetching.
            let fetches = server.state.listFetches
            try await Task.sleep(for: .milliseconds(200))
            #expect(server.state.listFetches == fetches)
        }

        @Test func keepsCheckingUntilStopped() async throws {
            let (vm, server, _) = Self.vm()
            let watching = Task { await vm.refreshWhileVisible(every: .milliseconds(40)) }
            try await Task.sleep(for: .milliseconds(200))
            #expect(server.state.listFetches >= 3)
            watching.cancel()
            await watching.value
            let fetches = server.state.listFetches
            try await Task.sleep(for: .milliseconds(150))
            #expect(server.state.listFetches == fetches)
        }

        @Test func theLiveChannelOpensWithTheServer() async throws {
            let (_, server, _) = Self.vm()
            try await Task.sleep(for: .milliseconds(100))
            #expect(server.connections >= 1)
        }

        @Test func aReplyStartedInTheWebUIShowsAtOnce() async throws {
            let (vm, server, context) = Self.vm()
            let chat = Chat(id: "c1", title: "Web Chat")
            context.insert(chat)
            try context.save()
            server.send(.active(chatID: "c1", isActive: true))
            #expect(chat.isActive)
            // Stopped: the list says what changed (here, a new time).
            server.state.setList(#"[{"id":"c1","title":"Web Chat","updated_at":2000000000,"created_at":1,"last_read_at":1}]"#)
            server.send(.active(chatID: "c1", isActive: false))
            #expect(!chat.isActive)
            try await Task.sleep(for: .milliseconds(200))
            #expect(chat.isUnread)
            withExtendedLifetime(vm) {}
        }

        @Test func aChatNewToDexIsFetchedWhenItStarts() async throws {
            let (vm, server, context) = Self.vm()
            defer { withExtendedLifetime(vm) {} }
            server.state.setList(#"[{"id":"c9","title":"New Chat","updated_at":5,"created_at":1,"active":true}]"#)
            server.send(.active(chatID: "c9", isActive: true))
            try await Task.sleep(for: .milliseconds(200))
            let chat = try #require(try context.fetch(FetchDescriptor<Chat>()).first)
            #expect(chat.isActive)
            // The server names it once the reply is done.
            server.send(.title(chatID: "c9", title: "planning a trip"))
            #expect(chat.title == "Planning a Trip")
        }

        @Test func openChatDeletedElsewhereGivesWayToANewOne() async throws {
            let (vm, server, context) = Self.vm()
            let chat = Chat(id: "c1", title: "Open")
            context.insert(chat)
            try context.save()
            server.state.setChat("c1", FakeServer.chatJSON(id: "c1", title: "Open", messages: [("u", "user", "Hi", nil)]))
            vm.open(chat)
            try await Task.sleep(for: .milliseconds(100))
            #expect(vm.chat?.id == "c1")
            // Deleted in the web UI: gone from the list.
            server.state.setList("[]")
            await vm.refreshList()
            #expect(vm.chat == nil)
            #expect(vm.messages.isEmpty)
            #expect(try context.fetch(FetchDescriptor<Chat>()).isEmpty)
        }

        @Test func openingAChatDeletedElsewhereClearsIt() async throws {
            let (vm, _, context) = Self.vm()
            let chat = Chat(id: "gone", title: "Gone")
            context.insert(chat)
            try context.save()
            vm.open(chat)
            try await Task.sleep(for: .milliseconds(200))
            #expect(vm.chat == nil)
            #expect(try context.fetch(FetchDescriptor<Chat>()).isEmpty)
        }

        @Test func readInTheWebUIClearsTheDotHere() async throws {
            let (vm, server, context) = Self.vm()
            let chat = Chat(id: "c1", title: "Done")
            chat.updatedAt = Date(timeIntervalSince1970: 100)
            chat.lastReadAt = Date(timeIntervalSince1970: 50)
            context.insert(chat)
            #expect(chat.isUnread)
            server.send(.read(chatID: "c1", at: Date(timeIntervalSince1970: 120)))
            #expect(!chat.isUnread)
            withExtendedLifetime(vm) {}
        }

        @Test func incognitoActivityIsIgnored() async throws {
            let (_, server, _) = Self.vm()
            let fetches = server.state.listFetches
            server.send(.active(chatID: "local:sid", isActive: false))
            try await Task.sleep(for: .milliseconds(150))
            #expect(server.state.listFetches == fetches)
        }

        @Test func openChatStaysReadAndCatchesUp() async throws {
            let (vm, server, context) = Self.vm()
            let chat = Chat(id: "c1", title: "Mine")
            chat.messagesSyncedAt = Date(timeIntervalSince1970: 5)
            chat.updatedAt = Date(timeIntervalSince1970: 5)
            context.insert(chat)
            vm.open(chat)
            server.state.setList(#"[{"id":"c1","title":"Mine","updated_at":50,"created_at":1,"last_read_at":5}]"#)
            server.state.setChat("c1", FakeServer.chatJSON(id: "c1", title: "Mine", updatedAt: 50, messages: [
                ("u", "user", "Hi", nil), ("a", "assistant", "Answered on the web", true),
            ]))
            await vm.refreshList()
            try await Task.sleep(for: .milliseconds(200))
            #expect(!chat.isUnread)
            #expect(server.readChats.contains("c1"))
            #expect(vm.messages.last?.content == "Answered on the web")
        }

        @Test func aChangeHereDuringARefreshIsntUndone() async throws {
            let (vm, server, context) = Self.vm()
            let chat = Chat(id: "c1", title: "Old")
            context.insert(chat)
            server.state.setList(#"[{"id":"c1","title":"Old","updated_at":5,"created_at":1}]"#)
            // Renamed here while the list is on its way: the stale list is
            // fetched again, by which time the server has the new name.
            server.state.duringList = {
                vm.rename(chat, to: "New")
                server.state.setList(#"[{"id":"c1","title":"New","updated_at":5,"created_at":1}]"#)
                server.state.duringList = nil
            }
            await vm.refreshList()
            #expect(chat.title == "New")
            #expect(server.state.listFetches == 2)
        }

        @Test func newFolderIsMadeOnTheServerFirst() async throws {
            let (vm, server, context) = Self.vm()
            guard case .created(let folder) = await vm.createFolder(named: "  Lab ") else {
                Issue.record("not created"); return
            }
            #expect(folder.id == "f1")
            #expect(server.state.folderOps == ["create Lab"])
            guard case .taken = await vm.createFolder(named: "lab") else {
                Issue.record("not refused"); return
            }
            #expect(try context.fetch(FetchDescriptor<Folder>()).count == 1)
        }

        @Test func folderTheServerRefusesIsntMade() async throws {
            let (vm, _, context) = Self.vm()
            vm.server = nil
            guard case .failed(let reason) = await vm.createFolder(named: "Lab") else {
                Issue.record("not failed"); return
            }
            #expect(reason == "No server is set. Add one in Settings.")
            #expect(try context.fetch(FetchDescriptor<Folder>()).isEmpty)
        }

        @Test func folderRenamesGoToTheServerFirst() async throws {
            let (vm, server, context) = Self.vm()
            let lab = Folder(id: "f1", name: "Lab")
            let trip = Folder(id: "f2", name: "Trip")
            context.insert(lab)
            context.insert(trip)
            guard case .renamed = await vm.rename(lab, to: " Home Lab ") else {
                Issue.record("not renamed"); return
            }
            #expect(lab.name == "Home Lab")
            #expect(server.state.folderOps == [#"update f1 {"name":"Home Lab"}"#])
            guard case .taken = await vm.rename(lab, to: "trip") else {
                Issue.record("not refused"); return
            }
            guard case .unchanged = await vm.rename(lab, to: "Home Lab") else {
                Issue.record("changed"); return
            }
            #expect(server.state.folderOps.count == 1)
        }

        @Test func movesAndFolderDeletesReachTheServer() async throws {
            let (vm, server, context) = Self.vm()
            let lab = Folder(id: "f1", name: "Lab")
            let chat = Chat(id: "c1", title: "Notes")
            context.insert(lab)
            context.insert(chat)
            vm.move(chat, to: lab)
            try await Task.sleep(for: .milliseconds(200))
            #expect(server.state.folderOps == ["move c1 f1"])
            vm.delete(lab)
            try await Task.sleep(for: .milliseconds(200))
            #expect(server.state.folderOps == ["move c1 f1", "delete f1"])
            #expect(try context.fetch(FetchDescriptor<Chat>()).isEmpty)
        }

        @Test func foldersMadeBeforeSyncAreUploadedOnce() async throws {
            let (vm, server, context) = Self.vm()
            UserDefaults.standard.set(false, forKey: "foldersUploaded")
            defer { UserDefaults.standard.set(true, forKey: "foldersUploaded") }
            let old = Folder(id: "local", name: "From Before")
            let chat = Chat(id: "c1", title: "Inside")
            chat.folder = old
            context.insert(old)
            context.insert(chat)
            server.state.setList(#"[{"id":"c1","title":"Inside","updated_at":5,"created_at":1}]"#)
            await vm.refreshList()
            #expect(server.state.folderOps == ["create From Before", "move c1 f1"])
            #expect(UserDefaults.standard.bool(forKey: "foldersUploaded"))
            await vm.refreshList()
            #expect(server.state.folderOps.count == 2)
        }

        @Test func uploadJoinsAFolderTheServerHasByName() async throws {
            let (vm, server, context) = Self.vm()
            UserDefaults.standard.set(false, forKey: "foldersUploaded")
            defer { UserDefaults.standard.set(true, forKey: "foldersUploaded") }
            let old = Folder(id: "local", name: "lab")
            let chat = Chat(id: "c1", title: "Inside")
            chat.folder = old
            context.insert(old)
            context.insert(chat)
            server.state.setFolders(#"[{"id":"f7","name":"Lab","meta":null,"parent_id":null,"created_at":1,"updated_at":2}]"#)
            await vm.refreshList()
            #expect(server.state.folderOps == ["move c1 f7"])
        }

        @Test func uploadSkipsAChatTheServerNoLongerHas() async throws {
            let (vm, server, context) = Self.vm()
            UserDefaults.standard.set(false, forKey: "foldersUploaded")
            defer { UserDefaults.standard.set(true, forKey: "foldersUploaded") }
            let old = Folder(id: "local", name: "From Before")
            let stale = Chat(id: "gone", title: "Deleted On Web")
            stale.folder = old
            context.insert(old)
            context.insert(stale)
            server.state.setMissing(["gone"])
            await vm.refreshList()
            // Done anyway, and the list applied: the stale chat is dropped.
            #expect(UserDefaults.standard.bool(forKey: "foldersUploaded"))
            #expect(try context.fetch(FetchDescriptor<Chat>()).isEmpty)
        }

        @Test func failedUploadKeepsTheFoldersForNextTime() async throws {
            let (vm, server, context) = Self.vm()
            UserDefaults.standard.set(false, forKey: "foldersUploaded")
            defer { UserDefaults.standard.set(true, forKey: "foldersUploaded") }
            server.state.refusesFolders = true
            let old = Folder(id: "local", name: "From Before")
            let chat = Chat(id: "c1", title: "Inside")
            chat.folder = old
            context.insert(old)
            context.insert(chat)
            await vm.refreshList()
            // Not applied: the folder and its chat are still here.
            #expect(chat.folder === old)
            #expect(try context.fetch(FetchDescriptor<Folder>()).map(\.id) == ["local"])
            #expect(!UserDefaults.standard.bool(forKey: "foldersUploaded"))
        }
    }
}

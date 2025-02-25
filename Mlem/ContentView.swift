//
//  ContentView.swift
//  Mlem
//
//  Created by David Bureš on 25.03.2022.
//

import Dependencies
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    
    @Dependency(\.errorHandler) var errorHandler
    @Dependency(\.personRepository) var personRepository
    @Dependency(\.hapticManager) var hapticManager
    
    @EnvironmentObject var appState: AppState
    
    @StateObject var editorTracker: EditorTracker = .init()
    @StateObject var unreadTracker: UnreadTracker = .init()
    
    @State private var errorAlert: ErrorAlert?
    
    // tabs
    @State private var tabSelection: TabSelection = .feeds
    @State private var tabNavigation: any FancyTabBarSelection = TabSelection._tabBarNavigation
    @State private var showLoading: Bool = false
    @GestureState private var isDetectingLongPress = false
    
    @State private var isPresentingAccountSwitcher: Bool = false
    
    @AppStorage("showInboxUnreadBadge") var showInboxUnreadBadge: Bool = true
    @AppStorage("homeButtonExists") var homeButtonExists: Bool = false
    @AppStorage("profileTabLabel") var profileTabLabel: ProfileTabLabel = .username
    
    var accessibilityFont: Bool { UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory }
    
    var body: some View {
        FancyTabBar(selection: $tabSelection, navigationSelection: $tabNavigation, dragUpGestureCallback: showAccountSwitcherDragCallback) {
            Group {
                FeedRoot(showLoading: showLoading)
                    .fancyTabItem(tag: TabSelection.feeds) {
                        FancyTabBarLabel(
                            tag: TabSelection.feeds,
                            symbolName: "scroll",
                            activeSymbolName: "scroll.fill"
                        )
                    }
                InboxView()
                    .fancyTabItem(tag: TabSelection.inbox) {
                        FancyTabBarLabel(
                            tag: TabSelection.inbox,
                            symbolName: "mail.stack",
                            activeSymbolName: "mail.stack.fill",
                            badgeCount: showInboxUnreadBadge ? unreadTracker.total : 0
                        )
                    }
                
                ProfileView(userID: appState.currentActiveAccount.id)
                    .fancyTabItem(tag: TabSelection.profile) {
                        FancyTabBarLabel(
                            tag: TabSelection.profile,
                            customText: computeUsername(account: appState.currentActiveAccount),
                            symbolName: "person.circle",
                            activeSymbolName: "person.circle.fill"
                        )
                        .simultaneousGesture(accountSwitchLongPress)
                    }
                SearchView()
                    .fancyTabItem(tag: TabSelection.search) {
                        FancyTabBarLabel(
                            tag: TabSelection.search,
                            symbolName: "magnifyingglass",
                            activeSymbolName: "text.magnifyingglass"
                        )
                    }
                
                SettingsView()
                    .fancyTabItem(tag: TabSelection.settings) {
                        FancyTabBarLabel(
                            tag: TabSelection.settings,
                            symbolName: "gear"
                        )
                    }
            }
        }
        .task(id: appState.currentActiveAccount) {
            accountChanged()
        }
        .onReceive(errorHandler.$sessionExpired) { expired in
            if expired {
                NotificationDisplayer.presentTokenRefreshFlow(for: appState.currentActiveAccount) { updatedAccount in
                    appState.setActiveAccount(updatedAccount)
                }
            }
        }
        .alert(using: $errorAlert) { content in
            Alert(
                title: Text(content.title),
                message: Text(content.message),
                dismissButton: .default(
                    Text("OK"),
                    action: { errorAlert = nil }
                )
            )
        }
        .sheet(isPresented: $isPresentingAccountSwitcher) {
            AccountsPage()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $editorTracker.editResponse) { editing in
            NavigationStack {
                ResponseEditorView(concreteEditorModel: editing)
            }
        }
        .sheet(item: $editorTracker.editPost) { editing in
            NavigationStack {
                PostComposerView(editModel: editing)
            }
        }
        .environment(\.openURL, OpenURLAction(handler: didReceiveURL))
        .environmentObject(editorTracker)
        .environmentObject(unreadTracker)
        .onChange(of: scenePhase) { phase in
            // when app moves into background, hide the account switcher. This prevents the app from reopening with the switcher enabled.
            if phase != .active {
                isPresentingAccountSwitcher = false
            }
        }
    }
    
    // MARK: Helpers
    
    /// Function that executes whenever the account changes to handle any state updates that need to happen
    func accountChanged() {
        // refresh unread count
        Task(priority: .background) {
            do {
                let unreadCounts = try await personRepository.getUnreadCounts()
                unreadTracker.update(with: unreadCounts)
            } catch {
                errorHandler.handle(error)
            }
        }
    }
    
    func computeUsername(account: SavedAccount) -> String {
        switch profileTabLabel {
        case .username: return account.username
        case .instance: return account.hostName ?? account.username
        case .nickname: return appState.currentNickname
        case .anonymous: return "Profile"
        }
    }
    
    func showAccountSwitcherDragCallback() {
        if !homeButtonExists {
            isPresentingAccountSwitcher = true
        }
    }
    
    var accountSwitchLongPress: some Gesture {
        LongPressGesture()
            .onEnded { _ in
                // disable long press in accessibility mode to prevent conflict with HUD
                if !accessibilityFont {
                    hapticManager.play(haptic: .rigidInfo, priority: .high)
                    isPresentingAccountSwitcher = true
                }
            }
    }
}

// MARK: - URL Handling

extension ContentView {
    func didReceiveURL(_ url: URL) -> OpenURLAction.Result {
        let outcome = URLHandler.handle(url)
        
        switch outcome.action {
        case let .error(message):
            errorAlert = .init(
                title: "Unsupported link",
                message: message
            )
        default:
            break
        }
        
        return outcome.result
    }
}

//
//  User View.swift
//  Mlem
//
//  Created by David Bureš on 02.04.2022.
//

import Dependencies
import SwiftUI

/// View for showing user profiles
/// Accepts the following parameters:
/// - **userID**: Non-optional ID of the user
struct UserView: View {
    @Dependency(\.apiClient) var apiClient
    @Dependency(\.errorHandler) var errorHandler
    @Dependency(\.notifier) var notifier
    
    // appstorage
    @AppStorage("shouldShowUserHeaders") var shouldShowUserHeaders: Bool = true
    
    // environment
    @EnvironmentObject var appState: AppState
    
    // parameters
    @State var userID: Int
    @State var userDetails: APIPersonView?

    @StateObject private var privatePostTracker: PostTracker
    @StateObject private var privateCommentTracker: CommentTracker = .init()
    @State private var avatarSubtext: String = ""
    @State private var showingCakeDay = false
    @State private var moderatedCommunities: [APICommunityModeratorView] = []
    
    @State private var selectionSection = UserViewTab.overview
    @State private var errorDetails: ErrorDetails?
    
    init(userID: Int, userDetails: APIPersonView? = nil) {
        @AppStorage("internetSpeed") var internetSpeed: InternetSpeed = .fast
        
        self._userID = State(initialValue: userID)
        self._userDetails = State(initialValue: userDetails)
        
        self._privatePostTracker = StateObject(wrappedValue: .init(shouldPerformMergeSorting: false, internetSpeed: internetSpeed))
    }
    
    // account switching
    @State private var isPresentingAccountSwitcher: Bool = false

    var body: some View {
        if let errorDetails {
            ErrorView(errorDetails)
                .fancyTabScrollCompatible()
        } else {
            contentView
                .sheet(isPresented: $isPresentingAccountSwitcher) {
                    AccountsPage()
                }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if let userDetails {
            view(for: userDetails)
        } else {
            progressView
        }
    }
    
    @ViewBuilder
    private var moderatorButton: some View {
        if let user = userDetails, !moderatedCommunities.isEmpty {
            NavigationLink(value: UserModeratorLink(user: user, moderatedCommunities: moderatedCommunities)) {
                Image(systemName: "shield")
            }
        }
    }
    
    @ViewBuilder
    private var accountSwitcher: some View {
        if isShowingOwnProfile() {
            Button {
                isPresentingAccountSwitcher = true
            } label: {
                Image(systemName: AppConstants.switchUserSymbolName)
            }
        }
    }

    private func header(for userDetails: APIPersonView) -> some View {
        CommunitySidebarHeader(
            title: userDetails.person.displayName ?? userDetails.person.name,
            subtitle: "@\(userDetails.person.name)@\(userDetails.person.actorId.host()!)",
            avatarSubtext: $avatarSubtext,
            avatarSubtextClicked: toggleCakeDayVisible,
            bannerURL: shouldShowUserHeaders ? userDetails.person.banner : nil,
            avatarUrl: userDetails.person.avatar,
            label1: "\(userDetails.counts.commentCount) Comments",
            label2: "\(userDetails.counts.postCount) Posts"
        )
    }
    
    private func view(for userDetails: APIPersonView) -> some View {
        ScrollView {
            header(for: userDetails)
            
            if let bio = userDetails.person.bio {
                MarkdownView(text: bio, isNsfw: false).padding()
            }
            
            Picker(selection: $selectionSection, label: Text("Profile Section")) {
                ForEach(UserViewTab.allCases, id: \.id) { tab in
                    // Skip tabs that are meant for only our profile
                    if tab.onlyShowInOwnProfile {
                        if isShowingOwnProfile() {
                            Text(tab.label).tag(tab.rawValue)
                        }
                    } else {
                        Text(tab.label).tag(tab.rawValue)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            UserFeedView(
                userID: userID,
                privatePostTracker: privatePostTracker,
                privateCommentTracker: privateCommentTracker,
                selectedTab: $selectionSection
            )
        }
        .fancyTabScrollCompatible()
        .environmentObject(privatePostTracker)
        .environmentObject(privateCommentTracker)
        .navigationTitle(userDetails.person.displayName ?? userDetails.person.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarColor()
        .headerProminence(.standard)
        .refreshable {
            await tryLoadUser()
        }.toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                accountSwitcher
                moderatorButton
            }
        }
    }
    
    private func updateAvatarSubtext() {
        if let user = userDetails {
            if showingCakeDay {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "ddMMYY", options: 0, locale: Locale.current)
                
                avatarSubtext = "Joined \(dateFormatter.string(from: user.person.published))"
            } else {
                avatarSubtext = "Joined \(user.person.published.getRelativeTime(date: Date.now))"
            }
        } else {
            avatarSubtext = ""
        }
    }
    
    private func toggleCakeDayVisible() {
        showingCakeDay = !showingCakeDay
        updateAvatarSubtext()
    }
    
    private func isShowingOwnProfile() -> Bool {
        userID == appState.currentActiveAccount.id
    }
    
    @MainActor
    private var progressView: some View {
        ProgressView {
            if isShowingOwnProfile() {
                Text("Loading your profile…")
            } else {
                Text("Loading user profile…")
            }
        }
        .task(priority: .userInitiated) {
            await tryLoadUser()
        }
    }
    
    private func tryLoadUser() async {
        do {
            let authoredContent = try await loadUser(savedItems: false)
            var savedContentData: GetPersonDetailsResponse?
            if isShowingOwnProfile() {
                savedContentData = try await loadUser(savedItems: true)
            }
            
            privateCommentTracker.add(authoredContent.comments
                .sorted(by: { $0.comment.published > $1.comment.published })
                .map { HierarchicalComment(comment: $0, children: [], parentCollapsed: false, collapsed: false) })
            
            privatePostTracker.add(authoredContent.posts.map { PostModel(from: $0) })
            
            if let savedContent = savedContentData {
                privateCommentTracker.add(savedContent.comments
                    .sorted(by: { $0.comment.published > $1.comment.published })
                    .map { HierarchicalComment(comment: $0, children: [], parentCollapsed: false, collapsed: false) })
                
                privatePostTracker.add(savedContent.posts.map { PostModel(from: $0) })
            }
            
            userDetails = authoredContent.personView
            moderatedCommunities = authoredContent.moderates
            updateAvatarSubtext()
            
            errorDetails = nil
        } catch {
            if userDetails == nil {
                errorDetails = ErrorDetails(error: error, refresh: {
                    await tryLoadUser()
                    return userDetails != nil
                })
            } else {
                errorHandler.handle(
                    .init(
                        title: "Couldn't load user info",
                        message: "There was an error while loading user information.\nTry again later.",
                        underlyingError: error
                    )
                )
            }
        }
    }
    
    private func loadUser(savedItems: Bool) async throws -> GetPersonDetailsResponse {
        try await apiClient.getPersonDetails(for: userID, limit: 20, savedOnly: savedItems)
    }
}

// TODO: darknavi - Move these to a common area for reuse
struct UserViewPreview: PreviewProvider {
    static let previewAccount = SavedAccount(
        id: 0,
        instanceLink: URL(string: "lemmy.com")!,
        accessToken: "abcdefg",
        username: "Test Account"
    )
    
    // Only Admin and Bot work right now
    // Because the rest require post/comment context
    enum PreviewUserType: String, CaseIterable {
        case normal
        case mod
        case op
        case bot
        case admin
        case dev = "developer"
    }
    
    static func generatePreviewUser(
        name: String,
        displayName: String,
        userType: PreviewUserType
    ) -> APIPerson {
        .mock(
            id: name.hashValue,
            name: name,
            displayName: displayName,
            avatar: URL(string: "https://lemmy.ml/pictrs/image/df86c06d-341c-4e79-9c80-d7c7eb64967a.jpeg?format=webp"),
            published: Date.now.advanced(by: -10000),
            actorId: URL(string: "https://google.com")!,
            bio: "Just here for the good vibes!",
            banner: URL(string: "https://i.imgur.com/wcayaCB.jpeg"),
            admin: userType == .admin,
            botAccount: userType == .bot
        )
    }
    
    static func generatePreviewComment(creator: APIPerson, isMod: Bool) -> APIComment {
        APIComment(
            id: 0,
            creatorId: creator.id,
            postId: 0,
            content: "",
            removed: false,
            deleted: false,
            published: Date.now,
            updated: nil,
            apId: "foo.bar",
            local: false,
            path: "foo",
            distinguished: isMod,
            languageId: 0
        )
    }
    
    static func generateFakeCommunity(id: Int, namePrefix: String) -> APICommunity {
        .mock(
            id: id,
            name: "\(namePrefix) Fake Community \(id)",
            title: "\(namePrefix) Fake Community \(id) Title",
            description: "This is a fake community (#\(id))",
            published: Date.now,
            actorId: URL(string: "https://lemmy.google.com/c/\(id)")!
        )
    }
    
    static func generatePreviewPost(creator: APIPerson) -> PostModel {
        let community = generateFakeCommunity(id: 123, namePrefix: "Test")
        let post: APIPost = .mock(
            name: "Test Post Title",
            body: "This is a test post body",
            creatorId: creator.id,
            embedDescription: "Embeedded Description",
            embedTitle: "Embedded Title",
            published: Date.now
        )
        
        let postVotes = APIPostAggregates(
            id: 123,
            postId: post.id,
            comments: 0,
            score: 10,
            upvotes: 15,
            downvotes: 5,
            published: Date.now,
            newestCommentTime: Date.now,
            newestCommentTimeNecro: Date.now,
            featuredCommunity: false,
            featuredLocal: false
        )
        
        return PostModel(from: APIPostView(
            post: post,
            creator: creator,
            community: community,
            creatorBannedFromCommunity: false,
            counts: postVotes,
            subscribed: .notSubscribed,
            saved: false,
            read: false,
            creatorBlocked: false,
            unreadComments: 0
        ))
    }
    
    static func generateUserProfileLink(name: String, userType: PreviewUserType) -> UserProfileLink {
        let previewUser = generatePreviewUser(name: name, displayName: name, userType: userType)
        
        var postContext: PostModel?
        var commentContext: APIComment?
        
        if userType == .mod {
            commentContext = generatePreviewComment(creator: previewUser, isMod: true)
        }
        
        if userType == .op {
            commentContext = generatePreviewComment(creator: previewUser, isMod: false)
            postContext = generatePreviewPost(creator: previewUser)
        }
        
        return UserProfileLink(
            user: previewUser,
            serverInstanceLocation: .bottom,
            overrideShowAvatar: true,
            postContext: postContext?.post,
            commentContext: commentContext
        )
    }
    
    static var previews: some View {
        UserView(
            userID: 123,
            userDetails: APIPersonView(
                person: generatePreviewUser(name: "actualUsername", displayName: "PreferredUsername", userType: .normal),
                counts: APIPersonAggregates(id: 123, personId: 123, postCount: 123, postScore: 567, commentCount: 14, commentScore: 974)
            )
        )
    }
}

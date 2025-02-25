//
//  Lazy Load Expanded Post.swift
//  Mlem
//
//  Created by Jake Shirey on 23.06.2023.
//

import Dependencies
import SwiftUI

/*
 A simple wrapper around ExpandedPost which loads the PostModel on demand for when we don't already have one
 */
struct LazyLoadExpandedPost: View {
    @Dependency(\.errorHandler) var errorHandler
    
    @State var post: APIPost
    @State var scrollTarget: Int?
    
    @State private var loadedPostView: PostModel?

    @StateObject private var postTracker = PostTracker(internetSpeed: .slow)

    var body: some View {
        Group {
            if let loadedPost = loadedPostView {
                ExpandedPost(post: PostModel(from: loadedPost), scrollTarget: scrollTarget)
                    .environmentObject(postTracker)
            } else {
                progressView
            }
        }
    }
    
    private var progressView: some View {
        ProgressView {
            Text("Loading post details…")
        }
        .task(priority: .background) {
            do {
                loadedPostView = try await postTracker.loadPost(postId: post.id)
            } catch {
                // TODO: Some sort of common alert banner?
                // we can show a toast here by passing a `message` and `style: .toast` by using a `ContextualError` below...
                errorHandler.handle(error)
            }
        }
    }
}

//
//  Upvote.swift
//  Mlem
//
//  Created by David Bureš on 25.03.2022.
//

import SwiftUI

struct UpvoteButton: View {
    let myVote: ScoringOperation

    var body: some View
    {
        HStack(alignment: .center, spacing: 2)
        {
            Image(systemName: "arrow.up")

            Text(String(score))
        }
        .foregroundColor(.accentColor)
    }
}


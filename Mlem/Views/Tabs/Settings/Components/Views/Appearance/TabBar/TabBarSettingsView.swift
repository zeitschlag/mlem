//
//  TabBarSettingsView.swift
//  Mlem
//
//  Created by Sam Marfleet on 19/07/2023.
//

import Dependencies
import SwiftUI

struct TabBarSettingsView: View {
    
    @Dependency(\.accountsTracker) var accountsTracker
    
    @AppStorage("profileTabLabel") var profileTabLabel: ProfileTabLabel = .username
    @AppStorage("showTabNames") var showTabNames: Bool = true
    @AppStorage("showInboxUnreadBadge") var showInboxUnreadBadge: Bool = true
        
    @EnvironmentObject var appState: AppState
    
    @State var textFieldEntry: String = ""
    
    var body: some View {
        Form {
            Section {
                SelectableSettingsItem(
                    settingIconSystemName: "person.text.rectangle",
                    settingName: "Profile Tab Label",
                    currentValue: $profileTabLabel,
                    options: ProfileTabLabel.allCases
                )
                
                if profileTabLabel == .nickname {
                    Label {
                        TextField(text: $textFieldEntry, prompt: Text(appState.currentNickname)) {
                            Text("Nickname")
                        }
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .onSubmit {
                            print(textFieldEntry)
                            let newAccount = SavedAccount(from: appState.currentActiveAccount, storedNickname: textFieldEntry)
                            appState.changeDisplayedNickname(to: textFieldEntry)
                            accountsTracker.update(with: newAccount)
                        }
                    } icon: {
                        Image(systemName: "rectangle.and.pencil.and.ellipsis")
                            .foregroundColor(.pink)
                    }
                }
            }
            
            Section {
                SwitchableSettingsItem(
                    settingPictureSystemName: "tag",
                    settingName: "Show Tab Labels",
                    isTicked: $showTabNames
                )
                
                SwitchableSettingsItem(
                    settingPictureSystemName: "envelope.badge",
                    settingName: "Show Unread Count",
                    isTicked: $showInboxUnreadBadge
                )
            }
        }
        .fancyTabScrollCompatible()
        .navigationTitle("Tab Bar")
        .navigationBarColor()
        .animation(.easeIn, value: profileTabLabel)
        .onChange(of: appState.currentActiveAccount.nickname) { nickname in
            print("new nickname: \(nickname)")
            textFieldEntry = nickname
        }
    }
}

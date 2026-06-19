//
//  SessionConfiguration.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import GeckoView

enum SessionOpening {
    case immediate(windowID: String?)
    case manual
    case external
}

struct SessionDelegates {
    var content: ContentDelegate?
    var navigation: NavigationDelegate?
    var permission: PermissionEmbedderDelegate?
    var progress: ProgressDelegate?
    var prompt: PromptDelegate?
    var selectionAction: SelectionActionDelegate?
    var mediaSession: MediaSessionDelegate?
    
    init(
        content: ContentDelegate? = nil,
        navigation: NavigationDelegate? = nil,
        permission: PermissionEmbedderDelegate? = nil,
        progress: ProgressDelegate? = nil,
        prompt: PromptDelegate? = nil,
        selectionAction: SelectionActionDelegate? = nil,
        mediaSession: MediaSessionDelegate? = nil
    ) {
        self.content = content
        self.navigation = navigation
        self.permission = permission
        self.progress = progress
        self.prompt = prompt
        self.selectionAction = selectionAction
        self.mediaSession = mediaSession
    }
}

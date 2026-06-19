//
//  BookmarkFolderRows.swift
//  Reynard
//
//  Created by Minh Ton on 21/5/26.
//

typealias BookmarkFolderRow = (folder: BookmarkFolderSnapshot, depth: Int)

func makeBookmarkFolderRows(root: BookmarkFolderHierarchySnapshot, store: BookmarkStore) -> [BookmarkFolderRow] {
    var folderRows: [BookmarkFolderRow] = []
    
    func appendDescendants(parentFolderID: String, depth: Int) {
        for folder in store.childFolders(in: parentFolderID).items {
            folderRows.append((folder, depth))
            appendDescendants(parentFolderID: folder.guid, depth: depth + 1)
        }
    }
    
    for folder in root.items where folder.isProtected {
        folderRows.append((folder, 0))
        appendDescendants(parentFolderID: folder.guid, depth: 1)
    }
    folderRows.append((root.parent, 0))
    for folder in root.items where !folder.isProtected {
        folderRows.append((folder, 1))
        appendDescendants(parentFolderID: folder.guid, depth: 2)
    }
    
    return folderRows
}

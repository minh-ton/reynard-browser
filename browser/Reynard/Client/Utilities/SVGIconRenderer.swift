//
//  SVGIconRenderer.swift
//  Reynard
//
//  Created by Minh Ton on 17/6/26.
//

import UIKit

enum SVGIconRenderer {
    private typealias SVGDocumentRef = UnsafeMutableRawPointer
    private typealias CreateDocumentFunction = @convention(c) (CFData, CFDictionary?) -> SVGDocumentRef?
    private typealias ReleaseDocumentFunction = @convention(c) (SVGDocumentRef) -> Void
    private typealias DrawDocumentFunction = @convention(c) (CGContext, SVGDocumentRef) -> Void
    private typealias GetCanvasSizeFunction = @convention(c) (SVGDocumentRef) -> CGSize
    
    private static let frameworkHandle = dlopen("/System/Library/PrivateFrameworks/CoreSVG.framework/CoreSVG", RTLD_LAZY)
    private static let createDocument = symbol(named: "CGSVGDocumentCreateFromData", as: CreateDocumentFunction.self)
    private static let releaseDocument = symbol(named: "CGSVGDocumentRelease", as: ReleaseDocumentFunction.self)
    private static let drawDocument = symbol(named: "CGContextDrawSVGDocument", as: DrawDocumentFunction.self)
    private static let getCanvasSize = symbol(named: "CGSVGDocumentGetCanvasSize", as: GetCanvasSizeFunction.self)
    
    static func render(data: Data, size: CGSize) -> UIImage? {
        guard let createDocument,
              let releaseDocument,
              let drawDocument else {
            return nil
        }
        
        guard let document = createDocument(data as CFData, nil) else {
            return nil
        }
        defer { releaseDocument(document) }
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.saveGState()
            applyCanvasTransform(to: cgContext, document: document, size: size)
            drawDocument(cgContext, document)
            cgContext.restoreGState()
        }
    }
    
    private static func applyCanvasTransform(to context: CGContext, document: SVGDocumentRef, size: CGSize) {
        guard let getCanvasSize else {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            return
        }
        
        let canvasSize = getCanvasSize(document)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            return
        }
        
        let scale = min(size.width / canvasSize.width, size.height / canvasSize.height)
        let scaledSize = CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
        let origin = CGPoint(x: (size.width - scaledSize.width) / 2, y: (size.height - scaledSize.height) / 2)
        context.translateBy(x: origin.x, y: origin.y + scaledSize.height)
        context.scaleBy(x: scale, y: -scale)
    }
    
    private static func symbol<T>(named name: String, as type: T.Type) -> T? {
        guard let frameworkHandle,
              let symbol = dlsym(frameworkHandle, name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }
}

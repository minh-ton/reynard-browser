//
//  ReynardViewController.swift
//  Reynard
//
//  Created by Minh Ton on 1/2/26.
//


import UIKit
import GeckoWrapper

class ReynardViewController: UIViewController {
    private var geckoView: GeckoView!
    private var geckoSession: GeckoSession!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        // Not sure why Gecko just acting weird
        // so I have to use auto-layout here.
        geckoView = GeckoView(frame: .zero)
        geckoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(geckoView)
        
        NSLayoutConstraint.activate([
            geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            geckoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            geckoView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        geckoSession = GeckoSession()
        geckoSession.open()
        
        geckoView.session = geckoSession
        geckoSession.setActive(true)
        
        // This cannot be loaded yet, still under investigation
        geckoSession.load("data:text/html,<html><body style='background: red; height: 100vh; margin: 0;'><h1>HELLO WORLD</h1></body></html>")
    }
}

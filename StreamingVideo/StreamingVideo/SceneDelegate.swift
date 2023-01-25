//
//  SceneDelegate.swift
//  StreamingVideo
//
//  Created by Don Clore on 1/24/23.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else {
            return
        }
        
        let vc = ViewController()
        let win = UIWindow(windowScene: windowScene)
        window = win
        win.rootViewController = vc
        win.makeKeyAndVisible()
    }
}


//
//  AppDelegate.swift
//  Nabto Edge Video
//
//  Created by Nabto on 30/01/2022.
//  Copyright © 2022 Nabto. All rights reserved.
//

import UIKit
import NotificationBannerSwift
import IQKeyboardManagerSwift
import OSLog
import Amplify
import AWSCognitoAuthPlugin
import NabtoEdgeClientWebRTC

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var starting = true
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NabtoAppDelegate")

    let configuration =
"""
    {
      "auth": {
        "plugins": {
          "awsCognitoAuthPlugin": {
            "IdentityManager": {
              "Default": {}
            },
            "CognitoUserPool": {
              "Default": {
                "PoolId": "\(ConfigService.shared.COGNITO_POOL_ID)",
                "AppClientId": "\(ConfigService.shared.COGNITO_APP_CLIENT_ID)",
                "Region": "\(ConfigService.shared.COGNITO_REGION)"
              }
            },
            "Auth": {
              "Default": {
                "authenticationFlowType": "USER_SRP_AUTH",
                "OAuth": {
                  "WebDomain": "\(ConfigService.shared.COGNITO_WEB_DOMAIN)",
                  "AppClientId": "\(ConfigService.shared.COGNITO_APP_CLIENT_ID)",
                  "SignInRedirectURI": "myapp://example",
                  "SignOutRedirectURI": "myapp://example",
                  "Scopes": [
                    "email",
                    "openid",
                    "profile",
                    "aws.cognito.signin.user.admin"
                  ]
                }
              }
            }
          }
        }
      }
    }
"""
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        IQKeyboardManager.shared.enable = true
        let data = configuration.data(using: .utf8)!
        let jsonDecoder = JSONDecoder()
        EdgeWebRTC.setLogLevel(.verbose)
        
        do {
            let conf = try jsonDecoder.decode(AmplifyConfiguration.self, from: data)
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.configure(conf)
            print("Amplify configured")
        } catch {
            print("An error occurred setting up Amplify: \(error)")
        }
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        EdgeConnectionManager.shared.reset()
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}


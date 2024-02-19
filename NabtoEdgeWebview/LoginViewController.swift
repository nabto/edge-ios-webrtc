//
//  LoginViewController.swift
//  NabtoEdgeWebview
//
//  Created by Ahmad Saleh on 30/10/2023.
//  Copyright © 2023 Nabto. All rights reserved.
//

import UIKit
import Amplify
import Authenticator
import AWSCognitoAuthPlugin
import SwiftUI

class LoginViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        Task {
            if (await self.isSignedIn()) {
                print("Already signed in")
                navigateToOverview()
                return
            }
            
            do {
            } catch let error as AuthError {
                print("Sign in failed: \(error)")
            } catch {
                print("Unexpected error in WebUI sign in: \(error)")
            }
        }
    }
   
    func isSignedIn() async -> Bool {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            return session.isSignedIn
        } catch let error as AuthError {
            print("Fetch session failed with error \(error)")
        } catch {
            print("Unexpected error: \(error)")
        }
        return false
    }

    // MARK: - Navigation
    
    private func navigateToOverview() {
        self.performSegue(withIdentifier: "LoginToOverview", sender: nil)
    }
}

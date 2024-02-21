//
//  LoginViewController.swift
//  NabtoEdgeWebview
//
//  Created by Ahmad Saleh on 30/10/2023.
//  Copyright © 2023 Nabto. All rights reserved.
//

import UIKit
import Amplify
import NotificationBannerSwift

class LoginViewController: UIViewController {

    @IBOutlet weak var usernameField: UITextField!
    @IBOutlet weak var passwordField: UITextField!
    @IBOutlet weak var signinButton: UIButton!
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    
    @IBAction func signinTapped(_ sender: Any) {
        self.spinner.startAnimating()
        Task {
            await signIn(username: self.usernameField.text!,
                         password: self.passwordField.text!)
            DispatchQueue.main.async {
                 self.spinner.stopAnimating()
             }
        }
    }
        
    func signIn(username: String, password: String) async {
        do {
            let signInResult = try await Amplify.Auth.signIn(
                username: username,
                password: password
                )
            if signInResult.isSignedIn {
                print("Sign in succeeded")
                navigateToOverview()
            }
        } catch let error as AuthError {
            DispatchQueue.main.async {
                let banner = GrowingNotificationBanner(title: "Sign in error",  subtitle: error.errorDescription, style: .danger)
                banner.show()
                print("Sign in failed - \(error)")
            }
        } catch {
            let banner = GrowingNotificationBanner(title: "Unexpected error",  subtitle: "\(error)", style: .danger)
            banner.show()
            print("Unexpected error: \(error)")
        }
        
    }
    
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
        }
    }
   
    func isSignedIn() async -> Bool {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            return session.isSignedIn
        } catch let error as AuthError {
            let banner = GrowingNotificationBanner(title: "Session resume error",  subtitle: error.errorDescription, style: .danger)
            banner.show()
            print("Fetch session failed with error \(error)")
        } catch {
            let banner = GrowingNotificationBanner(title: "Unexpected error",  subtitle: "\(error)", style: .danger)
            banner.show()
            print("Unexpected error: \(error)")
        }
        return false
    }

    // MARK: - Navigation
    
    private func navigateToOverview() {
        self.performSegue(withIdentifier: "LoginToOverview", sender: nil)
    }
}

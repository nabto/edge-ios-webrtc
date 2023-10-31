//
//  AuthService.swift
//  NabtoEdgeWebview
//
//  Created by Ahmad Saleh on 30/10/2023.
//  Copyright © 2023 Nabto. All rights reserved.
//

import Foundation
import Amplify
import AWSPluginsCore

struct AuthTokens {
    var accessToken: String
    var refreshToken: String
}

struct NabtoToken: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let issuedTokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case issuedTokenType = "issued_token_type"
    }
}

class AuthService {
    internal static let shared = AuthService()
    
    private let jsonDecoder = JSONDecoder()
    
    func getTokens() async -> AuthTokens? {
        let session = try? await Amplify.Auth.fetchAuthSession()
        
        if let session = session {
            if session.isSignedIn {
                if let tokenProvider = session as? AuthCognitoTokensProvider {
                    if let token = try? tokenProvider.getCognitoTokens().get() {
                        return AuthTokens(accessToken: token.accessToken , refreshToken: token.refreshToken)
                    }
                }
            }
        }
        
        return nil
    }
    
    func getStsTokenForDevice(_ device: Bookmark) async -> NabtoToken? {
        let productId = device.productId
        let deviceId = device.deviceId
        let tokens = await getTokens()
        
        let serviceUrl = ConfigService.shared.CLOUD_SERVICE_URL
        let requestUrl = "\(serviceUrl)/sts/token"
        
        let requestHeaders: [String: String] = [
            "Content-Type": "application/x-www-form-urlencoded"
        ]
        
        var requestComponents = URLComponents()
        requestComponents.queryItems = [
            URLQueryItem(name: "client_id", value: ConfigService.shared.COGNITO_APP_CLIENT_ID),
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:token-exchange"),
            URLQueryItem(name: "subject_token", value: tokens?.accessToken ?? ""),
            URLQueryItem(name: "subject_token_type", value: "urn:ietf:params:oauth:token-type:access_token"),
            URLQueryItem(name: "resource", value: "nabto://device?productId=\(productId)%26deviceId=\(deviceId)")
        ]
        
        var request = URLRequest(url: URL(string: requestUrl)!)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = requestHeaders
        request.httpBody = requestComponents.query?.data(using: .utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let stsToken = try? jsonDecoder.decode(NabtoToken.self, from: data)
            if stsToken == nil {
                print("Decoding STS token failed: \(String(data: data, encoding: .utf8)!)")
            }
            return stsToken
        } catch {
            print("Failed to exchange tokens with STS service: \(error)")
            return nil
        }
    }
}

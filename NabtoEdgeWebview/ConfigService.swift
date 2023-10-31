//
//  ConfigService.swift
//  NabtoEdgeWebview
//
//  Created by Ahmad Saleh on 30/10/2023.
//  Copyright © 2023 Nabto. All rights reserved.
//

import Foundation

class ConfigService {
    internal static let shared = ConfigService()
    
    /** Our cloud service that we get/post info from/to */
    let CLOUD_SERVICE_URL = "https://smarthome.as.dev.nabto.com"

    /** Cognito userpool config */
    let COGNITO_REGION = "eu-west-1"
    let COGNITO_POOL_ID = "eu-west-1_FAs7WiRvc"
    let COGNITO_APP_CLIENT_ID = "5r8seqd0f5gfk6thfpdvjic6o0"
    let COGNITO_WEB_DOMAIN = "as-oauth-example.auth.eu-west-1.amazoncognito.com"
    
    private init() {}
}

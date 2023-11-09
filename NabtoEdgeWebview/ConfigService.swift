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
    let CLOUD_SERVICE_URL = "https://api.as.dev.nabto.com"

    /** Cognito userpool config */
    let COGNITO_REGION = "eu-west-1"
    let COGNITO_POOL_ID = "eu-west-1_88DX8rDJT"
    let COGNITO_APP_CLIENT_ID = "5c029pghuvrq64lbi7kr7pfsnf"
    let COGNITO_WEB_DOMAIN = "as-oauth-example.auth.eu-west-1.amazoncognito.com"
    
    private init() {}
}

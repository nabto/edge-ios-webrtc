//
//  EdgeDeviceViewController.swift
//  Nabto Edge Video
//
//  Created by Nabto on 03/02/2022.
//  Copyright © 2022 Nabto. All rights reserved.
//

import UIKit
import NotificationBannerSwift
import CBORCoding
import NabtoEdgeClient
import NabtoEdgeIamUtil
import OSLog
import WebKit
import WebRTC

class EdgeDeviceViewController: DeviceDetailsViewController, WKUIDelegate {
    private let cborEncoder: CBOREncoder = CBOREncoder()
    private let rtc = NabtoRTC()
    private var renderer: RTCMTLVideoView!

    @IBOutlet weak var settingsButton       : UIButton!
    @IBOutlet weak var connectingView       : UIView!
    @IBOutlet weak var spinner              : UIActivityIndicatorView!
    
    @IBOutlet weak var videoScreenView : UIView!
    
    @IBOutlet weak var deviceIdLabel         : UILabel!
    @IBOutlet weak var appNameAndVersionLabel: UILabel!
    @IBOutlet weak var usernameLabel         : UILabel!
    @IBOutlet weak var displayNameLabel      : UILabel!
    @IBOutlet weak var roleLabel             : UILabel!

    var offline         = false
    var showReconnectedMessage: Bool = false
    var refreshTimer: Timer?
    var busyTimer: Timer?
    var banner: GrowingNotificationBanner? = nil
    
    var busy = false {
        didSet {
            self.busyTimer?.invalidate()
            if busy {
                DispatchQueue.main.async {
                    self.busyTimer = Timer.scheduledTimer(timeInterval: 0.8, target: self, selector: #selector(self.showSpinner), userInfo: nil, repeats: false)
                }
            } else {
                self.hideSpinner()
            }
        }
    }

    private func showConnectSuccessIfNecessary() {
        if (self.showReconnectedMessage) {
            DispatchQueue.main.async {
                self.banner?.dismiss()
                self.banner = GrowingNotificationBanner(title: "Connected", subtitle: "Connection re-established!", style: .success)
                self.banner!.show()
                self.showReconnectedMessage = false
            }
        }
    }

    func handleDeviceError(_ error: Error) {
        EdgeConnectionManager.shared.removeConnection(self.device)
        if let error = error as? NabtoEdgeClientError {
            handleApiError(error: error)
        } else if let error = error as? IamError {
            if case .API_ERROR(let cause) = error {
                handleApiError(error: cause)
            } else {
                NSLog("Pairing error, really? \(error)")
            }
        } else {
            self.showDeviceErrorMsg("\(error)")
        }
    }

    private func handleApiError(error: NabtoEdgeClientError) {
        switch error {
        case .NO_CHANNELS:
            self.showDeviceErrorMsg("Device offline - please make sure you and the target device both have a working network connection")
            break
        case .TIMEOUT:
            self.showDeviceErrorMsg("The operation timed out - was the connection lost?")
            break
        case .STOPPED:
            // ignore - connection/client will be restarted at next connect attempt
            break
        default:
            self.showDeviceErrorMsg("An error occurred: \(error)")
        }
    }

    func showDeviceErrorMsg(_ msg: String) {
        DispatchQueue.main.async {
            self.banner?.dismiss()
            self.banner = GrowingNotificationBanner(title: "Communication Error", subtitle: msg, style: .danger)
            self.banner!.show()
        }
    }

    @objc func showSpinner() {
        DispatchQueue.main.async {
            if (self.busy) {
                self.connectingView.isHidden = false
                self.spinner.startAnimating()
            }
        }
    }

    func hideSpinner() {
        DispatchQueue.main.async {
            self.connectingView.isHidden = true
            self.spinner.stopAnimating()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.busy = true
        
        renderer = RTCMTLVideoView(frame: self.videoScreenView.frame)
        renderer.videoContentMode = .scaleAspectFit
        
        embedView(renderer, into: self.videoScreenView)
        self.busy = false
        
        Task {
            rtc.start(bookmark: self.device, renderer: renderer)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default
                .removeObserver(self, name: NSNotification.Name(EdgeConnectionManager.eventNameConnectionClosed), object: nil)
        NotificationCenter.default
                .removeObserver(self, name: NSNotification.Name(EdgeConnectionManager.eventNameNoNetwork), object: nil)
        NotificationCenter.default
                .removeObserver(self, name: NSNotification.Name(EdgeConnectionManager.eventNameNetworkAvailable), object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(connectionClosed),
                       name: NSNotification.Name (EdgeConnectionManager.eventNameConnectionClosed),
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(networkLost),
                       name: NSNotification.Name (EdgeConnectionManager.eventNameNoNetwork),
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(networkAvailable),
                       name: NSNotification.Name (EdgeConnectionManager.eventNameNetworkAvailable),
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(appMovedToBackground),
                       name: UIApplication.willResignActiveNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(appWillMoveToForeground),
                       name: UIApplication.didBecomeActiveNotification,
                       object: nil)
    }
    
    private func embedView(_ view: UIView, into container: UIView) {
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:|[view]|",
            options: [],
            metrics: nil,
            views: ["view": view]
        ))
        
        container.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "V:|[view]|",
            options: [],
            metrics: nil,
            views: ["view": view]
        ))
        
        container.layoutIfNeeded()
    }

    // MARK: - Reachability callbacks
    @objc func appMovedToBackground() {
        Task {
            print("Backgrounded")
            try? rtc.stop()
        }
    }
    
    @objc func appWillMoveToForeground() {
        Task {
            print("Foregrounded")
            rtc.start(bookmark: self.device, renderer: renderer)
        }
    }

    @objc func connectionClosed(_ notification: Notification) {
        if notification.object is Bookmark {
            DispatchQueue.main.async {
                self.showDeviceErrorMsg("Connection closed - refresh to try to reconnect")
                self.showReconnectedMessage = true
            }
        }
    }

    @objc func networkLost(_ notification: Notification) {
        DispatchQueue.main.async {
            let banner = GrowingNotificationBanner(title: "Network connection lost", subtitle: "Please try again later", style: .warning)
            banner.show()
        }
    }

    @objc func networkAvailable(_ notification: Notification) {
        DispatchQueue.main.async {
            let banner = GrowingNotificationBanner(title: "Network up again!", style: .success)
            banner.show()
        }
    }
}

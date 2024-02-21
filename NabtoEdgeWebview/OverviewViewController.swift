//
//  ViewController.swift
//  Nabto Edge Video
//
//  Created by Nabto on 30/01/2022.
//  Copyright © 2022 Nabto. All rights reserved.
//

import UIKit
import NabtoEdgeIamUtil
import NabtoEdgeClient
import NotificationBannerSwift
import Amplify
import AWSPluginsCore

struct CloudDevice: Codable {
    var id: String
    var owner: String
    var name: String
    var nabtoProductId: String
    var nabtoDeviceId: String
    var nabtoSct: String?
    var fingerprint: String
}

class OverviewViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var table: UITableView!

    var devices: [DeviceRowModel] = []

    var waiting  = true
    var errorBanner: GrowingNotificationBanner? = nil

    let buttonBarSpinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        return spinner
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        table.contentInset.top += 16
        self.navigationItem.leftBarButtonItems?.append(UIBarButtonItem(customView: self.buttonBarSpinner))
        do {
            try BookmarkManager.shared.loadBookmarks()
        } catch {
            let banner = GrowingNotificationBanner(title: "Error", subtitle: "Could not load bookmarks: \(error)", style: .danger)
            banner.show()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default
                .addObserver(self,
                        selector: #selector(connectionClosed),
                        name: NSNotification.Name (EdgeConnectionManager.eventNameConnectionClosed),
                        object: nil)
        NotificationCenter.default
                .addObserver(self,
                        selector: #selector(networkLost),
                        name: NSNotification.Name (EdgeConnectionManager.eventNameNoNetwork),
                        object: nil)
        NotificationCenter.default
                .addObserver(self,
                        selector: #selector(networkAvailable),
                        name: NSNotification.Name (EdgeConnectionManager.eventNameNetworkAvailable),
                        object: nil)
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

    @objc func connectionClosed(_ notification: Notification) {
        if let bookmark = notification.object as? Bookmark {
            for d in self.devices {
                if (d.bookmark == bookmark) {
                    d.isOnline = false
                    DispatchQueue.main.async {
                        self.table.reloadData()
                    }
                    return
                }
            }
        }
    }

    @objc func networkLost(_ notification: Notification) {
        for d in self.devices {
            d.isOnline = false
        }
        DispatchQueue.main.async {
            self.table.reloadData()
            let banner = GrowingNotificationBanner(title: "Network connection lost", subtitle: "Please try again later", style: .warning)
            banner.show()
        }
    }

    @objc func networkAvailable(_ notification: Notification) {
        DispatchQueue.main.async {
            let banner = GrowingNotificationBanner(title: "Network up again!", style: .success)
            banner.show()
            self.doRefresh()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if (ProfileTools.getSavedPrivateKey() != nil) {
            self.doRefresh()
        } else {
            DispatchQueue.global().async {
                self.createProfile()
                DispatchQueue.main.async {
                    self.doRefresh()
                }
            }
        }
    }

    func createProfile() {
        do {
            let key = try EdgeConnectionManager.shared.client.createPrivateKey()
            let username = UIDevice.current.name
            let simplifiedUsername = ProfileTools.convertToValidUsername(input: username)
            ProfileTools.saveProfile(username: simplifiedUsername, privateKey: key, displayName: username)
        } catch {
            let banner = NotificationBanner(title: "Error", subtitle: "Could not create private key: \(error)", style: .danger)
            banner.show()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    func profileCreated() {
        self.populateDeviceOverview()
    }

    func populateDeviceOverview() {
        self.devices = []
        if (BookmarkManager.shared.deviceBookmarks.isEmpty) {
            // show big spinner in table
            self.waiting = true
        } else {
            // show spinner above table
            self.buttonBarSpinner.startAnimating()
        }
        self.addDevicesFromBookmarks()
        self.addDevicesFromCloudService()
        DispatchQueue.global().async {
            self.getDetailsForDevices()
            DispatchQueue.main.async {
                self.table.reloadData()
                self.buttonBarSpinner.stopAnimating()
                self.waiting = false
            }
        }
    }
    
    // @TODO: This all seems pretty spaghetti at the moment, but we're just trying to get something in the air first.
    func addDevicesFromCloudService() {
        Task {
            let tokens = await AuthService.shared.getTokens()
            let accessToken = tokens?.accessToken ?? ""
            
            let url = URL(string: "\(ConfigService.shared.CLOUD_SERVICE_URL)/webrtc/devices")!
            var req = URLRequest(url: url)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                print("HTTP Request succeeded!")
                
                if let devs = try? JSONDecoder().decode([CloudDevice].self, from: data) {
                    let bookmarks = devs.map {
                        Bookmark(deviceId: $0.nabtoDeviceId, productId: $0.nabtoProductId, sct: $0.nabtoSct, name: $0.name)
                    }
                    for b in bookmarks {
                        self.devices.append(DeviceRowModel(bookmark: b))
                    }
                    self.table.reloadData()
                } else {
                    print("JSON decode of cloud devices failed!")
                }
                
            } catch {
                print("HTTP request failed: \(error)")
            }
        }
    }

    func addDevicesFromBookmarks() {
        let bookmarks = BookmarkManager.shared.deviceBookmarks
        self.devices = []
        for b in bookmarks {
            self.devices.append(DeviceRowModel(bookmark: b))
        }
        
        
        self.table.reloadData()
    }

    func getDetailsForDevices() {
        let group = DispatchGroup()
        for device in self.devices {
            group.enter()
            Task {
                do {
                    try await device.populateWithDetails()
                } catch {
                    print("An error occurred when retrieving device information for \(device.bookmark): \(error)")
                }
                DispatchQueue.main.sync {
                    self.table.reloadData()
                }
                group.leave()
            }
        }
        group.wait()
    }

    @IBAction func refresh(_ sender: Any) {
        EdgeConnectionManager.shared.reset()
        self.errorBanner?.dismiss()
        self.doRefresh()
    }

    func doRefresh() {
        self.devices = []
        self.table.reloadData()
        self.populateDeviceOverview()
    }
    
    //MARK: - Handle device selection
    
    func handleSelection(device: DeviceRowModel) {
        self.errorBanner?.dismiss()
        if (device.isOnline ?? false) {
            self.handleOnlineDevice(device)
        } else {
            self.handleOfflineDevice(device)
        }
    }

    private func handleOfflineDevice(_ device: DeviceRowModel) {
        // expect timeout, so indicate activity in the UI
        self.buttonBarSpinner.startAnimating()
        Task {
            defer {
                Task { @MainActor in
                    self.buttonBarSpinner.stopAnimating()
                }
            }
            do {
                let updatedDevice = DeviceRowModel(bookmark: device.bookmark)
                try await updatedDevice.populateWithDetails()
                if (updatedDevice.isOnline ?? false) {
                    self.handleOnlineDevice(updatedDevice)
                } else {
                    if let err = device.error {
                        self.handleError(msg: "Cannot connect to '\(device.bookmark.name)': \(err)")
                    } else {
                        self.handleError(msg: "Device '\(device.bookmark.name)' is offline")
                    }
                }
            } catch {
                self.handleError(msg: "\(error)")
                return
            }
        }
    }

    func handleOnlineDevice(_ device: DeviceRowModel) {
        DispatchQueue.main.async {
            if (device.isPaired) {
                self.handlePaired(device: device.bookmark)
            } else {
                self.handleUnpaired(device: device.bookmark)
            }
        }
    }
    
    func handlePaired(device: Bookmark) {
        performSegue(withIdentifier: "toDeviceView", sender: device)
    }
    
    func handleUnpaired(device: Bookmark) {
        performSegue(withIdentifier: "toPairing", sender: device)
    }

    func handleError(msg: String) {
        DispatchQueue.main.async {
            self.errorBanner = GrowingNotificationBanner(title: "Error", subtitle: msg, style: .danger)
            self.errorBanner?.show()
        }
    }

    //MARK: - UITableView methods
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (indexPath.section == 0) {
            if (self.devices.count > 0) {
                let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceCell", for: indexPath) as! DeviceCell
                let device = devices[indexPath.row]
                cell.configure(device: device)
                if (device.isOnline != nil) {
                    cell.statusIcon.isHidden = false
                    if (device.isOnline!) {
                        if (device.isPaired) {
                            cell.statusIcon.image = UIImage(named: "checkSmall")?.withRenderingMode(.alwaysTemplate)
//                            cell.statusIcon.tintColor = UIColor(named: "NabtoColor")
                            cell.statusIcon.tintColor = .systemGreen
                        } else {
                            cell.statusIcon.image = UIImage(named: "open")?.withRenderingMode(.alwaysTemplate)
//                            cell.statusIcon.tintColor = UIColor(named: "NabtoColor")
                            cell.statusIcon.tintColor = .systemGreen
                        }
                    } else {
                        cell.statusIcon.image = UIImage(named: "alert")?.withRenderingMode(.alwaysTemplate)
                        cell.statusIcon.tintColor = .systemRed
                    }
                } else {
                    cell.statusIcon.isHidden = true
                }
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: "NoDevicesCell", for: indexPath) as! NoDevicesCell
                cell.configure(waiting: waiting)
                return cell
            }
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "OverviewButtonCell", for: indexPath) as! OverviewButtonCell
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0 && self.devices.count > 0 else { return }
        self.handleSelection(device: self.devices[indexPath.row])
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? max(devices.count, 1) : 1
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return indexPath.section == 0 ? 72 : 110
    }

    
    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let device = sender as? Bookmark else { return }
        if let destination = segue.destination as? PairingViewController {
            destination.device = device
        } else if let destination = segue.destination as? DeviceDetailsViewController {
            destination.device = device
        }
    }
}


//
//  NabtoRTCComponent.swift
//  NabtoEdgeWebview
//
//  Created by Ahmad Saleh on 01/11/2023.
//  Copyright © 2023 Nabto. All rights reserved.
//

import Foundation
import WebRTC
import NabtoEdgeClient
import CBORCoding
import AsyncAlgorithms

fileprivate struct RTCInfo: Codable {
    let fileStreamPort: UInt32
    let signalingStreamPort: UInt32
    
    enum CodingKeys: String, CodingKey {
        case fileStreamPort = "FileStreamPort"
        case signalingStreamPort = "SignalingStreamPort"
    }
}

fileprivate struct TurnServer: Codable {
    let hostname: String
    let port: Int
    let username: String
    let password: String
}

fileprivate struct IceCandidate: Codable {
    let candidate: String
    let sdpMid: String
    let sdpMLineIndex: Int?
}

fileprivate struct SignalMessageMetadataTrack: Codable {
    let mid: String
    let trackId: String
}

fileprivate struct SignalMessageMetadata: Codable {
    let tracks: [SignalMessageMetadataTrack]
    let noTrickle: Bool
}

fileprivate enum SignalMessageType: Int, Codable {
    case offer = 0
    case answer = 1
    case iceCandidate = 2
    case turnRequest = 3
    case turnResponse = 4
}

fileprivate struct SignalMessage: Codable {
    let type: SignalMessageType
    var data: String? = nil
    var servers: [TurnServer]? = nil
    var metadata: SignalMessageMetadata? = nil
}

fileprivate struct SDP: Codable {
    let sdp: String
    let type: String
}

final class NabtoRTC: NSObject {
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    // Misc
    private let cborDecoder = CBORDecoder()
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    
    // Nabto
    private var deviceStream: NabtoEdgeClient.Stream!
    private let messageChannel = AsyncChannel<SignalMessage>()
    
    // WebRTC
    private var peerConnection: RTCPeerConnection!
    private let mandatoryConstraints = [
        kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
        //kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue
    ]
    
    private var remoteVideoTrack: RTCVideoTrack?
    
    deinit {
        do {
            peerConnection.close()
            try deviceStream.close()
        } catch {
            print("NabtoRTC: error in deinitialization \(error)")
        }
    }
    
    func connectToDevice(bookmark: Bookmark, renderer: RTCVideoRenderer) {
        let maybeConn = try? EdgeConnectionManager.shared.getConnection(bookmark)
        if let conn = maybeConn {
            connectInternal(conn: conn, renderer: renderer)
        } else {
            print("Could not get connection for bookmark \(bookmark)")
        }
    }
    
    private func createOffer() async -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
        return await withCheckedContinuation { continuation in
            self.peerConnection.offer(for: constraints) { (sdp, error) in
                guard let sdp = sdp else { return }
                continuation.resume(returning: sdp)
            }
        }
    }
    
    private func startSignalingStream(_ conn: Connection) {
        do {
            let coap = try conn.createCoapRequest(method: "GET", path: "/webrtc/info")
            let coapResult = try coap.execute()
            
            if coapResult.status != 205 {
                print("Unexpected /webrtc/info return code \(coapResult.status)")
            }
            
            let rtcInfo = try? cborDecoder.decode(RTCInfo.self, from: coapResult.payload)
            if let rtcInfo = rtcInfo {
                self.deviceStream = try conn.createStream()
                try self.deviceStream.open(streamPort: rtcInfo.signalingStreamPort)
            } else {
                print("Could not decode coap payload")
            }
        } catch {
            // @TODO: We will need better error handling later.
            fatalError("Failed to start signaling stream: \(error)")
        }
    }
    
    private func startPeerConnection(_ config: RTCConfiguration, _ renderer: RTCVideoRenderer) {
        let streamId = "stream"
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peerConnection = NabtoRTC.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            fatalError("Failed to create RTCPeerConnection")
        }
        
        self.peerConnection = peerConnection
        
        // video track
        let videoSource = NabtoRTC.factory.videoSource()
        let videoTrack = NabtoRTC.factory.videoTrack(with: videoSource, trackId: "video0")
        self.peerConnection.add(videoTrack, streamIds: [streamId])
        self.remoteVideoTrack = self.peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
        self.remoteVideoTrack?.add(renderer)
    }
    
    private func connectInternal(conn: Connection, renderer: RTCVideoRenderer) {
        startSignalingStream(conn)
        
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.nabto.net"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        Task {
            for await msg in messageChannel {
                do {
                    try await writeSignalMessage(deviceStream, msg: msg)
                } catch {
                    print("Error in consumer task \(error)")
                }
            }
        }
        
        Task {
            do {
                //try await writeSignalMessage(deviceStream, msg: SignalMessage(type: .turnRequest))
                await messageChannel.send(SignalMessage(type: .turnRequest))
                
                while true {
                    let msg = try await readSignalMessage(deviceStream)
                    print("Received msg of type: \(msg.type)")
                    switch msg.type {
                    case .answer:
                        let answer = try jsonDecoder.decode(SDP.self, from: msg.data!.data(using: .utf8)!)
                        let sdp = RTCSessionDescription(type: RTCSdpType.answer, sdp: answer.sdp)
                        try await self.peerConnection.setRemoteDescription(sdp)
                        break
                        
                    case .iceCandidate:
                        let cand = try jsonDecoder.decode(IceCandidate.self, from: msg.data!.data(using: .utf8)!)
                        try await self.peerConnection.add(RTCIceCandidate(
                            sdp: cand.candidate,
                            sdpMLineIndex: 0,
                            sdpMid: cand.sdpMid
                        ))
                        break
                        
                    case .turnResponse:
                        guard let turnServers = msg.servers else {
                            // @TODO: Show an error to the user
                            break
                        }
                        
                        for server in turnServers {
                            let turn = RTCIceServer(
                                urlStrings: [server.hostname],
                                username: server.username,
                                credential: server.password
                            )
                            config.iceServers.append(turn)
                        }
                        
                        self.startPeerConnection(config, renderer)
                        
                        let offer = await self.createOffer()
                        let msg = SignalMessage(
                            type: .offer,
                            data: offer.toJSON(),
                            metadata: SignalMessageMetadata(
                                tracks: [SignalMessageMetadataTrack(mid: "0", trackId: "frontdoor-video")],
                                noTrickle: false
                            )
                        )
                        
                        //try await writeSignalMessage(deviceStream, msg: msg)
                        await messageChannel.send(msg)
                        try await peerConnection.setLocalDescription(offer)
                        break
                        
                    default:
                        print("Unexpected signaling message of type: \(msg.type)")
                        break
                    }
                }
            } catch {
                // @TODO: Better error handling for the msg loop
                print("MsgLoop failed: \(error)")
            }
        }
    }
}

extension RTCSessionDescription {
    func toJSON() -> String {
        let strType: String // Define the type of the variable
        switch self.type {
        case .answer: strType = "answer"
        case .offer: strType = "offer"
        case .prAnswer: strType = "prAnswer"
        case .rollback: strType = "rollback"
        }

        let obj: [String: Any] = [
            "type": strType,
            "sdp": self.sdp
        ]
        
        let maybeJsonData = try? JSONSerialization.data(withJSONObject: obj)
        guard let jsonData = maybeJsonData else {
            fatalError("Invalid SDP, could not convert to JSON.")
        }
        
        let maybeResult = String(data: jsonData, encoding: .utf8)
        guard let result = maybeResult else {
            fatalError("Invalid SDP, could not convert to JSON.")
        }
        
        return result
    }
}


extension RTCIceCandidate {
    func toJSON() -> String {
        let obj: [String: Any] = [
            "candidate": self.sdp,
            "sdpMLineIndex": self.sdpMLineIndex,
            "sdpMid": self.sdpMid ?? ""
        ]
        
        let maybeJsonData = try? JSONSerialization.data(withJSONObject: obj)
        guard let jsonData = maybeJsonData else {
            fatalError("Invalid SDP, could not convert to JSON.")
        }
        
        let maybeResult = String(data: jsonData, encoding: .utf8)
        guard let result = maybeResult else {
            fatalError("Invalid SDP, could not convert to JSON.")
        }
        
        return result
    }
}

// MARK: RTCPeerConnectionDelegate implementation
extension NabtoRTC: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("NabtoRTC: Signaling state changed to \((try? stateChanged.description()) ?? "invalid RTCSignalingState")")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("NabtoRTC: New RTCMediaStream \(stream.streamId) added")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("NabtoRTC: RTCMediaStream \(stream.streamId) removed")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("NabtoRTC: Peer connection should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("NabtoRTC: ICE connection state changed to: \((try? newState.description()) ?? "invalid RTCIceConnectionState")")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("NabtoRTC: ICE gathering state changed to: \((try? newState.description()) ?? "invalid RTCIceGatheringState")")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("NabtoRTC: New ICE candidate generated: \(candidate.sdp)")
        Task {
            await messageChannel.send(SignalMessage(
                type: .iceCandidate,
                data: candidate.toJSON()
            ))
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("NabtoRTC: ICE candidate removed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen candidate: RTCDataChannel) {
        print("NabtoRTC: Data channel opened")
    }
}

// MARK: Nabto device signaling
extension NabtoRTC {
    private func readSignalMessage(_ stream: NabtoEdgeClient.Stream) async throws -> SignalMessage {
        let lenData = try await withCheckedThrowingContinuation { continuation in
            deviceStream.readAllAsync(length: 4) { err, data in
                if err == .OK {
                    continuation.resume(returning: data!)
                } else {
                    continuation.resume(throwing: err)
                }
            }
        }
        
        let len: Int32 = lenData.withUnsafeBytes { $0.load(as: Int32.self)}
        
        let data = try await withCheckedThrowingContinuation { continuation in
            deviceStream.readAllAsync(length: Int(len)) { err, data in
                if err == .OK {
                    continuation.resume(returning: data!)
                } else {
                    continuation.resume(throwing: err)
                }
            }
        }
        
        return try jsonDecoder.decode(SignalMessage.self, from: data)
    }
    
    private func writeSignalMessage(_ stream: NabtoEdgeClient.Stream, msg: SignalMessage) async throws {
        let encoded = try jsonEncoder.encode(msg)
        let len = UInt32(encoded.count)
        
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: len.littleEndian, Array.init))
        data.append(encoded)
        
        try await withCheckedThrowingContinuation { continuation in
            stream.writeAsync(data: data) { err in
                if err == .OK {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: err)
                }
            }
        }
    }
}

extension RTCSignalingState {
    public func description() throws -> String {
        switch self {
        case .closed:
            return "closed"
        case .stable:
            return "stable"
        case .haveLocalOffer:
            return "haveLocalOffer"
        case .haveLocalPrAnswer:
            return "haveLocalPrAnswer"
        case .haveRemoteOffer:
            return "haveRemoteOffer"
        case .haveRemotePrAnswer:
            return "haveRemotePrAnswer"
        @unknown default:
           throw NabtoEdgeClientError.INVALID_ARGUMENT
        }
    }
}

extension RTCIceGatheringState {
    public func description() throws -> String {
        switch self {
        case .complete:
            return "complete"
        case .new:
            return "new"
        case .gathering:
            return "gathering"
        @unknown default:
           throw NabtoEdgeClientError.INVALID_ARGUMENT
        }
    }
}

extension RTCIceConnectionState {
    public func description() throws -> String {
        switch self {
        case .new:
             return "new"
         case .checking:
             return "checking"
         case .connected:
             return "connected"
         case .completed:
             return "completed"
         case .failed:
             return "failed"
         case .disconnected:
             return "disconnected"
         case .closed:
             return "closed"
         @unknown default:
            throw NabtoEdgeClientError.INVALID_ARGUMENT
        }
    }
}


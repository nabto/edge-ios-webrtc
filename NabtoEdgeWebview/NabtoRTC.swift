//
//  WebRTCClient.swift
//  NabtoEdgeWebview
//
//  Created by Ahmad Saleh on 26/10/2023.
//  Copyright © 2023 Nabto. All rights reserved.
//

import Foundation
import WebRTC
import NabtoEdgeClient
import CBORCoding

fileprivate struct RTCInfo: Codable {
    let fileStreamPort: UInt32
    let signalingStreamPort: UInt32
    
    enum CodingKeys: String, CodingKey {
        case fileStreamPort = "FileStreamPort"
        case signalingStreamPort = "SignalingStreamPort"
    }
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
    let data: String?
    let metadata: SignalMessageMetadata?
}

fileprivate struct SDP: Codable {
    let sdp: String
    let type: String
}

final class NabtoRTC: NSObject {
    static let shared = NabtoRTC()
    
    private static let factory: RTCPeerConnectionFactory = {
        RTCSetMinDebugLogLevel(RTCLoggingSeverity.info);
        RTCEnableMetrics()
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
    
    // WebRTC
    private var peerConnection: RTCPeerConnection!
    private let mandatoryConstraints = [
        kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
        //kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue
    ]
    
    private var remoteVideoTrack: RTCVideoTrack?
    
    override private init() {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.nabto.net"])]
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        
        super.init()
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peerConnection = NabtoRTC.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            fatalError("Failed to create RTCPeerConnection")
        }
        
        self.peerConnection = peerConnection
    }
    
    func createOffer() async -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
        return await withCheckedContinuation { continuation in
            self.peerConnection.offer(for: constraints) { (sdp, error) in
                guard let sdp = sdp else { return }
                continuation.resume(returning: sdp)
            }
        }
    }
    
    func renderRemoteVideo(to renderer: RTCVideoRenderer) {
        self.remoteVideoTrack?.add(renderer)
    }
    
    func connectToDevice(bookmark: Bookmark, renderer: RTCVideoRenderer) {
        let maybeConn = try? EdgeConnectionManager.shared.getConnection(bookmark)
        if let conn = maybeConn {
            connectInternal(conn: conn, renderer: renderer)
        } else {
            print("Could not get connection for bookmark \(bookmark)")
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
    
    private func connectInternal(conn: Connection, renderer: RTCVideoRenderer) {
        startSignalingStream(conn)
        let streamId = "stream"
        
        // audio track
        /*
        let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = NabtoRTC.factory.audioSource(with: audioConstraints)
        let audioTrack = NabtoRTC.factory.audioTrack(with: audioSource, trackId: "audio0")
        self.peerConnection.add(audioTrack, streamIds: [streamId])
         */
        
        // video track
        let videoSource = NabtoRTC.factory.videoSource()
        let videoTrack = NabtoRTC.factory.videoTrack(with: videoSource, trackId: "video0")
        self.peerConnection.add(videoTrack, streamIds: [streamId])
        self.remoteVideoTrack = self.peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
        self.remoteVideoTrack?.add(renderer)
        
        Task {
            do {
                let msg = try readSignalMessage(deviceStream)
                switch msg.type {
                case .answer:
                    let answer = try jsonDecoder.decode(SDP.self, from: msg.data!.data(using: .utf8)!)
                    let sdp = RTCSessionDescription(type: RTCSdpType.answer, sdp: answer.sdp)
                    print(answer.sdp)
                    try await self.peerConnection.setRemoteDescription(sdp)
                    break
                case .offer:
                    break
                case .iceCandidate:
                    break
                case .turnRequest:
                    break
                case .turnResponse:
                    break
                }
            } catch {
                // @TODO: Better error handling for the msg loop
                debugPrint("MsgLoop failed: \(error)")
            }
        }
        
        Task {
            let offer = await self.createOffer()
            do {
                let msg = SignalMessage(
                    type: .offer,
                    data: offer.toJSON(),
                    metadata: SignalMessageMetadata(
                        tracks: [SignalMessageMetadataTrack(mid: "0", trackId: "frontdoor-video")],
                        noTrickle: false
                    )
                )
                
                try writeSignalMessage(deviceStream, msg: msg)
                try await peerConnection.setLocalDescription(offer)
            } catch {
                debugPrint("Failed to set local description")
            }
        }
    }
}

extension RTCSessionDescription {
    func toJSON() -> String {
        let strType = switch self.type {
        case .answer: "answer"
        case .offer: "offer"
        case .prAnswer: "prAnswer"
        case .rollback: "rollback"
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
        debugPrint("NabtoRTC: Signaling state changed to \(stateChanged)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        debugPrint("NabtoRTC: New RTCMediaStream \(stream.streamId) added")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        debugPrint("NabtoRTC: RTCMediaStream \(stream.streamId) removed")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        debugPrint("NabtoRTC: Peer connection should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        debugPrint("NabtoRTC: ICE connection state changed to \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        debugPrint("NabtoRTC: ICE gathering state changed to \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // debugPrint("NabtoRTC: New ICE candidate generated: \(candidate.sdp)")
        do {
            try writeSignalMessage(self.deviceStream, msg: SignalMessage(
                type: .iceCandidate,
                data: candidate.toJSON(),
                metadata: nil
            ))
        } catch {
            print("NabtoRTC: Failed to send ICE candidate to peer. \(error)")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        debugPrint("NabtoRTC: ICE candidate removed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen candidate: RTCDataChannel) {
        debugPrint("NabtoRTC: Data channel opened")
    }
}

// MARK: Nabto device signaling
extension NabtoRTC {
    private func readSignalMessage(_ stream: NabtoEdgeClient.Stream) throws -> SignalMessage {
        let lenData = try deviceStream.readAll(length: 4)
        let len: Int32 = lenData.withUnsafeBytes { $0.load(as: Int32.self)}
        
        let data = try stream.readAll(length: Int(len))
        return try jsonDecoder.decode(SignalMessage.self, from: data)
    }
    
    private func writeSignalMessage(_ stream: NabtoEdgeClient.Stream, msg: SignalMessage) throws {
        let encoded = try jsonEncoder.encode(msg)
        let len = UInt32(encoded.count)
        
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: len.littleEndian, Array.init))
        data.append(encoded)
        
        try stream.write(data: data)
    }
}

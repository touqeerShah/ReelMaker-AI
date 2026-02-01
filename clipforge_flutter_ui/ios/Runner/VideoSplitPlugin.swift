import Flutter
import UIKit
import AVFoundation

public class VideoSplitPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private static let CHANNEL = "com.clipforge/video_split"
    private static let PROGRESS_CHANNEL = "com.clipforge/video_split/progress"
    
    private var eventSink: FlutterEventSink?
    private var currentExportSession: AVAssetExportSession?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: registrar.messenger())
        let progressChannel = FlutterEventChannel(name: PROGRESS_CHANNEL, binaryMessenger: registrar.messenger())
        
        let instance = VideoSplitPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        progressChannel.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "splitAndExport":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments required", details: nil))
                return
            }
            splitAndExport(args: args, result: result)
            
        case "getVideoDuration":
            guard let args = call.arguments as? [String: Any],
                  let path = args["path"] as? String else {
                result(FlutterError(code: "INVALID_PATH", message: "Video path required", details: nil))
                return
            }
            getVideoDuration(path: path, result: result)
            
        case "cancelExport":
            cancelExport()
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - FlutterStreamHandler
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    // MARK: - Video Processing
    
    /**
     * Split video and export segments
     *
     * Implementation steps:
     * 1. Parse input arguments
     * 2. Load video asset and get duration
     * 3. For each segment:
     *    - Create AVMutableComposition with time range
     *    - Apply AVVideoComposition for 9:16 scaling (center-fit)
     *    - Add CALayer watermark overlay
     *    - Add timed subscribe overlay (CALayer with opacity animation)
     *    - Export with AVAssetExportSession
     * 4. Return list of output paths
     */
    private func splitAndExport(args: [String: Any], result: @escaping FlutterResult) {
        guard let inputPath = args["inputPath"] as? String,
              let outputDir = args["outputDir"] as? String else {
            result(FlutterError(code: "MISSING_PARAMS", message: "inputPath and outputDir required", details: nil))
            return
        }
        
        let mode = args["mode"] as? String ?? "split_only"
        let segmentSeconds = args["segmentSeconds"] as? Int ?? 60
        let subscribeSeconds = args["subscribeSeconds"] as? Int ?? 5
        let watermarkPosition = args["watermarkPosition"] as? String ?? "Top-right"
        let channelName = args["channelName"] as? String ?? "MyChannel"
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var outputPaths: [String] = []
            
            do {
                let videoURL = URL(fileURLWithPath: inputPath)
                let asset = AVURLAsset(url: videoURL)
                
                guard let duration = try? await asset.load(.duration) else {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "LOAD_FAILED", message: "Failed to load video", details: nil))
                    }
                    return
                }
                
                let durationSeconds = CMTimeGetSeconds(duration)
                let segmentCount = Int(ceil(durationSeconds / Double(segmentSeconds)))
                
                self.sendProgress(current: 0, total: segmentCount, progress: 0.0, status: "Starting export...")
                
                // TODO: Implement actual video processing
                // For each segment:
                // 1. Create AVMutableComposition and extract time range
                // 2. Set up AVMutableVideoComposition with:
                //    - renderSize: CGSize(width: 1080, height: 1920)
                //    - Transform for aspect-fit scaling (center with letterbox/pillarbox)
                // 3. Create CALayer hierarchy:
                //    - Video layer
                //    - Watermark layer (always visible)
                //    - Subscribe layer (opacity animation from subscribeSeconds to end)
                // 4. Export using AVAssetExportSession
                
                // Simulate processing
                for i in 0..<segmentCount {
                    let start = Double(i * segmentSeconds)
                    let end = min(start + Double(segmentSeconds), durationSeconds)
                    
                    self.sendProgress(current: i, total: segmentCount, 
                                    progress: Double(i) / Double(segmentCount),
                                    status: "Processing segment \(i + 1)/\(segmentCount)")
                    
                    try? await Task.sleep(nanoseconds: 500_000_000) // Simulate processing
                    
                    let outputPath = "\(outputDir)/segment_\(String(format: "%03d", i)).mp4"
                    outputPaths.append(outputPath)
                }
                
                self.sendProgress(current: segmentCount, total: segmentCount, progress: 1.0, 
                                status: "Export complete", outputPath: outputPaths.first)
                
                DispatchQueue.main.async {
                    result(outputPaths)
                }
                
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "EXPORT_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func getVideoDuration(path: String, result: @escaping FlutterResult) {
        let videoURL = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: videoURL)
        
        Task {
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                DispatchQueue.main.async {
                    result(seconds)
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "DURATION_FAILED", message: error.localizedDescription, details: nil))
                }
            }
        }
    }
    
    private func cancelExport() {
        currentExportSession?.cancelExport()
        currentExportSession = nil
    }
    
    private func sendProgress(current: Int, total: Int, progress: Double, status: String, 
                            outputPath: String? = nil, error: String? = nil) {
        var data: [String: Any] = [
            "currentSegment": current,
            "totalSegments": total,
            "progress": progress,
            "status": status
        ]
        if let path = outputPath { data["outputPath"] = path }
        if let err = error { data["error"] = err }
        
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(data)
        }
    }
}

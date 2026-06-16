//
//  AmbientNoiseSensor.swift
//  com.awareframework.ios.sensor.ambientnoise
//

import AVFoundation
import CoreML
import Foundation
import SoundAnalysis
import UIKit
import UserNotifications
import com_awareframework_ios_core

// MARK: - Observable data structures

public struct DecibelPoint {
    public var date: Date
    public var value: Double
}

public struct AudioClassPoint {
    public var family: String
    public var date: Date
    public var confidence: Double
}

public struct AmbientNoiseMicrophoneInput: Hashable {
    public let uid: String
    public let name: String
    public let portType: String

    public init(uid: String, name: String, portType: String) {
        self.uid = uid
        self.name = name
        self.portType = portType
    }
}

// MARK: - Observer protocol

public protocol AmbientNoiseSensorObserver {
    func onAmbientNoiseChanged(data: AmbientNoiseData)
    func onAudioLabelChanged(data: AudioLabelData)
}

// MARK: - Notification names

extension Notification.Name {
    public static let actionAwareAmbientNoise = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE)
    public static let actionAwareAmbientNoiseStart = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_START)
    public static let actionAwareAmbientNoiseStop = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_STOP)
    public static let actionAwareAmbientNoiseSetLabel = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_SET_LABEL)
    public static let actionAwareAmbientNoiseSync = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_SYNC)
    public static let actionAwareAmbientNoiseSyncCompletion = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_SYNC_COMPLETION)
    public static let actionAwareAudioLabel = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AUDIO_LABEL)
    public static let actionAwareAudioProcessingError = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AUDIO_PROCESSING_ERROR)
    public static let actionAwareAmbientNoiseMicrophoneChanged = Notification.Name(
        AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_MICROPHONE_CHANGED)
}

// MARK: - Action keys

extension AmbientNoiseSensor {
    public static let ACTION_AWARE_AMBIENT_NOISE = "com.awareframework.ios.sensor.ambientnoise"
    public static let ACTION_AWARE_AMBIENT_NOISE_START =
        "com.awareframework.ios.sensor.ambientnoise.ACTION_START"
    public static let ACTION_AWARE_AMBIENT_NOISE_STOP =
        "com.awareframework.ios.sensor.ambientnoise.ACTION_STOP"
    public static let ACTION_AWARE_AMBIENT_NOISE_SYNC =
        "com.awareframework.ios.sensor.ambientnoise.ACTION_SYNC"
    public static let ACTION_AWARE_AMBIENT_NOISE_SYNC_COMPLETION =
        "com.awareframework.ios.sensor.ambientnoise.ACTION_SYNC_COMPLETION"
    public static let ACTION_AWARE_AMBIENT_NOISE_SET_LABEL =
        "com.awareframework.ios.sensor.ambientnoise.ACTION_SET_LABEL"
    public static let ACTION_AWARE_AUDIO_LABEL =
        "com.awareframework.ios.sensor.ambientnoise.audio_label"
    public static let ACTION_AWARE_AUDIO_PROCESSING_ERROR =
        "com.awareframework.ios.sensor.ambientnoise.audio_processing_error"
    public static let ACTION_AWARE_AMBIENT_NOISE_MICROPHONE_CHANGED =
        "com.awareframework.ios.sensor.ambientnoise.microphone_changed"
    public static let EXTRA_LABEL = "label"
    public static let EXTRA_STATUS = "status"
    public static let EXTRA_ERROR = "error"
    public static let EXTRA_PREVIOUS_INPUT_UID = "previousInputUID"
    public static let TAG = "com.awareframework.ios.sensor.ambientnoise"
}

// MARK: - SNResultsObserving

extension AmbientNoiseSensor: SNResultsObserving {

    public func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        DispatchQueue.main.async {
            let now = Date()
            self.audioClasses.removeAll()
            for c in result.classifications {
                self.audioClasses.append(
                    AudioClassPoint(family: c.identifier, date: now, confidence: c.confidence))
            }
            self.extendDutyCycleIfNeeded(for: result.classifications, now: now)

            let maxKnown = self.knownClassifications?.count ?? result.classifications.count
            let topK = self.CONFIG.storeOnlyTopK ?? maxKnown
            let topClassifications = result.classifications
                .sorted { $0.confidence > $1.confidence }
                .prefix(topK)

            for audioClass in topClassifications {
                let d = AudioLabelData(
                    timestamp: Int64(now.timeIntervalSince1970 * 1000),
                    audioLabel: audioClass.identifier,
                    confidence: audioClass.confidence,
                    label: self.CONFIG.label
                )
                let value = "\(audioClass.identifier) \(audioClass.confidence)"

                if self.CONFIG.debug {
                    print(AmbientNoiseSensor.TAG, now, value)
                }

                if let engine = self.audioLabelSubSensor?.dbEngine {
                    engine.save([d])
                }

                if let observer = self.CONFIG.sensorObserver {
                    observer.onAudioLabelChanged(data: d)
                }

                self.notificationCenter.post(name: .actionAwareAudioLabel, object: self)
            }

            if self.CONFIG.debug {
                print(AmbientNoiseSensor.TAG, "====================")
            }
        }
    }

    public func request(_ request: SNRequest, didFailWithError error: Error) {
        guard isSensorStarted, !isDutyCycleResting() else { return }
        if isApplicationNotActive && !hasCustomAudioClassifier {
            streamAnalyzer = nil
            knownClassifications = nil
            logAudioProcessingState(
                "suppressed audio classification model built into iOS error while app is not active: \(error.localizedDescription)"
            )
            return
        }
        handleAudioProcessingError("Sound analysis failed: \(error.localizedDescription)")
    }

    public func requestDidComplete(_ request: SNRequest) {
        if CONFIG.debug {
            print(AmbientNoiseSensor.TAG, "Sound analysis request completed.")
        }
    }
}

// MARK: - AmbientNoiseSensor

final public class AmbientNoiseSensor: AwareSensor, ObservableObject {

    public enum DutyCyclePhase: String {
        case active
        case resting
    }

    public struct DutyCycleStatus {
        public let phase: DutyCyclePhase
        public let phaseEndsAt: Date?
        public let activeDuration: TimeInterval
        public let restDuration: TimeInterval
        public let extensionEnabled: Bool
        public let extensionLabels: [String]
        public let extensionConfidenceThreshold: Double
        public let noiseLevelExtensionEnabled: Bool
        public let noiseLevelThreshold: Double
        public let extensionDuration: TimeInterval

        public var isActive: Bool {
            phase == .active
        }
    }

    private var audioEngine = AVAudioEngine()
    var knownClassifications: [String]?

    @Published public var decibels = [DecibelPoint]()
    @Published public var audioClasses = [AudioClassPoint]()

    var streamAnalyzer: SNAudioStreamAnalyzer?
    private var streamAnalyzerFormatKey: String?
    var analysisQueue: DispatchQueue!

    private var isSuspended = false
    private var isReadySessionCategory = false
    private var isSensorStarted = false
    private var isUserRequestedRunning = false
    private var hasAudioTap = false
    private var pendingStartAfterForeground = false
    private var pendingInterruptionResumeAfterForeground = false
    private var shouldResumeAfterInterruption = false
    private var interruptionResumeAttempt = 0
    private var audioAnalyzerSetupAttempt = 0
    private var pendingStopNotificationID: String?
    private var cachedApplicationState: UIApplication.State = .active
    private let applicationStateLock = NSLock()
    private var loadedAudioClassifierModel: MLModel?
    private var loadedAudioClassifierModelURL: URL?
    private var loadedAudioClassifierComputeUnits: MLComputeUnits?
    private var dutyCycleActiveUntil: Date?
    private var dutyCycleRestUntil: Date?
    private let dutyCycleLock = NSLock()
    private var lastProcessingErrorNotificationAt: Date?
    private static let processingErrorNotificationID =
        "com.awareframework.ios.sensor.ambientnoise.processing_error"
    private static let stoppedNotificationID =
        "com.awareframework.ios.sensor.ambientnoise.stopped"

    public var audioLabelSubSensor: AudioLabelSubSensor?
    public var ambientNoiseSubSensor: AmbientNoiseSubSensor?

    public var CONFIG = AmbientNoiseSensor.Config()

    // MARK: Config

    public class Config: SensorConfig {
        public var onBus: Int = 0
        public var bufferSize: UInt32 = 16384

        /// Custom Core ML sound classifier. If provided directly, load it with CPU-only
        /// compute units before assigning it when background classification is required.
        public var audioClassifierModel: MLModel?
        /// Custom Core ML sound classifier URL. Models loaded from this URL use
        /// `audioClassifierComputeUnits`, which defaults to CPU-only.
        public var audioClassifierModelURL: URL?
        public var audioClassifierComputeUnits: MLComputeUnits = .cpuOnly
        /// Use the audio classification model built into iOS when no custom model is set.
        /// This classifier is foreground-only because it may submit Metal/GPU work.
        public var useBuiltInAudioClassifier: Bool = true

        public var activateAmbientNoiseSensor: Bool = true
        public var activateAudioClassificationSensor: Bool = false

        public var dutyCycleEnabled: Bool = true
        public var activeDuration: TimeInterval = 60
        public var restDuration: TimeInterval = 60
        public var dutyCycleExtensionEnabled: Bool = false
        public var extensionLabels: [String] = ["speech", "conversation"]
        public var extensionConfidenceThreshold: Double = 0.5
        public var noiseLevelExtensionEnabled: Bool = false
        public var noiseLevelThreshold: Double = -30.0
        public var extensionDuration: TimeInterval = 60
        public var processingFailureNotificationsEnabled: Bool = false

        /// Store only top-K classifications per analysis window. nil stores all.
        public var storeOnlyTopK: Int?
        public var preferredInputUID: String = ""
        public var currentInputUID: String = ""
        public var currentInputName: String = ""
        public var currentInputPortType: String = ""

        public var sensorObserver: AmbientNoiseSensorObserver?

        public override init() {
            super.init()
        }

        public override func set(config: [String: Any]) {
            super.set(config: config)
            if let topK = config["storeOnlyTopK"] as? Int {
                self.storeOnlyTopK = topK
            }
            if let activateAmbient = config["activateAmbientNoiseSensor"] as? Bool {
                self.activateAmbientNoiseSensor = activateAmbient
            }
            if let activateClassification = config["activateAudioClassificationSensor"] as? Bool {
                self.activateAudioClassificationSensor = activateClassification
            }
            if let modelURL = config["audioClassifierModelURL"] as? URL {
                self.audioClassifierModelURL = modelURL
            } else if let modelPath = config["audioClassifierModelURL"] as? String {
                self.audioClassifierModelURL = Self.modelURL(from: modelPath)
            }
            if let computeUnits = config["audioClassifierComputeUnits"] as? MLComputeUnits {
                self.audioClassifierComputeUnits = computeUnits
            } else if let computeUnits = config["audioClassifierComputeUnits"] as? String,
                let parsedComputeUnits = Self.computeUnits(from: computeUnits)
            {
                self.audioClassifierComputeUnits = parsedComputeUnits
            }
            if let useBuiltIn = config["useBuiltInAudioClassifier"] as? Bool {
                self.useBuiltInAudioClassifier = useBuiltIn
            }
            if let preferredInputUID = config["preferredInputUID"] as? String {
                self.preferredInputUID = preferredInputUID
            }
            if let dutyCycleEnabled = config["dutyCycleEnabled"] as? Bool {
                self.dutyCycleEnabled = dutyCycleEnabled
            }
            if let activeDuration = Self.timeIntervalValue(config["activeDuration"]) {
                self.activeDuration = activeDuration
            }
            if let restDuration = Self.timeIntervalValue(config["restDuration"]) {
                self.restDuration = restDuration
            }
            if let enabled = config["dutyCycleExtensionEnabled"] as? Bool {
                self.dutyCycleExtensionEnabled = enabled
            }
            if let labels = config["extensionLabels"] as? [String] {
                self.extensionLabels = labels
            } else if let labels = config["extensionLabels"] as? String {
                self.extensionLabels = Self.labelList(from: labels)
            }
            if let threshold = Self.doubleValue(config["extensionConfidenceThreshold"]) {
                self.extensionConfidenceThreshold = threshold
            }
            if let enabled = config["noiseLevelExtensionEnabled"] as? Bool {
                self.noiseLevelExtensionEnabled = enabled
            }
            if let threshold = Self.doubleValue(config["noiseLevelThreshold"]) {
                self.noiseLevelThreshold = threshold
            }
            if let extensionDuration = Self.timeIntervalValue(config["extensionDuration"]) {
                self.extensionDuration = extensionDuration
            }
            if let enabled = config["processingFailureNotificationsEnabled"] as? Bool {
                self.processingFailureNotificationsEnabled = enabled
            }
        }

        public func apply(closure: (_ config: AmbientNoiseSensor.Config) -> Void) -> Self {
            closure(self)
            return self
        }

        private static func timeIntervalValue(_ value: Any?) -> TimeInterval? {
            if let value = value as? TimeInterval { return value }
            if let value = value as? Int { return TimeInterval(value) }
            return nil
        }

        private static func doubleValue(_ value: Any?) -> Double? {
            if let value = value as? Double { return value }
            if let value = value as? Float { return Double(value) }
            if let value = value as? Int { return Double(value) }
            return nil
        }

        private static func modelURL(from value: String) -> URL? {
            if let url = URL(string: value), url.scheme != nil {
                return url
            }
            return URL(fileURLWithPath: value)
        }

        private static func computeUnits(from value: String) -> MLComputeUnits? {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "cpuonly", "cpu_only", "cpu-only":
                return .cpuOnly
            case "cpuandgpu", "cpu_gpu", "cpu-and-gpu":
                return .cpuAndGPU
            case "cpuandneuralengine", "cpu_neural_engine", "cpu-and-neural-engine":
                if #available(iOS 16.0, *) {
                    return .cpuAndNeuralEngine
                }
                return nil
            case "all":
                return .all
            default:
                return nil
            }
        }

        private static func labelList(from value: String) -> [String] {
            value
                .split { $0 == "," || $0 == "\n" || $0 == "\t" }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    // MARK: Init / Deinit

    public init(_ config: AmbientNoiseSensor.Config) {
        super.init()
        self.CONFIG = config
        self.initializeDbEngine(config: config)
        super.syncConfig = DbSyncConfig().apply { syncConfig in
            syncConfig.serverType = config.serverType
            syncConfig.studyNumber = config.studyNumber
            syncConfig.studyKey = config.studyKey
            syncConfig.debug = config.debug
            syncConfig.batchSize = 1000
        }
        ambientNoiseSubSensor = AmbientNoiseSubSensor(config)
        audioLabelSubSensor = AudioLabelSubSensor(config)

        analysisQueue = DispatchQueue(
            label: "com.awareframework.ios.sensor.ambientnoise.analysisQueue")

        refreshCachedApplicationState()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesWereReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: CONFIG.onBus)
        }
        audioEngine.reset()
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    // MARK: AwareSensor overrides

    public override func start() {
        isUserRequestedRunning = true
        startSensor()
    }

    public override func stop() {
        isUserRequestedRunning = false
        isSensorStarted = false
        pendingStartAfterForeground = false
        pendingInterruptionResumeAfterForeground = false
        shouldResumeAfterInterruption = false
        interruptionResumeAttempt = 0
        cancelPendingStopNotification()
        logAudioProcessingState("stop requested")
        if shouldKeepAudioSessionAliveOnStop() {
            logAudioProcessingState("sensor stopped; keeping audio session alive in background")
        } else {
            stopAudioProcessing()
        }
        notificationCenter.post(name: .actionAwareAmbientNoiseStop, object: self)
    }

    public override func sync(force: Bool = false) {
        notificationCenter.post(name: .actionAwareAmbientNoiseSync, object: self)
        applySubSensorSyncSettings()
        ambientNoiseSubSensor?.sync(force: force)
        audioLabelSubSensor?.sync(force: force)
    }

    public override func set(label: String) {
        self.CONFIG.label = label
        notificationCenter.post(
            name: .actionAwareAmbientNoiseSetLabel,
            object: self,
            userInfo: [AmbientNoiseSensor.EXTRA_LABEL: label]
        )
    }

    private func applySubSensorSyncSettings() {
        let lock = NSLock()
        var remaining = 2
        var hasFailure = false
        var lastError: Error?
        let completion: DbSyncCompletionHandler = { [weak self] status, error in
            lock.lock()
            remaining -= 1
            hasFailure = hasFailure || status == false
            lastError = error ?? lastError
            let shouldNotify = remaining <= 0
            let finalStatus = hasFailure == false
            let finalError = lastError
            lock.unlock()

            guard shouldNotify, let self else { return }
            var userInfo: [String: Any] = [AmbientNoiseSensor.EXTRA_STATUS: finalStatus]
            if let finalError {
                userInfo[AmbientNoiseSensor.EXTRA_ERROR] = finalError
            }
            self.notificationCenter.post(
                name: .actionAwareAmbientNoiseSyncCompletion,
                object: self,
                userInfo: userInfo
            )
        }
        ambientNoiseSubSensor?.applySyncSettings(
            from: CONFIG,
            parentSyncConfig: syncConfig,
            completionHandler: completion
        )
        audioLabelSubSensor?.applySyncSettings(
            from: CONFIG,
            parentSyncConfig: syncConfig,
            completionHandler: completion
        )
    }

    public func availableMicrophoneInputs() -> [AmbientNoiseMicrophoneInput] {
        let audioSession = AVAudioSession.sharedInstance()
        return (audioSession.availableInputs ?? []).map { input in
            AmbientNoiseMicrophoneInput(
                uid: input.uid,
                name: input.portName,
                portType: input.portType.rawValue
            )
        }
    }

    public func refreshCurrentMicrophone() {
        updateCurrentMicrophoneInfo()
    }

    // MARK: Private — start

    private func startSensor(allowBackgroundSessionStart: Bool = false) {
        let audioSession = AVAudioSession.sharedInstance()
        logAudioProcessingState("startSensor requested")
        audioSession.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.startSensorAfterPermission(
                    granted: granted,
                    audioSession: audioSession,
                    allowBackgroundSessionStart: allowBackgroundSessionStart)
            }
        }
    }

    private func startSensorAfterPermission(
        granted: Bool,
        audioSession: AVAudioSession,
        allowBackgroundSessionStart: Bool
    ) {
            guard granted else {
                if self.CONFIG.debug {
                    print(AmbientNoiseSensor.TAG, "Microphone permission denied.")
                }
                return
            }
            do {
                if self.shouldDeferAudioSessionStart(allowBackgroundSessionStart: allowBackgroundSessionStart) {
                    self.pendingStartAfterForeground = true
                    self.logAudioProcessingState("deferring audio session start until foreground")
                    return
                }

                if !self.isReadySessionCategory {
                    try self.configureAudioSessionForRecording(audioSession)
                    try audioSession.setActive(true)
                    self.isReadySessionCategory = true
                }
                self.updateCurrentMicrophoneInfo()
            } catch {
                if self.CONFIG.debug { print(AmbientNoiseSensor.TAG, error) }
                self.logAudioProcessingState("audio session start failed: \(error)")
                self.isSensorStarted = false
                self.isReadySessionCategory = false
                if self.isApplicationNotActive {
                    self.pendingStartAfterForeground = true
                    self.sendProcessingErrorNotification(
                        "Audio recording was paused because the system audio session could not be restarted in the background.")
                }
                return
            }

            self.isSensorStarted = true
            self.pendingStartAfterForeground = false
            self.resetDutyCycle()
            self.logAudioProcessingState("starting audio processing")
            self.startAudioProcessing(inputNode: self.audioEngine.inputNode)
            DispatchQueue.main.async {
                self.notificationCenter.post(name: .actionAwareAmbientNoiseStart, object: self)
                if self.CONFIG.debug { print(AmbientNoiseSensor.TAG, "Sensor started.") }
            }
    }

    private func startAudioProcessing(inputNode: AVAudioInputNode) {
        guard !hasAudioTap else {
            guard !audioEngine.isRunning else {
                logAudioProcessingState("startAudioProcessing skipped because tap already exists")
                return
            }
            do {
                isSensorStarted = true
                try audioEngine.start()
                logAudioProcessingState("audio engine restarted with existing tap")
                cancelPendingStopNotification()
            } catch {
                isSensorStarted = false
                logAudioProcessingState(
                    "engine restart failed with existing tap: \(error)")
                removeStaleAudioTapAfterInterruption()
                isReadySessionCategory = false
            }
            return
        }

        // Prepare the engine first so that inputNode.inputFormat reflects the current hardware
        // state. After audioEngine.reset(), the format returns 0 Hz until the engine is prepared.
        audioEngine.prepare()

        let inputFormat = inputNode.inputFormat(forBus: CONFIG.onBus)

        guard inputFormat.sampleRate > 0 else {
            logAudioProcessingState(
                "input format not yet valid (sampleRate=\(inputFormat.sampleRate)); aborting tap install"
            )
            isSensorStarted = false
            isReadySessionCategory = false
            handleAudioProcessingError(
                "Audio input format is not available. The sensor will restart when the app is next opened."
            )
            return
        }

        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
        streamAnalyzerFormatKey = nil
        knownClassifications = nil

        inputNode.installTap(
            onBus: CONFIG.onBus, bufferSize: CONFIG.bufferSize, format: nil
        ) { buffer, when in
            guard self.isSensorStarted else { return }
            guard self.shouldProcessAudio() else { return }

            if self.shouldAnalyzeAudioLabels() {
                self.analysisQueue.async {
                    guard self.isSensorStarted else { return }
                    guard self.shouldAnalyzeAudioLabels() else { return }
                    self.prepareStreamAnalyzerIfNeeded(inputFormat: buffer.format)
                    self.streamAnalyzer?.analyze(buffer, atAudioFramePosition: when.sampleTime)
                }
            }

            if self.CONFIG.activateAmbientNoiseSensor {
                if let audioData = buffer.floatChannelData?[0] {
                    let rms = SignalProcessing.rms(
                        data: audioData, frameLength: UInt(buffer.frameLength))
                    let db = SignalProcessing.db(from: rms)
                    guard !db.isInfinite else { return }

                    let now = Date()
                    let dbValue = Double(db)
                    self.extendDutyCycleIfNeeded(forNoiseLevel: dbValue, now: now)
                    DispatchQueue.main.async {
                        let d = AmbientNoiseData(
                            timestamp: Int64(now.timeIntervalSince1970 * 1000),
                            db: dbValue,
                            label: self.CONFIG.label
                        )

                        if let engine = self.ambientNoiseSubSensor?.dbEngine {
                            engine.save([d])
                        }

                        if let observer = self.CONFIG.sensorObserver {
                            observer.onAmbientNoiseChanged(data: d)
                        }

                        if self.CONFIG.debug {
                            print(AmbientNoiseSensor.TAG, now, dbValue)
                        }

                        self.notificationCenter.post(name: .actionAwareAmbientNoise, object: self)

                        self.decibels.append(DecibelPoint(date: now, value: dbValue))
                        if self.decibels.count > 100 {
                            self.decibels.removeFirst()
                        }
                    }
                }
            }
        }
        hasAudioTap = true

        do {
            try audioEngine.start()
            logAudioProcessingState("audio engine started")
            cancelPendingStopNotification()
        } catch {
            if CONFIG.debug { print(AmbientNoiseSensor.TAG, "AVAudioEngine start error:", error) }
            if hasAudioTap {
                audioEngine.inputNode.removeTap(onBus: CONFIG.onBus)
                hasAudioTap = false
            }
            audioEngine.reset()
            isReadySessionCategory = false
            isSensorStarted = false
            handleAudioProcessingError(
                "Audio engine failed to start: \(error.localizedDescription)")
            sendProcessingErrorNotification(
                "Audio recording was stopped by another app (e.g., video or music playback).")
        }
    }

    private func prepareStreamAnalyzerIfNeeded(inputFormat: AVAudioFormat) {
        guard !shouldDeferBuiltInAudioClassifierSetup() else {
            return
        }
        let formatKey = analyzerFormatKey(inputFormat)
        guard streamAnalyzer == nil || streamAnalyzerFormatKey != formatKey else {
            return
        }
        prepareStreamAnalyzer(inputFormat: inputFormat)
    }

    private func shouldDeferBuiltInAudioClassifierSetup() -> Bool {
        isApplicationNotActive
            && CONFIG.useBuiltInAudioClassifier
            && CONFIG.audioClassifierModel == nil
            && CONFIG.audioClassifierModelURL == nil
    }

    private func analyzerFormatKey(_ format: AVAudioFormat) -> String {
        "\(format.sampleRate)-\(format.channelCount)-\(format.commonFormat.rawValue)"
    }

    private func prepareStreamAnalyzer(inputFormat: AVAudioFormat) {
        audioAnalyzerSetupAttempt += 1
        let attempt = audioAnalyzerSetupAttempt

        if CONFIG.debug {
            print(
                AmbientNoiseSensor.TAG,
                Date(),
                "prepareStreamAnalyzer attempt=\(attempt) format=\(inputFormat.sampleRate)Hz channels=\(inputFormat.channelCount) background=\(isApplicationNotActive)"
            )
        }

        guard CONFIG.activateAudioClassificationSensor else {
            streamAnalyzer?.removeAllRequests()
            streamAnalyzer = nil
            streamAnalyzerFormatKey = nil
            knownClassifications = nil
            logAudioProcessingState(
                "skipped SNAudioStreamAnalyzer because audio classification is disabled attempt=\(attempt)"
            )
            return
        }

        do {
            streamAnalyzer?.removeAllRequests()
            streamAnalyzer = nil
            streamAnalyzerFormatKey = nil
            knownClassifications = nil

            let request: SNClassifySoundRequest
            if let model = try audioClassifierModelForRequest() {
                logAudioProcessingState("creating SNAudioStreamAnalyzer attempt=\(attempt)")
                streamAnalyzer = SNAudioStreamAnalyzer(format: inputFormat)
                streamAnalyzerFormatKey = analyzerFormatKey(inputFormat)
                logAudioProcessingState("created SNAudioStreamAnalyzer attempt=\(attempt)")

                logAudioProcessingState(
                    "creating SNClassifySoundRequest from custom model attempt=\(attempt)"
                )
                request = try SNClassifySoundRequest(mlModel: model)
            } else if CONFIG.useBuiltInAudioClassifier {
                guard !isApplicationNotActive else {
                    streamAnalyzer = nil
                    streamAnalyzerFormatKey = nil
                    knownClassifications = nil
                    logAudioProcessingState(
                        "deferred audio classification model built into iOS setup while app is not active attempt=\(attempt)"
                    )
                    return
                }

                logAudioProcessingState("creating SNAudioStreamAnalyzer attempt=\(attempt)")
                streamAnalyzer = SNAudioStreamAnalyzer(format: inputFormat)
                streamAnalyzerFormatKey = analyzerFormatKey(inputFormat)
                logAudioProcessingState("created SNAudioStreamAnalyzer attempt=\(attempt)")

                logAudioProcessingState(
                    "creating SNClassifySoundRequest for audio classification model built into iOS attempt=\(attempt)"
                )
                request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            } else {
                streamAnalyzer = nil
                streamAnalyzerFormatKey = nil
                knownClassifications = nil
                logAudioProcessingState(
                    "skipped SNAudioStreamAnalyzer because no audio classifier model is configured attempt=\(attempt)"
                )
                return
            }

            logAudioProcessingState("created SNClassifySoundRequest attempt=\(attempt)")

            knownClassifications = request.knownClassifications
            logAudioProcessingState("adding SNClassifySoundRequest attempt=\(attempt)")
            try streamAnalyzer?.add(request, withObserver: self)
            logAudioProcessingState("added SNClassifySoundRequest attempt=\(attempt)")
        } catch {
            streamAnalyzer?.removeAllRequests()
            streamAnalyzer = nil
            streamAnalyzerFormatKey = nil
            if CONFIG.debug {
                print(
                    AmbientNoiseSensor.TAG,
                    Date(),
                    "SoundAnalysis setup error attempt=\(attempt):",
                    error
                )
            }
            handleAudioProcessingError(
                "Sound analysis setup failed: \(error.localizedDescription)")
        }
    }

    public func applyRuntimeAudioConfiguration() {
        resetDutyCycle()
        updateCurrentMicrophoneInfo()

        guard hasAudioTap else { return }
        let inputFormat = audioEngine.inputNode.inputFormat(forBus: CONFIG.onBus)

        if CONFIG.activateAudioClassificationSensor {
            logAudioProcessingState("applying runtime audio classification configuration")
            prepareStreamAnalyzer(inputFormat: inputFormat)
        } else {
            logAudioProcessingState("removing audio classification request from runtime configuration")
            streamAnalyzer?.removeAllRequests()
            knownClassifications = nil
            streamAnalyzerFormatKey = nil
        }
    }

    private func audioClassifierModelForRequest() throws -> MLModel? {
        if let model = CONFIG.audioClassifierModel {
            return model
        }
        guard let modelURL = CONFIG.audioClassifierModelURL else {
            return nil
        }

        if loadedAudioClassifierModelURL == modelURL,
            loadedAudioClassifierComputeUnits == CONFIG.audioClassifierComputeUnits,
            let loadedAudioClassifierModel
        {
            return loadedAudioClassifierModel
        }

        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = CONFIG.audioClassifierComputeUnits
        let model = try MLModel(contentsOf: modelURL, configuration: modelConfiguration)
        loadedAudioClassifierModel = model
        loadedAudioClassifierModelURL = modelURL
        loadedAudioClassifierComputeUnits = CONFIG.audioClassifierComputeUnits

        if CONFIG.debug {
            print(
                AmbientNoiseSensor.TAG,
                Date(),
                "Loaded custom audio classifier model with computeUnits=\(CONFIG.audioClassifierComputeUnits)"
            )
        }

        return model
    }

    private func resetDutyCycle() {
        dutyCycleLock.lock()
        let now = Date()
        dutyCycleActiveUntil = now.addingTimeInterval(max(0.1, CONFIG.activeDuration))
        dutyCycleRestUntil = nil
        dutyCycleLock.unlock()
    }

    private func shouldProcessAudio(now: Date = Date()) -> Bool {
        dutyCycleLock.lock()
        defer { dutyCycleLock.unlock() }

        return updateDutyCycleState(now: now)
    }

    public func currentDutyCycleStatus(now: Date = Date()) -> DutyCycleStatus? {
        guard CONFIG.dutyCycleEnabled else { return nil }

        dutyCycleLock.lock()
        let isActive = updateDutyCycleState(now: now)
        let status = DutyCycleStatus(
            phase: isActive ? .active : .resting,
            phaseEndsAt: isActive ? dutyCycleActiveUntil : dutyCycleRestUntil,
            activeDuration: max(0.1, CONFIG.activeDuration),
            restDuration: max(0.1, CONFIG.restDuration),
            extensionEnabled: CONFIG.dutyCycleExtensionEnabled,
            extensionLabels: CONFIG.extensionLabels,
            extensionConfidenceThreshold: min(1.0, max(0.0, CONFIG.extensionConfidenceThreshold)),
            noiseLevelExtensionEnabled: CONFIG.noiseLevelExtensionEnabled,
            noiseLevelThreshold: CONFIG.noiseLevelThreshold,
            extensionDuration: max(0.0, CONFIG.extensionDuration)
        )
        dutyCycleLock.unlock()
        return status
    }

    private func updateDutyCycleState(now: Date) -> Bool {
        guard CONFIG.dutyCycleEnabled else { return true }

        let activeDuration = max(0.1, CONFIG.activeDuration)
        let restDuration = max(0.1, CONFIG.restDuration)

        if let restUntil = dutyCycleRestUntil {
            guard now >= restUntil else { return false }
            dutyCycleRestUntil = nil
            dutyCycleActiveUntil = now.addingTimeInterval(activeDuration)
            return true
        }

        let activeUntil = dutyCycleActiveUntil ?? now.addingTimeInterval(activeDuration)
        dutyCycleActiveUntil = activeUntil

        if now >= activeUntil {
            dutyCycleRestUntil = now.addingTimeInterval(restDuration)
            dutyCycleActiveUntil = nil
            return false
        }

        return true
    }

    private func isDutyCycleResting(now: Date = Date()) -> Bool {
        guard CONFIG.dutyCycleEnabled else { return false }

        dutyCycleLock.lock()
        defer { dutyCycleLock.unlock() }

        guard let restUntil = dutyCycleRestUntil else { return false }
        return now < restUntil
    }

    private func extendDutyCycleIfNeeded(for classifications: [SNClassification], now: Date) {
        guard CONFIG.dutyCycleEnabled,
            CONFIG.dutyCycleExtensionEnabled,
            CONFIG.extensionDuration > 0
        else {
            return
        }

        let labels = CONFIG.extensionLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !labels.isEmpty else { return }

        let threshold = min(1.0, max(0.0, CONFIG.extensionConfidenceThreshold))
        let matched = classifications.contains { classification in
            guard classification.confidence >= threshold else { return false }
            let identifier = classification.identifier.lowercased()
            return labels.contains { label in
                identifier == label || identifier.contains(label)
            }
        }
        guard matched else { return }

        extendDutyCycle(by: CONFIG.extensionDuration, now: now)
    }

    private func extendDutyCycleIfNeeded(forNoiseLevel db: Double, now: Date) {
        guard CONFIG.dutyCycleEnabled,
            CONFIG.noiseLevelExtensionEnabled,
            CONFIG.extensionDuration > 0,
            db >= CONFIG.noiseLevelThreshold
        else {
            return
        }

        extendDutyCycle(by: CONFIG.extensionDuration, now: now)
    }

    private func extendDutyCycle(by duration: TimeInterval, now: Date) {
        dutyCycleLock.lock()
        if dutyCycleRestUntil == nil {
            let base = max(dutyCycleActiveUntil ?? now, now)
            dutyCycleActiveUntil = base.addingTimeInterval(duration)
        }
        dutyCycleLock.unlock()
    }

    private func applyPreferredInput(_ audioSession: AVAudioSession) throws {
        guard let preferredInput = preferredRecordingInput(audioSession) else {
            return
        }
        try audioSession.setPreferredInput(preferredInput)
    }

    private func preferredRecordingInput(_ audioSession: AVAudioSession) -> AVAudioSessionPortDescription? {
        let availableInputs = audioSession.availableInputs ?? []
        if CONFIG.preferredInputUID.isEmpty == false {
            return availableInputs.first { $0.uid == CONFIG.preferredInputUID }
        }

        // For long-running background sensing, keep the device microphone stable by default.
        // AirPods route changes can otherwise move input to Bluetooth HFP and destabilize
        // background session recovery after Siri.
        return availableInputs.first { $0.portType == .builtInMic }
    }

    private func configureAudioSessionForRecording(_ audioSession: AVAudioSession) throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: recordingSessionOptions(audioSession)
        )
        try applyPreferredInput(audioSession)
    }

    private func recordingSessionOptions(
        _ audioSession: AVAudioSession
    ) -> AVAudioSession.CategoryOptions {
        // Keep Bluetooth media output on A2DP when recording from the iPhone mic.
        // Enabling .allowBluetooth permits HFP input/output, which can degrade media playback
        // quality on AirPods during long-running sensing.
        guard usesBluetoothRecordingInput(audioSession) else {
            return [.mixWithOthers, .allowBluetoothA2DP]
        }
        return [.mixWithOthers, .allowBluetooth]
    }

    private func usesBluetoothRecordingInput(_ audioSession: AVAudioSession) -> Bool {
        guard CONFIG.preferredInputUID.isEmpty == false,
            let input = preferredRecordingInput(audioSession)
        else {
            return false
        }
        return input.portType == .bluetoothHFP
    }

    private func updateCurrentMicrophoneInfo() {
        let input = AVAudioSession.sharedInstance().currentRoute.inputs.first
        CONFIG.currentInputUID = input?.uid ?? ""
        CONFIG.currentInputName = input?.portName ?? ""
        CONFIG.currentInputPortType = input?.portType.rawValue ?? ""
    }

    // MARK: Private — stop

    private func stopAudioProcessing(preserveAudioSession: Bool = false) {
        logAudioProcessingState(
            preserveAudioSession
                ? "stopping audio processing while preserving audio session"
                : "stopping audio processing"
        )
        audioEngine.stop()
        audioEngine.disconnectNodeOutput(audioEngine.inputNode)
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: CONFIG.onBus)
            hasAudioTap = false
        }
        audioEngine.reset()
        if !preserveAudioSession {
            isReadySessionCategory = false
        }
        logAudioProcessingState("audio processing stopped")
    }

    private func shouldKeepAudioSessionAliveOnStop() -> Bool {
        isApplicationNotActive && hasAudioTap && audioEngine.isRunning
    }

    private func shouldDeferAudioSessionStart(allowBackgroundSessionStart: Bool = false) -> Bool {
        guard !allowBackgroundSessionStart else { return false }
        return isApplicationNotActive && (!hasAudioTap || !audioEngine.isRunning || !isReadySessionCategory)
    }

    private var applicationState: UIApplication.State {
        applicationStateLock.lock()
        let state = cachedApplicationState
        applicationStateLock.unlock()
        return state
    }

    private var isApplicationNotActive: Bool {
        applicationState != .active
    }

    private var hasCustomAudioClassifier: Bool {
        CONFIG.audioClassifierModel != nil || CONFIG.audioClassifierModelURL != nil
    }

    private func shouldAnalyzeAudioLabels() -> Bool {
        guard CONFIG.activateAudioClassificationSensor else { return false }
        if hasCustomAudioClassifier {
            return true
        }
        return CONFIG.useBuiltInAudioClassifier && !isApplicationNotActive
    }

    private func updateCachedApplicationState(_ state: UIApplication.State) {
        applicationStateLock.lock()
        cachedApplicationState = state
        applicationStateLock.unlock()
    }

    private func refreshCachedApplicationState() {
        if Thread.isMainThread {
            updateCachedApplicationState(UIApplication.shared.applicationState)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateCachedApplicationState(UIApplication.shared.applicationState)
            }
        }
    }

    private func logAudioProcessingState(_ message: String) {
        guard CONFIG.debug else { return }
        let state = applicationState
        print(
            AmbientNoiseSensor.TAG,
            Date(),
            message,
            "appState=\(state.rawValue)",
            "sensorStarted=\(isSensorStarted)",
            "hasTap=\(hasAudioTap)",
            "engineRunning=\(audioEngine.isRunning)",
            "sessionReady=\(isReadySessionCategory)",
            "pendingForegroundStart=\(pendingStartAfterForeground)",
            "pendingForegroundInterruptionResume=\(pendingInterruptionResumeAfterForeground)",
            "shouldResumeAfterInterruption=\(shouldResumeAfterInterruption)",
            "analyzerReady=\(streamAnalyzer != nil)",
            "audioClassification=\(CONFIG.activateAudioClassificationSensor)",
            "ambientNoise=\(CONFIG.activateAmbientNoiseSensor)"
        )
    }

    private func handleAudioProcessingError(_ message: String) {
        logAudioProcessingState("audio processing error: \(message)")
        DispatchQueue.main.async {
            self.notificationCenter.post(
                name: .actionAwareAudioProcessingError,
                object: self,
                userInfo: [AmbientNoiseSensor.EXTRA_ERROR: message]
            )
        }
    }

    private func sendProcessingErrorNotification(_ message: String) {
        guard CONFIG.processingFailureNotificationsEnabled else { return }

        let now = Date()
        if let last = lastProcessingErrorNotificationAt,
            now.timeIntervalSince(last) < 60
        {
            return
        }
        lastProcessingErrorNotificationAt = now

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.stoppedNotificationID, Self.processingErrorNotificationID])
        center.removeDeliveredNotifications(
            withIdentifiers: [Self.stoppedNotificationID, Self.processingErrorNotificationID])
        pendingStopNotificationID = nil
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Ambient noise recording stopped"
            content.body = "\(message) Please open the app and restart the sensor."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: Self.processingErrorNotificationID,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func scheduleStopNotification() {
        guard CONFIG.processingFailureNotificationsEnabled else { return }
        if pendingStopNotificationID != nil { return }
        let id = Self.stoppedNotificationID
        pendingStopNotificationID = id
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted, self?.pendingStopNotificationID == id else { return }
            let content = UNMutableNotificationContent()
            content.title = "Ambient noise recording stopped"
            content.body =
                "Recording was interrupted by another app or system event. "
                + "It will restart automatically if possible. "
                + "Open the app to restart manually."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private func cancelPendingStopNotification() {
        guard let id = pendingStopNotificationID else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
        pendingStopNotificationID = nil
    }

    private func finishInterruptionRecoveryIfRunning() -> Bool {
        guard isAudioProcessingRunning else { return false }
        logAudioProcessingState("interruption resume completed")
        pendingStartAfterForeground = false
        pendingInterruptionResumeAfterForeground = false
        shouldResumeAfterInterruption = false
        isSuspended = false
        interruptionResumeAttempt = 0
        return true
    }

    // MARK: Interruption handling

    private var isAudioProcessingRunning: Bool {
        isSensorStarted && hasAudioTap && audioEngine.isRunning
    }

    private func suspendAudioProcessingForInterruption() {
        logAudioProcessingState("suspending audio for interruption (soft stop)")
        isSensorStarted = false
        pendingStartAfterForeground = false
        pendingInterruptionResumeAfterForeground = false
        // Soft stop: halt the engine but do NOT remove the tap or call audioEngine.reset().
        // Keeping the tap and session alive lets resumeAudioProcessingAfterInterruption
        // restart with just setActive(true) + audioEngine.start(), which is fully
        // synchronous and avoids the outf 0 Hz error caused by reset().
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        cancelPendingStopNotification()
    }

    @discardableResult
    private func startAudioEngineFastPathAfterInterruption(_ context: String) -> Bool {
        guard hasAudioTap else { return false }

        do {
            isSensorStarted = true
            try audioEngine.start()
            logAudioProcessingState("audio engine restarted after interruption (\(context))")
            cancelPendingStopNotification()
            notificationCenter.post(name: .actionAwareAmbientNoiseStart, object: self)
            return true
        } catch {
            isSensorStarted = false
            logAudioProcessingState("engine restart failed (\(context)): \(error)")
            return false
        }
    }

    private func resumeAudioProcessingAfterInterruption() {
        guard isUserRequestedRunning else {
            logAudioProcessingState("interruption resume skipped: stopped by user")
            return
        }

        // Bypass requestRecordPermission (async callback — cannot fire if the OS suspends
        // the app before the dispatch). Permission was already granted at start time.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try configureAudioSessionForRecording(audioSession)
            // Match AVAudioSession's recommended interruption recovery order:
            // reactivate the session first, then restart the already configured engine.
            try audioSession.setActive(true)
            isReadySessionCategory = true
            logAudioProcessingState("audio session reactivated for interruption resume")
        } catch {
            logAudioProcessingState("setActive(true) failed for interruption resume: \(error)")
            isSensorStarted = false
            if isApplicationNotActive {
                pendingInterruptionResumeAfterForeground = true
                logAudioProcessingState(
                    "deferring interruption resume until foreground because session activation is unavailable in background")
                sendProcessingErrorNotification(
                    "Audio recording was paused by Siri or another system audio interruption.")
                return
            }
            removeStaleAudioTapAfterInterruption()
            isReadySessionCategory = false
            return
        }

        if startAudioEngineFastPathAfterInterruption("fast path after session activation") {
            return
        }

        removeStaleAudioTapAfterInterruption()

        // Full restart path (tap was absent or fast-path failed).
        isSensorStarted = true
        pendingStartAfterForeground = false
        resetDutyCycle()
        updateCurrentMicrophoneInfo()
        logAudioProcessingState("starting audio processing after interruption (full path)")
        startAudioProcessing(inputNode: audioEngine.inputNode)
        if isAudioProcessingRunning {
            notificationCenter.post(name: .actionAwareAmbientNoiseStart, object: self)
        }
    }

    private func scheduleInterruptionResumeAttempt(delay: TimeInterval) {
        interruptionResumeAttempt += 1
        let attempt = interruptionResumeAttempt
        logAudioProcessingState(
            "scheduling interruption resume attempt=\(attempt) delay=\(delay)")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.shouldResumeAfterInterruption else {
                self.logAudioProcessingState(
                    "interruption resume attempt=\(attempt) skipped: resume no longer pending")
                return
            }

            self.logAudioProcessingState("running interruption resume attempt=\(attempt)")
            self.resumeAudioProcessingAfterInterruption()

            // resumeAudioProcessingAfterInterruption is synchronous, so isAudioProcessingRunning
            // reflects the result of this attempt immediately.
            if self.finishInterruptionRecoveryIfRunning() {
                return
            }

            if self.pendingInterruptionResumeAfterForeground {
                self.logAudioProcessingState(
                    "interruption resume attempt=\(attempt) deferred until foreground")
                return
            }

            if attempt < 3 {
                self.logAudioProcessingState(
                    "interruption resume attempt=\(attempt) did not restore audio; retrying")
                self.scheduleInterruptionResumeAttempt(delay: 3.0)
                return
            }

            self.logAudioProcessingState(
                "interruption resume failed after \(attempt) attempts")
            self.shouldResumeAfterInterruption = false
            self.isSuspended = false
            self.interruptionResumeAttempt = 0
            self.handleAudioProcessingError(
                "Audio recording could not resume after an audio session interruption.")
            if self.pendingInterruptionResumeAfterForeground {
                self.logAudioProcessingState(
                    "suppressed interruption failure notification because foreground restart is pending")
            } else {
                self.sendProcessingErrorNotification(
                    "Audio recording was stopped by another app (e.g., video or music playback).")
            }
        }
    }

    private func deferInterruptionResume(reason: String) {
        logAudioProcessingState(reason)
        shouldResumeAfterInterruption = true
        isSuspended = true
        pendingStartAfterForeground = isApplicationNotActive
        interruptionResumeAttempt = 0
        scheduleInterruptionResumeAttempt(delay: 3.0)
    }

    private func removeStaleAudioTapAfterInterruption() {
        guard hasAudioTap else { return }
        audioEngine.inputNode.removeTap(onBus: CONFIG.onBus)
        hasAudioTap = false
        audioEngine.reset()
    }

    private func rebuildAudioEngineAfterMediaServicesReset() {
        logAudioProcessingState("rebuilding audio engine after media services reset")

        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
        audioAnalyzerSetupAttempt = 0

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasAudioTap {
            audioEngine.inputNode.removeTap(onBus: CONFIG.onBus)
            hasAudioTap = false
        }
        audioEngine.reset()
        audioEngine = AVAudioEngine()

        isReadySessionCategory = false
        isSensorStarted = false
        isSuspended = false
        shouldResumeAfterInterruption = false
        interruptionResumeAttempt = 0
        pendingStartAfterForeground = false
        pendingInterruptionResumeAfterForeground = false
        cancelPendingStopNotification()
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.handleRouteChange(notification: notification) }
            return
        }
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        logAudioProcessingState("audio route changed reason=\(reason.rawValue)")

        let previousInputUID = CONFIG.currentInputUID
        updateCurrentMicrophoneInfo()
        let newInputUID = CONFIG.currentInputUID

        if previousInputUID != newInputUID {
            DispatchQueue.main.async {
                self.notificationCenter.post(
                    name: .actionAwareAmbientNoiseMicrophoneChanged,
                    object: self,
                    userInfo: [AmbientNoiseSensor.EXTRA_PREVIOUS_INPUT_UID: previousInputUID]
                )
            }
        }

        // Defer to interruption handling when recovery is already in progress.
        guard isSensorStarted, !isSuspended, !shouldResumeAfterInterruption else { return }

        if recoverStoppedAudioEngineAfterRouteChange(reason: reason) {
            return
        }

        if shouldKeepRunningAfterBackgroundRouteChange(reason: reason) {
            logAudioProcessingState(
                "audio route changed while running in background; keeping current engine")
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            if newInputUID.isEmpty {
                logAudioProcessingState(
                    "input route became temporarily unavailable; restarting with preferred route")
                stopAudioProcessing(preserveAudioSession: true)
                isReadySessionCategory = false
                startSensor(allowBackgroundSessionStart: true)
            } else {
                logAudioProcessingState("input device removed; restarting with new route")
                stopAudioProcessing(preserveAudioSession: true)
                isReadySessionCategory = false
                startSensor(allowBackgroundSessionStart: true)
            }
        case .categoryChange, .override:
            logAudioProcessingState("audio route changed by session configuration; keeping current engine")
        case .newDeviceAvailable:
            logAudioProcessingState("input device became available; keeping preferred recording route")
            applyPreferredRecordingInputIfPossible()
        case .routeConfigurationChange:
            logAudioProcessingState("audio route changed; restarting audio engine")
            stopAudioProcessing(preserveAudioSession: true)
            isReadySessionCategory = false
            startSensor(allowBackgroundSessionStart: true)
        case .noSuitableRouteForCategory:
            handleAudioProcessingError(
                "No suitable audio input is available for the current audio category.")
        default:
            break
        }
    }

    private func recoverStoppedAudioEngineAfterRouteChange(
        reason: AVAudioSession.RouteChangeReason
    ) -> Bool {
        guard isUserRequestedRunning, isSensorStarted, hasAudioTap, !audioEngine.isRunning else {
            return false
        }

        logAudioProcessingState(
            "audio engine stopped during route change reason=\(reason.rawValue); attempting restart")

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try configureAudioSessionForRecording(audioSession)
            try audioSession.setActive(true)
            isReadySessionCategory = true
            updateCurrentMicrophoneInfo()
        } catch {
            logAudioProcessingState(
                "setActive(true) failed for route change recovery: \(error)")
            deferInterruptionResume(
                reason: "route change recovery deferred after session activation failure")
            return true
        }

        if startAudioEngineFastPathAfterInterruption("route change recovery") {
            _ = finishInterruptionRecoveryIfRunning()
            return true
        }

        deferInterruptionResume(
            reason: "route change recovery did not restore audio; scheduling retry")
        return true
    }

    private func shouldKeepRunningAfterBackgroundRouteChange(
        reason: AVAudioSession.RouteChangeReason
    ) -> Bool {
        guard isApplicationNotActive, isAudioProcessingRunning else { return false }

        switch reason {
        case .categoryChange, .routeConfigurationChange, .override, .newDeviceAvailable:
            return true
        case .oldDeviceUnavailable:
            return CONFIG.currentInputUID.isEmpty == false
        default:
            return false
        }
    }

    private func applyPreferredRecordingInputIfPossible() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try applyPreferredInput(audioSession)
            updateCurrentMicrophoneInfo()
        } catch {
            if CONFIG.debug {
                print(AmbientNoiseSensor.TAG, "Failed to apply preferred input: \(error)")
            }
        }
    }

    @objc private func handleMediaServicesWereReset(notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.handleMediaServicesWereReset(notification: notification) }
            return
        }
        let shouldRestart = isUserRequestedRunning
        logAudioProcessingState("media services were reset")
        rebuildAudioEngineAfterMediaServicesReset()

        guard shouldRestart else { return }
        if isApplicationNotActive {
            pendingStartAfterForeground = true
            logAudioProcessingState("restarting audio after media services reset in background")
            startSensor(allowBackgroundSessionStart: true)
        } else {
            logAudioProcessingState("restarting audio after media services reset")
            startSensor()
        }
    }

    @objc private func handleInterruption(notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.handleInterruption(notification: notification) }
            return
        }
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            logAudioProcessingState("audio session interruption began")
            if !isSuspended {
                shouldResumeAfterInterruption =
                    isSensorStarted || hasAudioTap || audioEngine.isRunning
                interruptionResumeAttempt = 0
                isSuspended = true
                suspendAudioProcessingForInterruption()
            }
        case .ended:
            logAudioProcessingState("audio session interruption ended")
            guard isSuspended || shouldResumeAfterInterruption else { return }

            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                deferInterruptionResume(
                    reason: "interruption ended without resume options; scheduling restart")
                return
            }

            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            guard options.contains(.shouldResume) else {
                deferInterruptionResume(
                    reason: "interruption ended without shouldResume; scheduling restart")
                return
            }

            logAudioProcessingState(
                "interruption ended with shouldResume (Siri / voice input)")
            logAudioProcessingState("attempting immediate interruption resume")

            // Resume synchronously while this notification callback is still executing.
            resumeAudioProcessingAfterInterruption()
            if finishInterruptionRecoveryIfRunning() {
                return
            }

            if pendingInterruptionResumeAfterForeground {
                logAudioProcessingState("waiting for foreground to resume after interruption")
                return
            }

            shouldResumeAfterInterruption = true
            isSuspended = true
            interruptionResumeAttempt = 0
            scheduleInterruptionResumeAttempt(delay: 3.0)
        @unknown default:
            break
        }
    }

    @objc private func handleDidBecomeActive() {
        updateCachedApplicationState(.active)
        logAudioProcessingState("didBecomeActive received")
        if pendingInterruptionResumeAfterForeground {
            pendingInterruptionResumeAfterForeground = false
            pendingStartAfterForeground = false
            logAudioProcessingState("restarting audio after deferred interruption resume")
            stopAudioProcessing()
            isSuspended = false
            shouldResumeAfterInterruption = false
            startSensor()
            return
        }
        if pendingStartAfterForeground {
            pendingStartAfterForeground = false
            logAudioProcessingState("retrying deferred audio session start")
            startSensor()
            return
        }
        if isUserRequestedRunning && !isAudioProcessingRunning {
            logAudioProcessingState("auto-restarting sensor on foreground after interruption or failure")
            // Clear stale engine state that may have been left by OS suspension during a long
            // interruption (e.g. phone call): hasAudioTap and isReadySessionCategory could be
            // true in memory while the engine was actually torn down by the OS.
            stopAudioProcessing()
            isSuspended = false
            shouldResumeAfterInterruption = false
            startSensor()
            return
        }
        if isSensorStarted, hasAudioTap, CONFIG.activateAudioClassificationSensor {
            let inputFormat = audioEngine.inputNode.inputFormat(forBus: CONFIG.onBus)
            logAudioProcessingState("rebuilding audio classification analyzer after foreground")
            prepareStreamAnalyzer(inputFormat: inputFormat)
        }
    }

    @objc private func handleWillResignActive() {
        updateCachedApplicationState(.inactive)
        logAudioProcessingState("willResignActive received")
    }

    @objc private func handleDidEnterBackground() {
        updateCachedApplicationState(.background)
        logAudioProcessingState("didEnterBackground received")
    }

    @objc private func handleWillEnterForeground() {
        updateCachedApplicationState(.inactive)
        logAudioProcessingState("willEnterForeground received")
    }
}

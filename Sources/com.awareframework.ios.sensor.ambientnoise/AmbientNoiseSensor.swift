//
//  AmbientNoiseSensor.swift
//  com.awareframework.ios.sensor.ambientnoise
//

import Foundation
import AVFoundation
import SoundAnalysis
import CoreML
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
    public static let actionAwareAmbientNoise            = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE)
    public static let actionAwareAmbientNoiseStart       = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_START)
    public static let actionAwareAmbientNoiseStop        = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_STOP)
    public static let actionAwareAmbientNoiseSetLabel    = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_SET_LABEL)
    public static let actionAwareAmbientNoiseSync        = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_SYNC)
    public static let actionAwareAmbientNoiseSyncCompletion = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AMBIENT_NOISE_SYNC_COMPLETION)
    public static let actionAwareAudioLabel              = Notification.Name(AmbientNoiseSensor.ACTION_AWARE_AUDIO_LABEL)
}

// MARK: - Action keys

public extension AmbientNoiseSensor {
    static let ACTION_AWARE_AMBIENT_NOISE               = "com.awareframework.ios.sensor.ambientnoise"
    static let ACTION_AWARE_AMBIENT_NOISE_START         = "com.awareframework.ios.sensor.ambientnoise.ACTION_START"
    static let ACTION_AWARE_AMBIENT_NOISE_STOP          = "com.awareframework.ios.sensor.ambientnoise.ACTION_STOP"
    static let ACTION_AWARE_AMBIENT_NOISE_SYNC          = "com.awareframework.ios.sensor.ambientnoise.ACTION_SYNC"
    static let ACTION_AWARE_AMBIENT_NOISE_SYNC_COMPLETION = "com.awareframework.ios.sensor.ambientnoise.ACTION_SYNC_COMPLETION"
    static let ACTION_AWARE_AMBIENT_NOISE_SET_LABEL     = "com.awareframework.ios.sensor.ambientnoise.ACTION_SET_LABEL"
    static let ACTION_AWARE_AUDIO_LABEL                 = "com.awareframework.ios.sensor.ambientnoise.audio_label"
    static let EXTRA_LABEL                              = "label"
    static let EXTRA_STATUS                             = "status"
    static let EXTRA_ERROR                              = "error"
    static let TAG                                      = "com.awareframework.ios.sensor.ambientnoise"
}

// MARK: - SNResultsObserving

extension AmbientNoiseSensor: SNResultsObserving {

    public func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        DispatchQueue.main.async {
            let now = Date()
            self.audioClasses.removeAll()
            for c in result.classifications {
                self.audioClasses.append(AudioClassPoint(family: c.identifier, date: now, confidence: c.confidence))
            }

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

                if self.CONFIG.debug {
                    print(AmbientNoiseSensor.TAG, audioClass.identifier, audioClass.confidence)
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
}

// MARK: - AmbientNoiseSensor

final public class AmbientNoiseSensor: AwareSensor, ObservableObject {

    private var audioEngine = AVAudioEngine()
    var knownClassifications: [String]?

    @Published public var decibels = [DecibelPoint]()
    @Published public var audioClasses = [AudioClassPoint]()

    var streamAnalyzer: SNAudioStreamAnalyzer!
    var analysisQueue: DispatchQueue!

    private var isSuspended = false
    private var isReadySessionCategory = false

    public var audioLabelSubSensor: AudioLabelSubSensor?
    public var ambientNoiseSubSensor: AmbientNoiseSubSensor?

    public var CONFIG = AmbientNoiseSensor.Config()

    // MARK: Config

    public class Config: SensorConfig {
        public var onBus: Int = 0
        public var bufferSize: UInt32 = 8192

        public var audioClassifierModel: MLModel?

        public var activateAmbientNoiseSensor: Bool = true
        public var activateAudioClassificationSensor: Bool = true

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

        public override func set(config: Dictionary<String, Any>) {
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
            if let preferredInputUID = config["preferredInputUID"] as? String {
                self.preferredInputUID = preferredInputUID
            }
        }

        public func apply(closure: (_ config: AmbientNoiseSensor.Config) -> Void) -> Self {
            closure(self)
            return self
        }
    }

    // MARK: Init / Deinit

    public init(_ config: AmbientNoiseSensor.Config) {
        super.init()
        self.CONFIG = config
        self.initializeDbEngine(config: config)
        ambientNoiseSubSensor = AmbientNoiseSubSensor(config)
        audioLabelSubSensor = AudioLabelSubSensor(config)

        analysisQueue = DispatchQueue(label: "com.awareframework.ios.sensor.ambientnoise.analysisQueue")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        audioEngine.inputNode.removeTap(onBus: CONFIG.onBus)
        audioEngine.reset()
        NotificationCenter.default.removeObserver(
            self,
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    // MARK: AwareSensor overrides

    public override func start() {
        startSensor()
    }

    public override func stop() {
        stopAudioProcessing()
        notificationCenter.post(name: .actionAwareAmbientNoiseStop, object: self)
    }

    public override func sync(force: Bool = false) {
        notificationCenter.post(name: .actionAwareAmbientNoiseSync, object: self)
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

    public func availableMicrophoneInputs() -> [AmbientNoiseMicrophoneInput] {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .default, options: [])
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

    private func startSensor() {
        let audioSession = AVAudioSession.sharedInstance()
        audioSession.requestRecordPermission { granted in
            guard granted else {
                if self.CONFIG.debug { print(AmbientNoiseSensor.TAG, "Microphone permission denied.") }
                return
            }
            do {
                if !self.isReadySessionCategory {
                    try audioSession.setCategory(.record, mode: .default, options: [])
                    try self.applyPreferredInput(audioSession)
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    self.isReadySessionCategory = true
                }
                self.updateCurrentMicrophoneInfo()
            } catch {
                if self.CONFIG.debug { print(AmbientNoiseSensor.TAG, error) }
                return
            }

            self.startAudioProcessing(inputNode: self.audioEngine.inputNode)
            DispatchQueue.main.async {
                self.notificationCenter.post(name: .actionAwareAmbientNoiseStart, object: self)
                if self.CONFIG.debug { print(AmbientNoiseSensor.TAG, "Sensor started.") }
            }
        }
    }

    private func startAudioProcessing(inputNode: AVAudioInputNode) {
        let inputFormat = inputNode.inputFormat(forBus: CONFIG.onBus)

        streamAnalyzer = SNAudioStreamAnalyzer(format: inputFormat)

        if CONFIG.activateAudioClassificationSensor {
            do {
                if let model = CONFIG.audioClassifierModel {
                    let request = try SNClassifySoundRequest(mlModel: model)
                    knownClassifications = request.knownClassifications
                    try streamAnalyzer.add(request, withObserver: self)
                } else {
                    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                    knownClassifications = request.knownClassifications
                    try streamAnalyzer.add(request, withObserver: self)
                }
            } catch {
                if CONFIG.debug { print(AmbientNoiseSensor.TAG, "SoundAnalysis setup error:", error) }
            }
        }

        inputNode.installTap(onBus: CONFIG.onBus, bufferSize: CONFIG.bufferSize, format: inputFormat) { buffer, when in
            if self.CONFIG.activateAudioClassificationSensor {
                self.analysisQueue.async {
                    self.streamAnalyzer.analyze(buffer, atAudioFramePosition: when.sampleTime)
                }
            }

            if self.CONFIG.activateAmbientNoiseSensor {
                if let audioData = buffer.floatChannelData?[0] {
                    let rms = SignalProcessing.rms(data: audioData, frameLength: UInt(buffer.frameLength))
                    let db = SignalProcessing.db(from: rms)

                    DispatchQueue.main.async {
                        guard !db.isInfinite else { return }

                        let now = Date()
                        let d = AmbientNoiseData(
                            timestamp: Int64(now.timeIntervalSince1970 * 1000),
                            db: Double(db),
                            label: self.CONFIG.label
                        )

                        if let engine = self.ambientNoiseSubSensor?.dbEngine {
                            engine.save([d])
                        }

                        if let observer = self.CONFIG.sensorObserver {
                            observer.onAmbientNoiseChanged(data: d)
                        }

                        if self.CONFIG.debug {
                            print(AmbientNoiseSensor.TAG, now, db)
                        }

                        self.notificationCenter.post(name: .actionAwareAmbientNoise, object: self)

                        self.decibels.append(DecibelPoint(date: now, value: Double(db)))
                        if self.decibels.count > 100 {
                            self.decibels.removeFirst()
                        }
                    }
                }
            }
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            if CONFIG.debug { print(AmbientNoiseSensor.TAG, "AVAudioEngine start error:", error) }
        }
    }

    private func applyPreferredInput(_ audioSession: AVAudioSession) throws {
        guard CONFIG.preferredInputUID.isEmpty == false,
              let preferredInput = audioSession.availableInputs?.first(where: { $0.uid == CONFIG.preferredInputUID }) else {
            return
        }
        try audioSession.setPreferredInput(preferredInput)
    }

    private func updateCurrentMicrophoneInfo() {
        let input = AVAudioSession.sharedInstance().currentRoute.inputs.first
        CONFIG.currentInputUID = input?.uid ?? ""
        CONFIG.currentInputName = input?.portName ?? ""
        CONFIG.currentInputPortType = input?.portType.rawValue ?? ""
    }

    // MARK: Private — stop

    private func stopAudioProcessing() {
        audioEngine.stop()
        audioEngine.disconnectNodeOutput(audioEngine.inputNode)
        audioEngine.inputNode.removeTap(onBus: CONFIG.onBus)
        audioEngine.reset()
        isReadySessionCategory = false
        if CONFIG.debug { print(AmbientNoiseSensor.TAG, "Sensor stopped.") }
    }

    // MARK: Interruption handling

    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if !isSuspended {
                isSuspended = true
                stop()
            }
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && isSuspended {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.start()
                    }
                    isSuspended = false
                }
            }
        @unknown default:
            break
        }
    }
}

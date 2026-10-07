//
//  Dictation.swift
//  Dex
//
//  Created by Prateek Prakash on 10/7/26.
//

import AVFoundation
import Speech
import SwiftUI

/// Speech to text for the message box, with the loudness the waveform
/// draws. On the phone when the recognizer can (Apple's servers otherwise,
/// as with the keyboard's dictation). Apple ends a recognition task after
/// about a minute, so a long recording runs as several, joined.
@MainActor
final class Dictation: ObservableObject {
    enum State: Equatable {
        case idle, starting, recording
    }

    @Published private(set) var state: State = .idle
    /// Everything heard this recording, punctuated.
    @Published private(set) var transcript: String = ""
    /// Recent loudness, oldest first, 0 to 1, one per `sampleInterval`.
    @Published private(set) var levels: [CGFloat] = []
    /// When the newest level arrived; the waveform slides between samples.
    private(set) var lastSample = Date()
    /// Why the last recording couldn't start or stopped early.
    @Published var error: String?

    static let sampleInterval: TimeInterval = 0.06
    /// More than any screen shows.
    static let maxLevels = 120

    private let engine = AVAudioEngine()
    private let sink = AudioSink()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    /// Text from this recording's earlier, finished tasks and utterances.
    private var committed = ""
    /// The current utterance as last heard.
    private var partial = ""
    /// Bumped per task and on stop, so late callbacks from an old task are ignored.
    private var generation = 0
    /// Tasks in a row that failed at once, hearing nothing: a recognizer
    /// that can't work. A long pause also ends a task, but not at once.
    private var emptyTasks = 0
    private var taskStarted = Date()
    private var meterTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// True from taking the audio session until giving it back; stopping
    /// touches the microphone and session only then.
    private var holdsAudio = false

    var isActive: Bool { state != .idle }

    /// Dex's audio outside a recording: mixes with other apps, so a haptic
    /// or anything else of Dex's never pauses what they're playing. Set at
    /// launch and again after every recording.
    nonisolated static func useAmbientAudio() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
    }

    func start() async {
        guard state == .idle else { return }
        state = .starting
        error = nil
        transcript = ""
        committed = ""
        partial = ""
        levels = []
        emptyTasks = 0
        // Cancel or leaving the screen while a permission prompt is up ends
        // this start: it must not go on to open the microphone.
        let attempt = generation
        let microphone = await Self.microphoneAllowed()
        guard attempt == generation, state == .starting else { return }
        guard microphone else {
            state = .idle
            error = "Microphone access is off. Turn it on for Dex in Settings."
            return
        }
        let speech = await Self.speechAllowed()
        guard attempt == generation, state == .starting else { return }
        guard speech else {
            state = .idle
            error = "Speech recognition is off. Turn it on for Dex in Settings."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            state = .idle
            error = "Speech recognition isn't available right now."
            return
        }
        self.recognizer = recognizer
        do {
            let session = AVAudioSession.sharedInstance()
            holdsAudio = true
            // Recording pauses other apps' audio; it resumes when we let go.
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            // No usable input (during a call, say): installing a tap on it
            // raises an exception no catch can stop.
            guard format.sampleRate > 0, format.channelCount > 0 else {
                finish()
                error = "The microphone isn't available right now."
                return
            }
            let sink = sink
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                sink.take(buffer)
            }
            engine.prepare()
            try engine.start()
        } catch {
            finish()
            self.error = "The microphone couldn't start."
            return
        }
        startTask()
        meterTimer = Timer.scheduledTimer(withTimeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleLevel() }
        }
        // A call, Siri or AirPods coming or going stops the engine under us:
        // end the recording, keeping its words, rather than show a dead one.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            },
        ]
        state = .recording
    }

    /// Stops listening; the words heard so far stay.
    func stop() {
        finish()
    }

    private func finish() {
        generation += 1
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        meterTimer?.invalidate()
        meterTimer = nil
        sink.setRequest(nil)
        task?.cancel()
        task = nil
        // Never started: the microphone and session were never touched, and
        // touching them now would interrupt other apps' audio.
        if holdsAudio {
            holdsAudio = false
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            Self.useAmbientAudio()
        }
        state = .idle
    }

    private func startTask() {
        guard let recognizer else { return }
        generation += 1
        let current = generation
        taskStarted = Date()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        sink.setRequest(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.heard(text, isFinal: isFinal || failed, generation: current)
            }
        }
    }

    private func heard(_ text: String?, isFinal: Bool, generation current: Int) {
        guard current == generation, state != .idle else { return }
        if let text, !text.isEmpty {
            // After a pause the recognizer may start a fresh transcription
            // without ending the task: keep the sentence before it.
            // The earlier sentence never got its final punctuation: close it.
            if Self.isRestart(previous: partial, next: text) {
                committed = Self.joined(committed, Self.closed(partial))
            }
            partial = text
            transcript = Self.joined(committed, Self.continuing(text, after: committed))
            emptyTasks = 0
        }
        guard isFinal else { return }
        // The task ended (its time limit, or a pause it took as the end):
        // keep what it heard and listen on with a new one.
        let failedAtOnce = (text?.isEmpty ?? true) && Date().timeIntervalSince(taskStarted) < 1
        emptyTasks = failedAtOnce ? emptyTasks + 1 : 0
        guard emptyTasks < 3 else {
            finish()
            error = "Speech recognition stopped working. Try again."
            return
        }
        committed = Self.closed(transcript)
        partial = ""
        startTask()
    }

    /// Words that always open a question.
    private static let questionWords: Set<String> = ["who", "what", "when", "where", "why", "how", "which", "whose"]
    /// Helper verbs open a question only before a subject ("can you…");
    /// before anything else they're a command ("do it now").
    private static let helperVerbs: Set<String> = [
        "is", "are", "am", "was", "were", "do", "does", "did", "can", "could", "would", "should",
        "will", "shall", "may", "might", "have", "has", "had", "isn't", "aren't", "don't",
        "doesn't", "didn't", "can't", "won't", "wouldn't", "shouldn't", "couldn't",
    ]
    private static let subjects: Set<String> = [
        "i", "you", "we", "they", "he", "she", "it", "this", "that", "these", "those", "there",
        "my", "your", "our", "their", "his", "her", "its", "the", "a", "an", "anyone", "someone", "everyone",
    ]

    /// A finished sentence with its ending: kept if it has one, a trailing
    /// comma or colon replaced, otherwise "?" when it opens like a question
    /// (a wh-word, or a helper verb then a subject) and "." when not.
    nonisolated static func closed(_ sentence: String) -> String {
        var text = sentence.trimmingCharacters(in: .whitespaces)
        guard let last = text.last else { return text }
        if ".?!…".contains(last) { return text }
        if ",;:".contains(last) { text.removeLast() }
        let words = text.split(whereSeparator: \.isWhitespace).prefix(2)
            .map { $0.lowercased().filter { $0.isLetter || $0 == "'" } }
        let first = words.first ?? ""
        let second = words.count > 1 ? words[1] : ""
        // "Do it", "Don't do that": with "do", these are objects, not subjects.
        let objects: Set<String> = ["do", "don't"].contains(first) ? ["it", "this", "that", "these", "those"] : []
        let isQuestion = questionWords.contains(first)
            || (helperVerbs.contains(first) && subjects.contains(second) && !objects.contains(second))
        return text + (isQuestion ? "?" : ".")
    }

    /// `text` capitalized when it starts a new sentence after `before`.
    nonisolated static func continuing(_ text: String, after before: String) -> String {
        guard let last = before.trimmingCharacters(in: .whitespaces).last, ".?!…".contains(last),
              let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// Whether `next` starts a new utterance rather than revising `previous`.
    /// Recognition rewrites as it hears more, the first word included
    /// ("Write the code" to "Right, the code is done"), but a revision keeps
    /// most of what was there. So a restart is either text less than half as
    /// long (a fresh start, even one opening with the same word), or a new
    /// first word with none of the old words after it: neither the old second
    /// word nor, for a lone word, anything as long.
    nonisolated static func isRestart(previous: String, next: String) -> Bool {
        func words(_ text: String) -> [String] {
            text.split(whereSeparator: \.isWhitespace)
                .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
                .filter { !$0.isEmpty }
        }
        let before = words(previous)
        let after = words(next)
        guard !before.isEmpty, !after.isEmpty else { return false }
        if next.count * 2 < previous.count { return true }
        guard before[0] != after[0] else { return false }
        if before.count >= 2 { return !after.dropFirst().prefix(2).contains(before[1]) }
        return next.count <= previous.count
    }

    private func sampleLevel() {
        levels.append(Self.level(rms: sink.takePeak()))
        if levels.count > Self.maxLevels { levels.removeFirst(levels.count - Self.maxLevels) }
        lastSample = Date()
    }

    /// Loudness on a 0 to 1 scale: -50 dB and below is silence, -20 dB (a
    /// clear voice at arm's length) and louder is full height.
    nonisolated static func level(rms: Float) -> CGFloat {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return CGFloat(min(max((decibels + 50) / 30, 0), 1))
    }

    /// Two runs of text joined with one space between.
    nonisolated static func joined(_ first: String, _ second: String) -> String {
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        if first.last?.isWhitespace == true || second.first?.isWhitespace == true { return first + second }
        return first + " " + second
    }

    private static func microphoneAllowed() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    private static func speechAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

/// Receives audio on the audio thread: feeds it to the recognition request
/// and keeps the loudest moment since the last sample.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var peak: Float = 0

    func setRequest(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request?.endAudio()
        self.request = request
        lock.unlock()
    }

    func take(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.rms(buffer)
        lock.lock()
        request?.append(buffer)
        peak = max(peak, rms)
        lock.unlock()
    }

    func takePeak() -> Float {
        lock.lock()
        defer { peak = 0; lock.unlock() }
        return peak
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += samples[index] * samples[index]
        }
        return (sum / Float(buffer.frameLength)).squareRoot()
    }
}

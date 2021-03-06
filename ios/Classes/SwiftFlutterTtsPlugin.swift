import Flutter
import UIKit
import AVFoundation

public class SwiftFlutterTtsPlugin: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate {
    final var iosAudioCategoryKey = "iosAudioCategoryKey"
    final var iosAudioCategoryOptionsKey = "iosAudioCategoryOptionsKey"
    
    var synthesizer : AVSpeechSynthesizer?;
    var language: String = AVSpeechSynthesisVoice.currentLanguageCode()
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    var languages = Set<String>()
    var volume: Float = 1.0
    var pitch: Float = 1.0
    var voice: AVSpeechSynthesisVoice?
    
    var channel = FlutterMethodChannel()
    lazy var audioSession = AVAudioSession.sharedInstance()
    
    init(channel: FlutterMethodChannel) {
        super.init()
        self.channel = channel
        
        // Get all possible languages
        setLanguages()
        
        // Allow audio playback when the Ring/Silent switch is set to silent
        do {
            try audioSession.setCategory(.playAndRecord, options: [.defaultToSpeaker])
        } catch {
            print(error)
        }
    }
    
    private func initSynthesizer() {
        self.synthesizer = AVSpeechSynthesizer()
        self.synthesizer!.delegate = self
    }
    
    private func setLanguages() {
        for voice in AVSpeechSynthesisVoice.speechVoices(){
            let language : String = voice.language
            
            self.languages.insert(language)
        }
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_tts", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterTtsPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "speak":
            let text: String = call.arguments as! String
            self.speak(text: text, result: result)
            break
        case "synthesizeToFile":
            guard let args = call.arguments as? [String: Any] else {
                result("iOS could not recognize flutter arguments in method: (sendParams)")
                return
            }
            let text = args["text"] as! String
            let fileName = args["fileName"] as! String
            self.synthesizeToFile(text: text, fileName: fileName, result: result)
            break
        case "pause":
            self.pause(result: result)
            break
        case "setLanguage":
            let language: String = call.arguments as! String
            self.setLanguage(language: language, result: result)
            break
        case "setSpeechRate":
            let rate: Double = call.arguments as! Double
            self.setRate(rate: Float(rate))
            result(1)
            break
        case "setVolume":
            let volume: Double = call.arguments as! Double
            self.setVolume(volume: Float(volume), result: result)
            break
        case "setPitch":
            let pitch: Double = call.arguments as! Double
            self.setPitch(pitch: Float(pitch), result: result)
            break
        case "stop":
            self.stop()
            result(1)
            break
        case "getLanguages":
            self.getLanguages(result: result)
            break
        case "getSpeechRateValidRange":
            self.getSpeechRateValidRange(result: result)
            break
        case "isLanguageAvailable":
            let language: String = call.arguments as! String
            self.isLanguageAvailable(language: language, result: result)
            break
        case "getVoices":
            self.getVoices(result: result)
            break
        case "setVoice":
            let voiceName = call.arguments as! String
            self.setVoice(voiceName: voiceName, result: result)
            break
        case "setSharedInstance":
            let sharedInstance = call.arguments as! Bool
            self.setSharedInstance(sharedInstance: sharedInstance, result: result)
            break
        case "setIosAudioCategory":
            guard let args = call.arguments as? [String: Any] else {
                result("iOS could not recognize flutter arguments in method: (sendParams)")
                return
            }
            let audioCategory = args["iosAudioCategoryKey"] as? String
            let audioOptions = args[iosAudioCategoryOptionsKey] as? Array<String>
            self.setAudioCategory(audioCategory: audioCategory, audioOptions: audioOptions, result: result)
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func speak(text: String, result: FlutterResult) {
        do {
            defer {
                disableAVSession()
            }
            
            if let synthesizer = self.synthesizer
            {
                if(synthesizer.isPaused) {
                    if (synthesizer.continueSpeaking()) {
                        result(1)
                    } else {
                        result(0)

                    }
                    return
                } else {
                    synthesizer.stopSpeaking(at: AVSpeechBoundary.immediate);
                }
            }
            
            do {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, mode: .default, options: .defaultToSpeaker)
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                print("audioSession properties weren't set because of an error.")
            }
            
            self.initSynthesizer();
            let utterance = AVSpeechUtterance(string: text)
            if self.voice != nil {
                utterance.voice = self.voice!
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: self.language)
            }
            utterance.rate = self.rate
            utterance.volume = self.volume
            utterance.pitchMultiplier = self.pitch
        
            self.synthesizer?.speak(utterance)
            
            result(1)
        }
    }
    
    private func disableAVSession() {
        print("disabling AV session")
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("audioSession properties weren't disable.")
        }
    }
    
    private func synthesizeToFile(text: String, fileName: String, result: FlutterResult) {
        var output: AVAudioFile?
        var failed = false
        let utterance = AVSpeechUtterance(string: text)
        
        if #available(iOS 13.0, *) {
            self.initSynthesizer();
            
            self.synthesizer!.write(utterance) { (buffer: AVAudioBuffer) in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    NSLog("unknow buffer type: \(buffer)")
                    failed = true
                    return
                }
                print(pcmBuffer.format)
                if pcmBuffer.frameLength == 0 {
                    // finished
                } else {
                    // append buffer to file
                    let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(fileName)
                    NSLog("Saving utterance to file: \(fileURL.absoluteString)")
                    
                    if output == nil {
                        do {
                            output = try AVAudioFile(
                                forWriting: fileURL,
                                settings: pcmBuffer.format.settings,
                                commonFormat: .pcmFormatInt16,
                                interleaved: false)
                        } catch {
                            NSLog(error.localizedDescription)
                            failed = true
                            return
                        }
                    }
                    
                    try! output!.write(from: pcmBuffer)
                }
            }
        } else {
            result("Unsupported iOS version")
        }
        if failed {
            result(0)
        }
        result(1)
    }
    
    private func pause(result: FlutterResult) {
        if let synthesizer = self.synthesizer {
            if (synthesizer.pauseSpeaking(at: AVSpeechBoundary.word)) {
                result(1)
            } else {
                result(0)
            }
        } else {
            result(0)
        }
    }
    
    private func setLanguage(language: String, result: FlutterResult) {
        if !(self.languages.contains(where: {$0.range(of: language, options: [.caseInsensitive, .anchored]) != nil})) {
            result(0)
        } else {
            self.language = language
            self.voice = nil
            result(1)
        }
    }
    
    private func setRate(rate: Float) {
        self.rate = rate
    }
    
    private func setVolume(volume: Float, result: FlutterResult) {
        if (volume >= 0.0 && volume <= 1.0) {
            self.volume = volume
            result(1)
        } else {
            result(0)
        }
    }
    
    private func setPitch(pitch: Float, result: FlutterResult) {
        if (volume >= 0.5 && volume <= 2.0) {
            self.pitch = pitch
            result(1)
        } else {
            result(0)
        }
    }
    
    private func setSharedInstance(sharedInstance: Bool, result: FlutterResult) {
        do {
            try AVAudioSession.sharedInstance().setActive(sharedInstance)
            result(1)
        } catch {
            result(0)
        }
    }
    
    private func setAudioCategory(audioCategory: String?, audioOptions: Array<String>?, result: FlutterResult){
        let category: AVAudioSession.Category = AudioCategory(rawValue: audioCategory ?? "")?.toAVAudioSessionCategory() ?? audioSession.category
        let options: AVAudioSession.CategoryOptions = audioOptions?.reduce([], { (result, option) -> AVAudioSession.CategoryOptions in
            return result.union(AudioCategoryOptions(rawValue: option)?.toAVAudioSessionCategoryOptions() ?? [])
        }) ?? []
        
        do {
            try audioSession.setCategory(category, options: options)
            result(1)
        } catch {
            print(error)
            result(0)
        }
    }
    
    private func stop() {
        self.synthesizer?.stopSpeaking(at: AVSpeechBoundary.immediate)
    }
    
    private func getLanguages(result: FlutterResult) {
        result(Array(self.languages))
    }
    
    private func getSpeechRateValidRange(result: FlutterResult) {
        let validSpeechRateRange: [String:String] = [
            "min": String(AVSpeechUtteranceMinimumSpeechRate),
            "normal": String(AVSpeechUtteranceDefaultSpeechRate),
            "max": String(AVSpeechUtteranceMaximumSpeechRate),
            "platform": "ios"
        ]
        result(validSpeechRateRange)
    }
    
    private func isLanguageAvailable(language: String, result: FlutterResult) {
        var isAvailable: Bool = false
        if (self.languages.contains(where: {$0.range(of: language, options: [.caseInsensitive, .anchored]) != nil})) {
            isAvailable = true
        }
        result(isAvailable);
    }
    
    private func getVoices(result: FlutterResult) {
        if #available(iOS 9.0, *) {
            let voices = NSMutableArray()
            for voice in AVSpeechSynthesisVoice.speechVoices() {
                voices.add(voice.name)
            }
            result(voices)
        } else {
            // Since voice selection is not supported below iOS 9, make voice getter and setter
            // have the same bahavior as language selection.
            getLanguages(result: result)
        }
    }
    
    private func setVoice(voiceName: String, result: FlutterResult) {
        if #available(iOS 9.0, *) {
            if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.name == voiceName }) {
                self.voice = voice
                self.language = voice.language
                result(1)
                return
            }
            result(0)
        } else {
            setLanguage(language: voiceName, result: result)
        }
    }
    
    private func shouldDeactivateAndNotifyOthers(_ session: AVAudioSession) -> Bool {
        var options: AVAudioSession.CategoryOptions = .duckOthers
        if #available(iOS 9.0, *) {
            options.insert(.interruptSpokenAudioAndMixWithOthers)
        }
        options.remove(.mixWithOthers)
        
        return !options.isDisjoint(with: session.categoryOptions)
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if shouldDeactivateAndNotifyOthers(audioSession) {
            do {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print(error)
            }
        }
        self.channel.invokeMethod("speak.onComplete", arguments: nil)
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        self.channel.invokeMethod("speak.onStart", arguments: nil)
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        self.channel.invokeMethod("speak.onPause", arguments: nil)
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        self.channel.invokeMethod("speak.onContinue", arguments: nil)
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        self.channel.invokeMethod("speak.onCancel", arguments: nil)
    }
    
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let nsWord = utterance.speechString as NSString
        let data: [String:String] = [
            "text": utterance.speechString,
            "start": String(characterRange.location),
            "end": String(characterRange.location + characterRange.length),
            "word": nsWord.substring(with: characterRange)
        ]
        self.channel.invokeMethod("speak.onProgress", arguments: data)
    }
    
}

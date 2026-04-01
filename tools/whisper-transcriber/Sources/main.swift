import Foundation
import FluidAudio

// Usage: whisper-transcriber <audio-file-path> [--progress] [--speakers]
// Output: JSON array of word objects to stdout
// Progress: lines like "PROGRESS:<fraction>:<message>" to stderr when --progress is set
// Uses NVIDIA Parakeet TDT 0.6B v2 via FluidAudio (fast, on-device)
// Speaker diarization via FluidAudio OfflineDiarizerManager (pyannote-based)

func reportProgress(_ fraction: Double, _ message: String) {
    let line = "PROGRESS:\(fraction):\(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

func printError(_ message: String) {
    FileHandle.standardError.write("ERROR:\(message)\n".data(using: .utf8)!)
}

let args = CommandLine.arguments

guard args.count >= 2 else {
    printError("Usage: whisper-transcriber <audio-file> [--progress] [--speakers]")
    exit(1)
}

let audioPath = args[1]
let showProgress = args.contains("--progress")
let detectSpeakers = args.contains("--speakers")

guard FileManager.default.fileExists(atPath: audioPath) else {
    printError("File not found: \(audioPath)")
    exit(1)
}

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0

Task {
    do {
        if showProgress { reportProgress(0.05, "Downloading Parakeet model...") }

        let models = try await AsrModels.downloadAndLoad(version: .v2)

        if showProgress { reportProgress(0.20, "Initializing Parakeet...") }

        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)

        if showProgress { reportProgress(0.30, "Transcribing audio...") }

        let audioURL = URL(fileURLWithPath: audioPath)
        let result = try await manager.transcribe(audioURL, source: .system)

        if showProgress { reportProgress(0.70, "Processing \(result.text.split(separator: " ").count) words...") }

        // Run speaker diarization if requested
        var speakerSegments: [TimedSpeakerSegment] = []
        if detectSpeakers {
            if showProgress { reportProgress(0.72, "Preparing speaker detection models...") }
            do {
                // Configure diarization with lower clustering threshold for better
                // speaker separation (default 0.6 tends to merge speakers in interviews)
                var config = OfflineDiarizerConfig()
                config.clustering.threshold = 0.45
                config.clustering.minSpeakers = 2
                config.segmentation.stepRatio = 0.1  // finer resolution

                let diarizer = OfflineDiarizerManager(config: config)
                try await diarizer.prepareModels()

                if showProgress { reportProgress(0.78, "Detecting speakers...") }

                let diarResult = try await diarizer.process(audioURL)
                speakerSegments = diarResult.segments
                let uniqueSpeakers = Set(speakerSegments.map { $0.speakerId })
                if showProgress {
                    reportProgress(0.88, "Found \(uniqueSpeakers.count) speakers")
                }
            } catch {
                // Diarization failed — continue without speakers
                if showProgress { reportProgress(0.88, "Speaker detection failed: \(error.localizedDescription)") }
                printError("Diarization failed: \(error.localizedDescription)")
            }
        }

        if showProgress { reportProgress(0.90, "Building word list...") }

        // Build word list from token timings
        var words: [[String: Any]] = []

        if let tokenTimings = result.tokenTimings {
            // Merge sub-word tokens into whole words (Parakeet returns sub-word tokens)
            let textWords = result.text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var tokenIndex = 0

            for textWord in textWords {
                var accumulated = ""
                var startTime: Float?
                var endTime: Float = 0
                var minConfidence: Float = 1.0

                while tokenIndex < tokenTimings.count {
                    let timing = tokenTimings[tokenIndex]
                    let token = timing.token.trimmingCharacters(in: .whitespacesAndNewlines)
                    tokenIndex += 1

                    if token.isEmpty { continue }

                    if startTime == nil {
                        startTime = Float(timing.startTime)
                    }
                    endTime = Float(timing.endTime)
                    minConfidence = min(minConfidence, timing.confidence)
                    accumulated += token

                    if accumulated == textWord || accumulated.count >= textWord.count {
                        break
                    }
                }

                let trimmed = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let start = startTime else { continue }

                // Find speaker for this word by time overlap
                var speaker = "Unknown"
                if !speakerSegments.isEmpty {
                    let wordMid = (start + endTime) / 2.0
                    for seg in speakerSegments {
                        if wordMid >= seg.startTimeSeconds && wordMid <= seg.endTimeSeconds {
                            speaker = seg.speakerId
                            break
                        }
                    }
                }

                var wordDict: [String: Any] = [
                    "word": trimmed,
                    "startTime": start,
                    "endTime": endTime,
                    "confidence": minConfidence,
                ]
                if speaker != "Unknown" {
                    wordDict["speaker"] = speaker
                }
                words.append(wordDict)
            }
        } else {
            // Fallback: single word for the whole text
            words.append([
                "word": result.text,
                "startTime": Float(0),
                "endTime": Float(result.duration),
                "confidence": result.confidence,
            ])
        }

        if showProgress { reportProgress(1.0, "Done — \(words.count) words") }

        // Output JSON to stdout
        let jsonData = try JSONSerialization.data(withJSONObject: words, options: [.sortedKeys])
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }

    } catch {
        printError("Transcription failed: \(error.localizedDescription)")
        exitCode = 1
    }
    semaphore.signal()
}

semaphore.wait()
exit(exitCode)

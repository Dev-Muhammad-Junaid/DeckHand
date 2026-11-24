//
//  OCRResultView.swift
//  DeckHandiOS
//
//  The capture sheet's read-text step (UX-009): on-device Vision text
//  recognition of the capture (full screen, region, window or annotated),
//  shown as selectable text on a raised navy panel. No Mac round trip.
//
//  The host (`ScreenshotPreviewView`) runs `TextReader.read(_:)` and owns
//  the state, so the header strip can count lines and the dock can copy;
//  this view only draws the state. Read text is a step inside the one
//  capture sheet, not a sheet of its own.
//

import SwiftUI
import UIKit
@preconcurrency import Vision

/// Where text recognition is.
enum TextReadState: Equatable {
    case reading
    case ready(text: String, lineCount: Int)
    case empty
    case failed(String)

    var text: String? {
        if case let .ready(text, _) = self { return text }
        return nil
    }

    /// The header strip for this state.
    var strip: CaptureStrip {
        switch self {
        case .reading:
            CaptureSheetChrome.readTextStrip(lines: nil, characters: nil)
        case let .ready(text, lines):
            CaptureSheetChrome.readTextStrip(lines: lines, characters: text.count)
        case .empty:
            CaptureSheetChrome.readTextStrip(lines: 0, characters: 0)
        case .failed:
            CaptureStrip(items: ["READ TEXT", "FAILED"], spoken: "Reading text failed")
        }
    }
}

struct OCRResultView: View {
    let state: TextReadState
    var onRetry: () -> Void = {}

    var body: some View {
        Group {
            switch state {
            case .reading:
                VStack(spacing: PixelHandTheme.Space.lg) {
                    DotWave(label: "Reading text")
                    DotMatrixText("READING", pitch: 1.6, label: "Reading text")
                        .foregroundStyle(PixelHandTheme.Brand.phosphor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .ready(text, _):
                ScrollView {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PixelHandTheme.Space.lg)
                }
                .scrollIndicators(.visible)
            case .empty:
                PHEmptyState(
                    glyph: PixelGlyphs.readText,
                    title: "No text found",
                    message: "Try a region around the words, or a sharper capture quality in Settings."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                PHEmptyState(
                    glyph: PixelGlyphs.readText,
                    title: "Couldn’t read text",
                    message: message,
                    primaryTitle: "Try again",
                    primaryAction: onRetry
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PixelHandTheme.Brand.screenRaised, in: RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous)
                .strokeBorder(PixelHandTheme.Brand.tileStroke, lineWidth: PixelHandTheme.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: PixelHandTheme.Radius.card, style: .continuous))
        .padding(.horizontal, PixelHandTheme.Space.lg)
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}

// MARK: - Vision

enum TextReader {
    /// Recognises the text in `image` off the main actor.
    static func read(_ image: UIImage) async -> TextReadState {
        guard let cgImage = image.cgImage else {
            return .failed("The capture’s pixels couldn’t be read.")
        }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return TextReadState.failed(error.localizedDescription)
            }
            guard let observations = request.results, !observations.isEmpty else {
                return TextReadState.empty
            }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let joined = lines.joined(separator: "\n")
            return joined.isEmpty ? TextReadState.empty : TextReadState.ready(text: joined, lineCount: lines.count)
        }.value
    }
}

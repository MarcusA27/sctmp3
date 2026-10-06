import SwiftUI
import AppKit
import UniformTypeIdentifiers

let scOrange = Color(red: 1.0, green: 0.33, blue: 0.0)

struct ContentView: View {
    @StateObject private var model = AppModel()
    @FocusState private var inputFocused: Bool

    private var intensity: Double {
        let active = model.items.filter {
            switch $0.state { case .downloading, .converting: return true; default: return false }
        }
        if active.isEmpty { return model.dropTargeted ? 0.5 : 0.0 }
        return 1.0
    }

    private var aggregateProgress: Double? {
        let fracs = model.items.compactMap { item -> Double? in
            if case .downloading(let p) = item.state { return p }
            if case .converting = item.state { return 0.98 }
            return nil
        }
        guard !fracs.isEmpty else { return nil }
        return fracs.reduce(0, +) / Double(fracs.count)
    }

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .ignoresSafeArea()
            Background(intensity: intensity)

            GlassEffectContainer(spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        Waveform(intensity: intensity, progress: aggregateProgress)
                            .padding(.vertical, 2)
                        inputBar

                        if !model.items.isEmpty {
                            queueSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 30)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .background(WindowConfigurator())
        .onAppear { model.peekClipboard() }
        .onDrop(of: [.url, .text], isTargeted: $model.dropTargeted) { providers in
            handleDrop(providers); return true
        }
        .overlay(alignment: .topTrailing) {
            loginMenu
                .padding(.top, 12)
                .padding(.trailing, 14)
                .ignoresSafeArea()
        }
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(scOrange.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.dropTargeted)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(scOrange)
                    .shadow(color: scOrange.opacity(0.6), radius: 8)
                Text("sctmp3")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
            Text("SoundCloud → MP3")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("", text: $model.input, prompt:
                    Text("Paste SoundCloud link(s)…").foregroundColor(.white.opacity(0.35)))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .font(.system(size: 14))
                    .focused($inputFocused)
                    .onSubmit(model.submit)
                if !model.input.isEmpty {
                    Button { model.input = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.3))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassEffect(.regular, in: .capsule)

            DotArrowButton(enabled: !model.input.isEmpty, action: model.submit)
        }
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.items.contains(where: { !$0.isActive }) {
                HStack {
                    Spacer()
                    Button("Clear done", action: model.clearFinished)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            ForEach(model.items) { item in
                QueueRow(item: item, onReveal: reveal,
                         onChoose: { model.chooseAlternate(item.id, $0) })
            }
        }
    }

    private var loginMenu: some View {
        Menu {
            Button("No login") { model.cookieBrowser = "none" }
            Divider()
            Button("Chrome") { model.cookieBrowser = "chrome" }
            Button("Safari") { model.cookieBrowser = "safari" }
            Button("Firefox") { model.cookieBrowser = "firefox" }
            Button("Edge") { model.cookieBrowser = "edge" }
            Button("Brave") { model.cookieBrowser = "brave" }
        } label: {
            Image(systemName: model.cookieBrowser == "none"
                  ? "person.crop.circle" : "person.crop.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.white)
        .fixedSize()
    }

    // MARK: - Actions

    private func reveal(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: model.saveDir.path)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for p in providers {
            if p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let s = url?.absoluteString { Task { @MainActor in model.add([s]) } }
                }
            } else if p.canLoadObject(ofClass: String.self) {
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    if let s { Task { @MainActor in model.add(AppModel.parseURLs(s)) } }
                }
            }
        }
    }
}


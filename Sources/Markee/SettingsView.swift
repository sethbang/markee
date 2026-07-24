import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 460)
        .padding(20)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var installedEditors: [String] = []
    @State private var editorText: String = ""

    var body: some View {
        Form {
            Picker("Editor:", selection: $store.editorOverride) {
                Text("Auto-detect").tag("")
                ForEach(installedEditors, id: \.self) { Text($0).tag($0) }
                if !store.editorOverride.isEmpty && !installedEditors.contains(store.editorOverride) {
                    Text("\(store.editorOverride) (not found)").tag(store.editorOverride)
                }
            }
            TextField("Other editor command:", text: $editorText, prompt: Text("e.g. code, zed"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.editorOverride = editorText }

            Divider().padding(.vertical, 4)

            Toggle("Check for updates on launch", isOn: $store.updateCheckEnabled)
            Toggle("Float new windows on top", isOn: $store.defaultFloatOnTop)
        }
        .onAppear {
            editorText = store.editorOverride
            EditorLauncher.availableEditors { installedEditors = $0 }
        }
        .onChange(of: store.editorOverride) { editorText = $0 }
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            Picker("Theme:", selection: $store.themeOverride) {
                Text("System").tag(ThemeOverride.system)
                Text("Light").tag(ThemeOverride.light)
                Text("Dark").tag(ThemeOverride.dark)
            }
            .pickerStyle(.segmented)

            HStack {
                ColorPicker("Accent color:", selection: accentBinding, supportsOpacity: false)
                Button("Reset") { store.accentHex = "" }
                    .disabled(store.accentHex.isEmpty)
            }

            HStack {
                Text("Base font size:")
                Slider(value: $store.baseFontSize, in: SettingsStore.fontRange, step: 1)
                Text("\(Int(store.baseFontSize)) pt").monospacedDigit()
            }

            Divider().padding(.vertical, 4)

            HStack {
                Text("Custom CSS:")
                Text(store.customCSSPath.isEmpty ? "None"
                     : (store.customCSSPath as NSString).lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseCSS() }
                Button("Clear") { store.customCSSPath = "" }
                    .disabled(store.customCSSPath.isEmpty)
            }
        }
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { store.accentHex.isEmpty ? .accentColor : Color(hex: store.accentHex) },
            set: { store.accentHex = $0.toHex() }
        )
    }

    private func chooseCSS() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "css")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.customCSSPath = url.path
        }
    }
}

extension Color {
    init(hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r, g, b: Double
        if h.count == 3 {
            r = Double((v >> 8) & 0xF) / 15; g = Double((v >> 4) & 0xF) / 15; b = Double(v & 0xF) / 15
        } else {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b)
    }

    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

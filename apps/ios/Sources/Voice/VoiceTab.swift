import SwiftUI

struct VoiceTab: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(VoiceWakeManager.self) private var voiceWake
    @AppStorage("voiceWake.enabled") private var voiceWakeEnabled: Bool = false
    @AppStorage("talk.enabled") private var talkEnabled: Bool = false
    @AppStorage("talk.background.enabled") private var talkBackgroundEnabled: Bool = false
    @AppStorage(SpeechLanguageSetting.userDefaultsKey) private var speechLanguageRaw: String = SpeechLanguageSetting.english.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("Controls") {
                    Toggle("Voice Wake", isOn: self.$voiceWakeEnabled)
                    Toggle("Talk Mode", isOn: self.$talkEnabled)
                    Picker("Speech Language", selection: self.$speechLanguageRaw) {
                        ForEach(SpeechLanguageSetting.allCases) { language in
                            Text(language.displayName).tag(language.rawValue)
                        }
                    }
                    Text("Used for speech recognition and talk replies.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Background Listening", isOn: self.$talkBackgroundEnabled)
                }

                Section("Status") {
                    LabeledContent("Voice Wake", value: self.voiceWakeEnabled ? "Enabled" : "Disabled")
                    LabeledContent("Listener", value: self.voiceWake.isListening ? "Listening" : "Idle")
                    Text(self.voiceWake.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("Talk Mode", value: self.talkEnabled ? "Enabled" : "Disabled")
                }

                Section("Notes") {
                    let triggers = self.voiceWake.activeTriggerWords
                    Group {
                        if triggers.isEmpty {
                            Text("Add wake words in Settings.")
                        } else if triggers.count == 1 {
                            Text("Say “\(triggers[0]) …” to trigger.")
                        } else if triggers.count == 2 {
                            Text("Say “\(triggers[0]) …” or “\(triggers[1]) …” to trigger.")
                        } else {
                            Text("Say “\(triggers.joined(separator: " …”, “")) …” to trigger.")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Voice")
            .onChange(of: self.voiceWakeEnabled) { _, newValue in
                self.appModel.setVoiceWakeEnabled(newValue)
            }
            .onChange(of: self.talkEnabled) { _, newValue in
                self.appModel.setTalkEnabled(newValue)
            }
            .onChange(of: self.speechLanguageRaw) { _, newValue in
                guard let language = SpeechLanguageSetting(rawValue: newValue) else {
                    self.speechLanguageRaw = SpeechLanguageSetting.english.rawValue
                    return
                }
                self.appModel.updateSpeechLanguage(language)
            }
        }
    }
}

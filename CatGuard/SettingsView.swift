import KeyboardShortcuts
import SwiftUI

/// 设置窗口：编辑上锁快捷键。
///
/// `KeyboardShortcuts.Recorder` 需要键盘焦点，必须置于真实窗口中（不能塞进 NSMenu），
/// 故通过标准 SwiftUI `Settings { }` 场景承载。录制结果由库自动持久化。
struct SettingsView: View {
    var body: some View {
        Form {
            Section("快捷键") {
                KeyboardShortcuts.Recorder("上锁快捷键:", name: .lockNow)
            }
            Section {
                Button("恢复默认快捷键") {
                    KeyboardShortcuts.reset(.lockNow)
                }
            }
        }
        .padding()
        .frame(width: 360)
    }
}

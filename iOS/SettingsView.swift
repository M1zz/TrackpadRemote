//
//  SettingsView.swift
//  TrackpadRemote (iOS)
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: PadSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    slider(value: $settings.pointerSpeed,
                           range: PadSettings.pointerSpeedRange,
                           title: "속도",
                           low: "느리게",
                           high: "빠르게")

                    Toggle("가속", isOn: $settings.accelerationEnabled)
                } header: {
                    Text("포인터")
                } footer: {
                    Text("가속을 끄면 천천히 움직이든 빠르게 튕기든 같은 비율로 이동합니다. "
                         + "조준은 예측하기 쉬워지지만 화면을 가로지르려면 여러 번 쓸어야 합니다.")
                }

                Section {
                    slider(value: $settings.scrollSpeed,
                           range: PadSettings.scrollSpeedRange,
                           title: "속도",
                           low: "느리게",
                           high: "빠르게")

                    Toggle("자연스러운 방향", isOn: $settings.naturalScrolling)
                } header: {
                    Text("스크롤")
                } footer: {
                    Text("자연스러운 방향에서는 내용이 손가락을 따라옵니다. "
                         + "끄면 손가락과 반대로 움직입니다.")
                }

                Section {
                    Toggle("핀치로 확대/축소", isOn: $settings.pinchEnabled)

                    slider(value: $settings.pinchSensitivity,
                           range: PadSettings.sensitivityRange,
                           title: "민감도",
                           low: "둔하게",
                           high: "예민하게")
                    .disabled(!settings.pinchEnabled)
                } header: {
                    Text("두 손가락 확대")
                } footer: {
                    Text("끄면 두 손가락은 항상 스크롤로만 동작합니다. "
                         + "확대는 ⌘=/⌘- 단축키로 전달되므로 연속이 아니라 단계적입니다.")
                }

                Section {
                    Toggle("스와이프 사용", isOn: $settings.swipeEnabled)

                    slider(value: $settings.swipeSensitivity,
                           range: PadSettings.sensitivityRange,
                           title: "민감도",
                           low: "길게",
                           high: "짧게")
                    .disabled(!settings.swipeEnabled)
                } header: {
                    Text("세 손가락 스와이프")
                } footer: {
                    Text("위: Mission Control · 아래: App Exposé · 좌우: 스페이스 이동. "
                         + "Mac에서 해당 단축키(⌃↑ ⌃↓ ⌃← ⌃→)를 바꾸거나 껐다면 동작하지 않습니다.")
                }

                Section {
                    Button("기본값으로 되돌리기", role: .destructive) {
                        settings.resetToDefaults()
                    }
                    .disabled(settings.isDefault)
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    /// Slider with its ends labelled — a bare track gives no clue which way is
    /// faster, and the pad is being adjusted by feel, not by reading a number.
    private func slider(value: Binding<Double>,
                        range: ClosedRange<Double>,
                        title: String,
                        low: String,
                        high: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Slider(value: value, in: range) {
                Text(title)
            } minimumValueLabel: {
                Text(low).font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(high).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

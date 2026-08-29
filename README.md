# TrackpadRemote

iPhone을 Mac의 무선 트랙패드로 쓰는 앱. MultipeerConnectivity 기반, IP 입력 없이 자동 발견/연결.

## 구성

```
TrackpadRemote/
├── Shared/InputPacket.swift      # 양쪽 타깃 모두에 추가 (9바이트 바이너리 프로토콜)
├── iOS/                          # iPhone 클라이언트 (SwiftUI)
│   ├── TrackpadRemoteApp.swift
│   ├── ConnectionManager.swift   # MC browser + 패킷 전송
│   ├── TrackpadView.swift        # 터치 캡처 + 제스처
│   └── ContentView.swift
└── macOS/                        # Mac 서버 (메뉴바 앱)
    ├── TrackpadServerApp.swift
    ├── ServerManager.swift       # MC advertiser + 패킷 수신
    └── EventInjector.swift       # CGEvent 주입
```

## 빌드

`TrackpadRemote.xcodeproj`가 리포에 포함되어 있다. 열고 스킴을 골라 실행하면 된다.

| 스킴 | 타깃 | 최소 버전 | Bundle ID |
|---|---|---|---|
| `TrackpadRemote` | iPhone/iPad 앱 | iOS 17 | `com.hyunholee.TrackpadRemote` |
| `TrackpadServer` | Mac 메뉴바 앱 | macOS 14 | `com.hyunholee.TrackpadServer` |

`Shared/InputPacket.swift`는 두 타깃 모두에 들어가 있다.

```bash
open TrackpadRemote.xcodeproj
# 또는 CLI로
xcodebuild -scheme TrackpadServer  -destination 'platform=macOS' build
xcodebuild -scheme TrackpadRemote  -destination 'generic/platform=iOS Simulator' build
```

실기기에 설치하려면 각 타깃의 Signing & Capabilities에서 본인 Team을 지정한다
(또는 `project.yml`의 `DEVELOPMENT_TEAM`에 Team ID를 넣고 재생성).

### 프로젝트 파일 재생성 (XcodeGen)

`.xcodeproj`는 [XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 `project.yml`에서 생성한다.
빌드 설정·Info.plist 키·파일 추가는 **`project.yml`을 고치고** 아래를 실행할 것:

```bash
brew install xcodegen   # 최초 1회
xcodegen generate
```

Info.plist(`Resources/*-Info.plist`)도 `project.yml`에서 생성되므로 직접 편집하지 말 것.

### 서버 타깃의 제약

- **App Sandbox 비활성** (`Resources/TrackpadServer.entitlements`) — 샌드박스에서는 `CGEventPost`가 막힌다.
  그래서 Mac App Store 배포 불가 → Developer ID 서명 + notarization으로 직접 배포.
- `LSUIElement = YES` — Dock 아이콘 없는 메뉴바 전용 앱.

### 실행 순서

1. Mac에서 TrackpadServer 실행 → 손쉬운 사용(Accessibility) 권한 허용
   (System Settings → Privacy & Security → Accessibility)
2. iPhone에서 TrackpadRemote 실행 → 로컬 네트워크 권한 허용
3. 자동으로 발견/연결됨 (Mac이 1대면 자동 연결, 여러 대면 목록에서 선택)

## 제스처

| 제스처 | 동작 |
|---|---|
| 한 손가락 이동 | 커서 이동 (가속 적용) |
| 한 손가락 탭 | 좌클릭 (더블클릭 인식 지원) |
| 두 손가락 탭 | 우클릭 |
| 두 손가락 이동 | 스크롤 (natural) |
| 더블탭 후 홀드+이동 | 드래그 |

## 프로토콜

9바이트 고정: `[type: UInt8][dx: Float32 LE][dy: Float32 LE]`
- move/scroll → `.unreliable` (다음 델타가 이전 것을 대체하므로 유실 OK)
- click/drag → `.reliable` (절대 유실되면 안 됨)

## 알려진 한계 / 다음 단계 아이디어

- 키보드 입력 (CGEvent keyboard events 추가)
- 세 손가락 제스처 (Mission Control, 스와이프)
- 감도/가속 설정 UI
- 미러링 모드 (ScreenCaptureKit + Network.framework QUIC — MC 스트림은 대역폭이 불안정해서 비추)

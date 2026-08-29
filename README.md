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

## 매핑

패드는 트랙패드가 아니라 **디스플레이의 축소 모형**이다 (Wacom 태블릿 방식).
패드의 30% 지점을 누르면 커서가 화면의 30% 지점으로 **바로 점프**한다.
상대 이동·커서 가속은 없다.

- Mac이 연결 직후 데스크톱 크기를 보내고, 아이폰은 그 종횡비로 패드를 레터박싱한다.
  → 매핑이 늘어나거나 찌그러지지 않는다.
- 디스플레이 배치를 바꾸면 (`didChangeScreenParameters`) 새 크기를 다시 보낸다.
- 다중 모니터는 전체 데스크톱을 감싸는 사각형에 매핑된다. 모니터가 여러 대면
  패드가 아주 납작해진다.
- iOS 앱은 **가로 전용**이다. 가로 디스플레이의 축소 모형이라 세로는 의미가 없다.

## 제스처

| 제스처 | 동작 |
|---|---|
| 한 손가락 터치/이동 | 커서가 그 지점으로 이동 (절대 좌표) |
| 한 손가락 탭 | 좌클릭 |
| 빠르게 2·3연타 | 더블클릭 / 트리플클릭 |
| 두 손가락 탭 | 우클릭 |
| 두 손가락 이동 | 스크롤 (natural) |
| 더블탭 후 홀드+이동 | 드래그 |

연타 판정은 **아이폰에서** 한다 (0.3초 이내 + 44pt 이내). 판정 결과인 클릭 횟수를
패킷에 실어 보내고 Mac은 그걸 `mouseEventClickState`에 그대로 넣는다. 패킷 도착
시각으로 Mac이 다시 추측하지 않는다 — 무선 지터 때문에 더블클릭이 깨지던 지점이다.

## 프로토콜

9바이트 고정: `[type: UInt8][a: Float32 LE][b: Float32 LE]`

| type | 방향 | a, b |
|---|---|---|
| `moveAbsolute` | iPhone → Mac | 데스크톱 기준 0…1 정규화 좌표 |
| `leftClick` / `rightClick` | iPhone → Mac | a = 클릭 횟수 (1~3) |
| `scroll` | iPhone → Mac | 픽셀 델타 |
| `dragBegin` / `dragEnd` | iPhone → Mac | — |
| `screenInfo` | **Mac → iPhone** | 데스크톱 너비·높이 (pt) |

`moveAbsolute`/`scroll` → `.unreliable` (다음 위치가 이전 것을 대체하므로 유실 OK)
나머지 → `.reliable` (절대 유실되면 안 됨)

## 연결

한 번에 **1:1 페어링만** 허용한다. Mac은 두 번째 아이폰의 초대를 `.connected`
시점이 아니라 **수락 시점에** 거절하기 때문에, 두 대가 동시에 초대해도 둘 다
들어와서 커서를 다투는 경합이 없다. 수락 후 15초 안에 핸드셰이크가 끝나지 않으면
슬롯을 풀어준다.

## 알려진 한계 / 다음 단계 아이디어

- 키보드 입력 (CGEvent keyboard events 추가)
- 세 손가락 제스처 (Mission Control, 스와이프)
- 상대 이동 모드 토글 — 절대 매핑은 조준은 빠르지만 정밀 작업엔 불리하다
- 다중 모니터에서 매핑 대상 디스플레이 선택
- 미러링 모드 (ScreenCaptureKit + Network.framework QUIC — MC 스트림은 대역폭이 불안정해서 비추)

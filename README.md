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

### 접근성 권한이 자꾸 풀린다면

**서버 타깃은 반드시 안정적인 서명 identity로 빌드해야 한다.** ad-hoc 서명
(`Signature=adhoc`, `TeamIdentifier=not set`)이면 TCC가 접근성 권한을 바이너리의
**CDHash**에 묶는데, 이 해시는 빌드할 때마다 바뀐다. 결과가 고약하다 —
System Settings의 접근성 목록에는 TrackpadServer가 **켜진 채로 그대로 보이는데**
`AXIsProcessTrusted()`는 false를 돌려주고, 커서는 아무 말 없이 안 움직인다.

`project.yml`의 `DEVELOPMENT_TEAM`이 그래서 채워져 있다. Apple Development
인증서로 서명하면 designated requirement가 CDHash 대신 번들 ID + 인증서가 되어
재빌드를 견딘다:

```
designated => identifier "com.hyunholee.TrackpadServer" and anchor apple generic
              and certificate leaf[subject.CN] = "Apple Development: ..."
```

ad-hoc으로 빌드한 적이 있다면 낡은 항목이 남아 계속 실패하므로 한 번 지워야 한다:

```bash
tccutil reset Accessibility com.hyunholee.TrackpadServer
```

그 다음 앱을 다시 실행해 권한을 한 번만 주면 된다.

### 문제 진단

서버는 전 구간에 `os_log`를 남긴다:

```bash
log stream --predicate 'subsystem == "com.hyunholee.TrackpadServer"' --level debug
```

광고 시작, 초대 수락/거절, 연결, screenInfo 전송, 디코딩 실패 패킷, 데스크톱
좌표, 커서 이동 샘플, 모든 클릭이 찍힌다. 권한이 없으면 메뉴바 아이콘이 경고
삼각형으로 바뀐다.

### 서버 타깃의 제약

- **App Sandbox 비활성** (`Resources/TrackpadServer.entitlements`) — 샌드박스에서는 `CGEventPost`가 막힌다.
  그래서 Mac App Store 배포 불가 → Developer ID 서명 + notarization으로 직접 배포.
- `LSUIElement = YES` — Dock 아이콘 없는 메뉴바 전용 앱.

### 실행 순서

1. Mac에서 TrackpadServer 실행 (메뉴바에만 뜬다)
2. iPhone에서 TrackpadRemote 실행 → 로컬 네트워크 권한 허용
3. 자동으로 발견/연결됨 (Mac이 1대면 자동 연결, 여러 대면 목록에서 선택)
4. 접근성 권한이 없으면 **이 시점에** 요청한다 — 실행할 때가 아니라

접근성 프롬프트는 아이폰이 붙는 순간, 실행당 한 번만 뜬다. 권한이 이미 켜져
있으면 뜨지 않는다. 서버는 아이폰이 오기 전까지 아무것도 안 하므로 실행 시점에
묻는 것은 아직 필요하지도 않은 권한으로 사용자를 붙잡는 셈이다. 미리 주고 싶으면
메뉴바 메뉴에서 직접 열 수 있다.

## 움직임

진짜 트랙패드와 같은 **상대 이동**이다. 패드를 터치해도 커서는 그 자리에 그대로
있고, 손가락이 움직인 만큼만 원래 있던 위치에서 이동한다. 손가락을 떼었다
다시 올리면 그 지점이 새 기준점이 된다 — 매직 트랙패드와 동일하다.

- 아이폰은 이동량을 **패드 폭에 대한 비율**로 보낸다. Mac은 거기에 데스크톱 폭을
  곱한다. 기기 크기를 서로 몰라도 되고, 패드를 한 번 끝까지 쓸면 화면을 가로지른다.
- x·y **둘 다 폭으로** 나눈다. y를 높이로 나누면 패드와 화면의 종횡비가 어긋나는
  순간 대각선이 찌그러진다.
- 가속: 느린 이동은 gain 0.55(정밀 조준), 빠른 플릭은 2.6까지 올라간다.
  상수는 `TrackpadView`의 `minGain` / `maxGain` / `accelerationDivisor`.
- Mac은 커서 위치를 **자체적으로** 추적한다. `CGEvent`가 보고하는 위치는 빠른 주입을
  따라오지 못해서, 매 패킷마다 읽으면 움직임이 유실된다. 대신 0.4초 이상 쉬었다가
  들어오면 그때 실제 커서 위치로 다시 맞춘다 — 그 사이 실제 마우스를 썼을 수 있다.
- 커서는 항상 실재하는 디스플레이 안에 갇힌다. 크기가 다른 두 모니터 사이에는
  union 안이지만 어느 화면에도 속하지 않는 빈 구역이 생기므로, union이 아니라
  **가장 가까운 화면**으로 clamp한다.

패드는 여전히 데스크톱 종횡비로 레터박싱된다 (Mac이 연결 직후 `screenInfo`로 크기를
보낸다). 절대 매핑은 아니지만, 화면 모양을 그대로 보여주고 x·y gain을 맞춰준다.

## 제스처

| 제스처 | 동작 |
|---|---|
| 한 손가락 이동 | 움직인 만큼 커서 이동 (가속 적용) |
| 한 손가락 탭 | 좌클릭 |
| 빠르게 2·3연타 | 더블클릭 / 트리플클릭 |
| 두 손가락 탭 | 우클릭 |
| 두 손가락 이동 | 스크롤 (natural) |
| 더블탭 후 홀드+이동 | 드래그 |

손가락이 닿는 지점마다 확장하며 사라지는 원이 그려진다. 패드 쪽에는 커서가 없어서
터치가 읽혔는지 확인할 방법이 이것뿐이다. 두 손가락 우클릭이면 원도 두 개 그려진다.

연타 판정은 **아이폰에서** 한다 (0.3초 이내 + 44pt 이내). 판정 결과인 클릭 횟수를
패킷에 실어 보내고 Mac은 그걸 `mouseEventClickState`에 그대로 넣는다. 패킷 도착
시각으로 Mac이 다시 추측하지 않는다 — 무선 지터 때문에 더블클릭이 깨지던 지점이다.

## 프로토콜

9바이트 고정: `[type: UInt8][a: Float32 LE][b: Float32 LE]`

| type | 방향 | a, b |
|---|---|---|
| `moveRelative` | iPhone → Mac | 패드 폭 대비 이동 비율 |
| `leftClick` / `rightClick` | iPhone → Mac | a = 클릭 횟수 (1~3) |
| `scroll` | iPhone → Mac | 픽셀 델타 |
| `dragBegin` / `dragEnd` | iPhone → Mac | — |
| `screenInfo` | **Mac → iPhone** | 데스크톱 너비·높이 (pt) |

`moveRelative`/`scroll` → `.unreliable` (다음 델타가 곧 따라오므로 한두 개 유실 OK)
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

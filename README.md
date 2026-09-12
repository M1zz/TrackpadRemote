# TrackpadRemote

iPhone을 Mac의 무선 트랙패드로 쓰는 앱. MultipeerConnectivity 기반, IP 입력 없이 자동 발견/연결.

| 페이지 | 주소 |
|---|---|
| 다운로드 (iPhone 앱 + Mac 앱) | https://m1zz.github.io/TrackpadRemote/ |
| 지원 | https://m1zz.github.io/TrackpadRemote/support/ |
| 개인정보 처리방침 | https://m1zz.github.io/TrackpadRemote/privacy/ |

## 구성

```
TrackpadRemote/
├── Shared/
│   ├── InputPacket.swift         # 양쪽 타깃 모두에 추가 (9바이트 바이너리 프로토콜)
│   └── CompanionLinks.swift      # 다른 쪽 앱을 받는 페이지 주소
├── iOS/                          # iPhone 클라이언트 (SwiftUI)
│   ├── TrackpadRemoteApp.swift
│   ├── ConnectionManager.swift   # MC browser + 패킷 전송
│   ├── TrackpadView.swift        # 터치 캡처 + 제스처
│   └── ContentView.swift
├── macOS/                        # Mac 서버 (메뉴바 앱)
│   ├── TrackpadServerApp.swift
│   ├── ServerManager.swift       # MC advertiser + 패킷 수신
│   ├── EventInjector.swift       # CGEvent 주입
│   └── CompanionWindow.swift     # "iPhone 앱 받기" QR 창
└── docs/                         # GitHub Pages: 다운로드 · 지원 · 개인정보 처리방침
```

## 앱 두 개가 한 쌍이다

| 앱 | 기기 | 배포 |
|---|---|---|
| **TrackpadRemote** | iPhone | App Store |
| **TrackpadServer** | Mac (메뉴 막대) | GitHub Releases — 샌드박스를 켤 수 없어 Mac App Store 불가 |

한쪽만 설치하면 아무 일도 일어나지 않는다. 앱이 그걸 스스로 말하지 않으면 사용자는
고장난 줄 안다. 그래서 **양쪽 앱 모두 다른 쪽 앱을 받는 창구를 갖고 있다.**

- **iPhone → Mac**: Mac을 찾는 화면에 "Mac에도 앱이 필요해요" 카드, 설정에 "Mac 앱"
  섹션. 둘 다 공유 시트로 다운로드 링크를 보낸다 — AirDrop으로 Mac에 보내면 Mac
  브라우저에서 바로 열린다. 공유 시트에 `message:`를 넣지 않은 이유도 이것이다.
  글이 붙으면 AirDrop이 링크를 여는 대신 메모로 받는다.
- **Mac → iPhone**: 메뉴 막대 **Get the iPhone App…** 이 QR 코드 창을 연다. iPhone
  카메라로 찍으면 페이지가 열린다. 메뉴 막대 아이콘 하나로는 반쪽짜리 앱이라는 걸
  알 길이 없으므로, **iPhone이 한 번도 연결된 적 없으면** 실행할 때마다 이 창을
  먼저 띄운다 (`hasConnectedPhone`).

두 앱 모두 스토어 링크가 아니라 같은 페이지(`CompanionLinks.downloadPage`)를
가리킨다. Mac 앱은 스토어에 없고, iPhone 앱의 App Store 주소는 아직 없다 — 페이지가
중간에 있으면 링크가 바뀌어도 앱을 다시 낼 필요가 없다. **출시할 때 고칠 곳은
`docs/index.html` 스크립트 맨 위의 `APP_STORE_URL`, `MAC_DOWNLOAD_URL` 두 줄뿐이다.**

### 웹 페이지 (GitHub Pages)

`docs/`가 `main` 브랜치의 `/docs` 소스로 배포된다. 빌드 단계 없는 정적 HTML이고
세 페이지가 `docs/style.css`를 같이 쓴다. 지원 페이지와 개인정보 처리방침 주소는
App Store Connect의 "지원 URL" / "개인정보 처리방침 URL"에 그대로 넣으면 된다.
앱이 수집·전송하는 데이터가 바뀌면(분석 SDK 추가 등) `docs/privacy/`도 같이 고칠 것.

## Mac 앱 배포 (GitHub Releases)

Mac 앱은 스토어에 못 올린다. 다운로드 페이지의 "Mac용 다운로드" 버튼은
`releases/latest`로 가므로, **가장 최신 릴리즈가 Mac 릴리즈여야 하고 첨부 파일
이름은 `TrackpadServer.zip`으로 고정**이다.

```bash
Tools/release_mac.sh              # project.yml의 MARKETING_VERSION으로
Tools/release_mac.sh 1.1          # 버전 지정
Tools/release_mac.sh --no-publish # 공증까지만, 릴리즈는 안 만듦 (연습용)
```

아카이브 → Developer ID export → 공증 → staple → 재압축 → `gh release create`
까지 한 번에 한다. 중간에 샌드박스가 켜져 있거나 하드닝 런타임이 꺼져 있으면
거기서 멈춘다 — 둘 다 통과해도 조용히 안 움직이는 앱이 나오는 조합이라 미리 막는다.

**공증을 건너뛰면 안 된다.** 서명만 된 앱은 다운로드 격리 딱지가 붙은 채로
Gatekeeper에 막혀 아예 안 열린다. 사용자는 그걸 "앱이 고장났다"로 읽는다.

### 최초 1회 준비

둘 다 사람이 웹에서 해야 하는 일이다.

1. **Developer ID Application 인증서** — `Apple Development` 인증서로는 스토어
   밖 배포 서명을 못 한다. Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸
   `+` ▸ Developer ID Application (또는
   [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates)).
   **Account Holder 권한이 필요하다.**
2. **notarytool 자격 증명** — [appleid.apple.com](https://appleid.apple.com) ▸
   로그인 및 보안 ▸ 앱 암호에서 앱 전용 암호를 만든 뒤 한 번만 저장한다.

   ```bash
   xcrun notarytool store-credentials TrackpadRemote \
     --apple-id <Apple ID> --team-id QGAQ3AY3R3 --password <앱 전용 암호>
   ```

   다른 이름으로 저장했으면 `NOTARY_PROFILE=<이름> Tools/release_mac.sh`.

준비가 됐는지는 `Tools/release_mac.sh --no-publish`가 알려준다. 프리플라이트에서
멈추면 아직인 것이고, 빌드가 시작되면 된 것이다.

## 빌드

`TrackpadRemote.xcodeproj`가 리포에 포함되어 있다. 열고 스킴을 골라 실행하면 된다.

| 스킴 | 타깃 | 최소 버전 | Bundle ID |
|---|---|---|---|
| `TrackpadRemote` | iPhone 앱 | iOS 17 | `com.leeo.TrackpadRemote` |
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

### 앱 아이콘 재생성

아이콘 PNG는 손으로 그린 게 아니라 `Tools/make_app_icons.py`가 그린다. 아트워크를
한 번만(1024pt를 4배 슈퍼샘플링해서) 렌더한 뒤 각 크기로 축소하므로, 16pt Finder
크기까지 같은 원본에서 나온다. 디자인을 고쳤으면 스크립트를 고치고 다시 돌릴 것 —
`.xcassets` 안의 PNG를 직접 갈아끼우지 말 것.

```bash
python3 -m pip install Pillow   # 최초 1회
python3 Tools/make_app_icons.py
```

| 카탈로그 | 타깃 | 담긴 것 |
|---|---|---|
| `Resources/Assets-iOS.xcassets` | `TrackpadRemote` | 1024 universal 한 장 (나머지는 Xcode가 파생) |
| `Resources/Assets-macOS.xcassets` | `TrackpadServer` | 16~512@2x 전체 세트 |

iOS는 정사각 full-bleed로 내보내고(마스킹은 시스템이 한다), macOS는 1024 캔버스
안에 824pt 스퀘어클로 인셋 + 그림자를 직접 그려 넣는다 — 플랫폼마다 요구하는
프레이밍이 달라서 마스터 두 장이 필요하다.

### 앱스토어 스크린샷 재생성

스크린샷도 `Tools/make_screenshots.py`가 만든다. iOS와 macOS는 따로 나온다.

```bash
python3 Tools/make_screenshots.py capture   # 시뮬레이터에서 실제 iOS 화면 캡처 (Xcode 필요)
python3 Tools/make_screenshots.py           # 캡션·기기 프레임·터치 합성
python3 Tools/make_screenshots.py ios       # 한쪽만: ios / mac
```

| 폴더 | 크기 | 내용 |
|---|---|---|
| `Screenshots/iOS` | 1242×2688 (6.5" 세로) | 트랙패드 / 클릭 / 스크롤·확대 / 세 손가락 / 자동 연결 / 설정 |
| `Screenshots/macOS` | 2880×1800 | 메뉴 막대 + iPhone / 대기 메뉴 / 제스처 / 1:1 연결 |
| `Screenshots/captures` | — | 합성에 쓰는 원본 캡처. 커밋해 두므로 캡션만 고칠 땐 `capture` 불필요 |

- **iOS 화면은 진짜 앱이다.** Debug 빌드는 실행 인자로 화면을 연출한다 —
  `-screenshotState connected|searching`, `-screenshotSettings YES`. 이때는 브라우징을
  시작하지 않으므로 근처에 실제 Mac이 있어도 캡처 중에 화면이 바뀌지 않는다.
  Release에는 들어가지 않는다(`#if DEBUG`).
- 앱은 가로 전용인데 캔버스는 세로라, 기기를 세워서(다이내믹 아일랜드가 위) UI가
  옆으로 누운 채로 넣는다. 가로 기기를 세로 캔버스에 넣으면 폭에 맞춰 띠처럼 작아진다.
- 패드 위의 원은 앱이 실제로 그리는 립플(`showRipple`)과 같은 모양·색으로 덧그린
  것이다. 립플은 0.35초짜리 애니메이션이라 캡처로는 잡히지 않는다.
- **Mac 화면은 다시 그린 것이다.** 메뉴 막대 앱이라 캡처할 창이 없고, `NSMenu`는
  오프스크린 렌더가 안 된다. 메뉴 문구는 `MAC_MENUS`에 옮겨 두었으니
  `TrackpadServerApp.swift`의 메뉴를 바꾸면 거기도 같이 고칠 것.
- SF Symbol은 Pillow가 못 그려서 `Tools/render_symbols.swift`로 PNG를 뽑아 쓴다.
- 앱스토어는 알파 채널이 있는 PNG를 거부하므로 전부 RGB로 저장한다.

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
| 두 손가락 오므리기/벌리기 | 축소 / 확대 |
| 세 손가락 탭 | 찾아보기 (포인터 아래 단어) |
| 세·네 손가락 위 | Mission Control |
| 세·네 손가락 아래 | App Exposé |
| 세·네 손가락 좌/우 | 다음 / 이전 스페이스 |
| 엄지+세 손가락 오므리기 | Launchpad (macOS 26은 Apps) |
| 엄지+세 손가락 벌리기 | 데스크탑 보기 |
| 더블탭 후 홀드+이동 | 드래그 |

손가락이 닿는 지점마다 확장하며 사라지는 원이 그려진다. 패드 쪽에는 커서가 없어서
터치가 읽혔는지 확인할 방법이 이것뿐이다. 두 손가락 우클릭이면 원도 두 개 그려진다.

연타 판정은 **아이폰에서** 한다 (0.3초 이내 + 44pt 이내). 판정 결과인 클릭 횟수를
패킷에 실어 보내고 Mac은 그걸 `mouseEventClickState`에 그대로 넣는다. 패킷 도착
시각으로 Mac이 다시 추측하지 않는다 — 무선 지터 때문에 더블클릭이 깨지던 지점이다.

## 멀티터치 제스처

### 스크롤이냐 핀치냐

두 손가락은 둘 다일 수 있다. 프레임마다 판단하면 스크롤이 살짝 비뚤 때 화면이
확대돼버린다. 그래서 **증거를 모아 한 번만 결정하고, 제스처가 끝날 때까지
유지한다** — 중간에 모드가 바뀌면 고장난 것처럼 느껴진다.

- 중심점 이동량은 스크롤 쪽 증거, 벌어짐 변화량은 핀치 쪽 증거로 쌓는다
- 둘 중 큰 쪽이 24pt를 넘으면 그 순간 확정
- 벌어짐은 두 점 거리가 아니라 **중심점으로부터의 평균 거리**로 잰다.
  손가락 수와 무관하게 정의되므로 세 번째 손가락이 닿아도 값이 튀지 않는다

### 세 손가락 스와이프

중심점이 시작점에서 55pt 이상 움직이면 **제스처당 한 번만** 발사한다. 프레임마다
보내면 Mission Control이 연타된다. 우세한 축으로 방향을 정한다.

### 네 손가락

Mac은 Mission Control·스페이스 전환을 세 손가락과 네 손가락 중 어느 쪽에 둘지
사용자가 고르게 한다. 여기서는 **둘 다 같은 스와이프**로 받는다. 네 손가락에만
있는 것은 엄지 핀치 — 벌어짐(중심점으로부터의 평균 거리)이 시작 대비 30pt 넘게
변하면 오므림은 Launchpad, 벌림은 데스크탑 보기다. 엄지가 모이면 중심점도 끌려가고
스와이프 중에도 벌어짐이 흔들리므로, 이동량과 벌어짐 변화 중 **큰 쪽이 자기 임계값을
넘을 때만** 발사한다.

손가락이 하나씩 떨어지는 동안 남은 손가락이 다른 제스처로 읽히지 않도록, 두 손가락
처리는 그 제스처의 최대 손가락 수가 2일 때만 한다. 탭 판정도 같은 최대 손가락 수로
나눈다 (1 좌클릭 · 2 우클릭 · 3 찾아보기 · 4 무시).

### 못 하는 것

아래는 macOS에 기본 단축키가 없거나 진짜 제스처 이벤트로만 되는 것들이라 넣지 않았다.

- 두 손가락 좌우로 페이지 앞/뒤 — 가로 스크롤과 구분할 방법이 없다. 스크롤 이벤트에
  phase를 실어 앱이 트랙패드 스크롤로 인식하게 하는 방법은 남아 있다
- 두 손가락 오른쪽 가장자리에서 알림 센터, 두 손가락 더블탭 스마트 확대, 회전
- 연속 확대(단계가 아닌) — 비공개 이벤트 필드가 필요하다
- 세 손가락 드래그 — 세 손가락 스와이프와 겹친다

### Mac 쪽은 키보드 단축키로 주입한다

진짜 트랙패드 제스처 이벤트(`NSEventTypeSwipe`/`Magnify`)를 만들려면 `CGEventType`에
존재하지도 않는 타입 값을 넣고 문서화되지 않은 필드에 값을 써야 한다. 대신
**macOS가 같은 동작에 이미 바인딩해둔 단축키**를 보낸다:

| 제스처 | 보내는 키 |
|---|---|
| 세 손가락 위 | ⌃↑ |
| 세 손가락 아래 | ⌃↓ |
| 세 손가락 좌 | ⌃→ (오른쪽 스페이스로) |
| 세 손가락 우 | ⌃← |
| 확대 / 축소 | ⌘= / ⌘- |
| 세 손가락 탭 | ⌃⌘D (찾아보기) |
| 네 손가락 벌리기 | F11 (데스크탑 보기) |
| 네 손가락 오므리기 | 단축키가 없어 `Apps.app`/`Launchpad.app`을 직접 연다 |

전부 공개 API고 OS 업데이트에 안 깨진다. 대가는 두 가지다 — **사용자가 이 단축키를
바꾸거나 껐으면 해당 제스처가 안 먹고**, **확대가 연속이 아니라 단계적이다**
(핀치 55pt마다 한 칸).

수식어 키는 생성 후 `flags`에 **대입**한다. 이벤트 소스가 실제 키보드의 현재
수식어를 물고 오기 때문에, 사용자가 Shift를 누르고 있으면 ⌘= 가 ⌘+ 로 바뀐다.

## 설정 (iOS)

헤더의 슬라이더 아이콘, 또는 Mac을 찾는 중일 때 화면 가운데 **설정** 버튼으로 연다.
연결 전에도 열리는 건 의도한 것이다 — 붙기를 기다리는 동안 감을 맞춰두는 게 자연스럽다.

| 항목 | 범위 | 기본값 |
|---|---|---|
| 포인터 속도 | 0.4 ~ 2.5배 | 1.0 |
| 포인터 가속 | on / off | on |
| 스크롤 속도 | 0.5 ~ 5.0 | 2.0 |
| 자연스러운 스크롤 방향 | on / off | on |
| 핀치 확대 사용 | on / off | on |
| 핀치 민감도 | 0.5 ~ 2.0배 | 1.0 |
| 세 손가락 스와이프 사용 | on / off | on |
| 스와이프 민감도 | 0.5 ~ 2.0배 | 1.0 |

`UserDefaults`에 저장되고 재실행해도 유지된다. 모든 컨트롤을 기본값에 두면 상수로
박혀 있던 시절과 정확히 같은 느낌이 나온다.

### 구조

- `PadTuning` — 순수 값 타입. `TrackpadUIView`가 실제로 쓰는 단위로 이미 환산된
  상태라, UIKit 쪽은 Combine도 UserDefaults도 몰라도 된다.
- `PadSettings` — `ObservableObject`. 슬라이더 값(배율)을 `PadTuning`(포인트, 게인)으로
  환산한다. 예를 들어 핀치 민감도가 높을수록 확대 한 칸에 필요한 벌어짐이 **짧아진다**.

`@AppStorage`를 `ObservableObject` 안에 쓰지 않았다. 그건 View 전용 프로퍼티 래퍼라
`objectWillChange`를 발행하지 않아서, 설정을 바꿔도 패드에 반영되지 않는다. 대신
`@Published` + `didSet`으로 직접 저장한다.

읽을 때는 `object(forKey:)`를 쓴다. `double(forKey:)`/`bool(forKey:)`는 키가 없을 때
0/false를 돌려주기 때문에, 첫 실행에서 기본값을 조용히 덮어쓴다.

**탭 판정 값은 노출하지 않았다.** 탭 최대 시간, 연타 인식 창, 립플 크기 같은 것들은
"탭이 무엇인가"를 정의하는 값이지 취향의 문제가 아니다.

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
- 두 손가락 페이지 앞/뒤 — 스크롤 이벤트에 phase 필드 싣기
- 상대 이동 모드 토글 — 절대 매핑은 조준은 빠르지만 정밀 작업엔 불리하다
- 다중 모니터에서 매핑 대상 디스플레이 선택
- 미러링 모드 (ScreenCaptureKit + Network.framework QUIC — MC 스트림은 대역폭이 불안정해서 비추)

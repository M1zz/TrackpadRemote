# TrackpadRemote todo

## 앱 아이콘 (iOS / macOS)
- [x] 아이콘 아트워크 생성 스크립트 작성 (`Tools/make_app_icons.py`)
- [x] iOS 에셋 카탈로그 `Resources/Assets-iOS.xcassets` 생성 (1024 universal)
- [x] macOS 에셋 카탈로그 `Resources/Assets-macOS.xcassets` 생성 (16~512@2x 전체 세트)
- [x] `project.yml`에 카탈로그/`ASSETCATALOG_COMPILER_APPICON_NAME` 추가 후 `xcodegen generate`
- [x] 두 타깃 빌드 검증 — macOS `AppIcon.icns`, iOS `AppIcon60x60@2x` / `AppIcon76x76@2x~ipad` 임베드 확인

## 앱스토어 스크린샷 (iOS / macOS 따로)
- [x] iOS 앱에 DEBUG 전용 스크린샷 스테이징 인자 추가 (`-screenshotState`, `-screenshotSettings`)
- [x] SF Symbol 렌더 헬퍼 `Tools/render_symbols.swift`
- [x] 6.9" 시뮬레이터에서 실제 화면 캡처 (연결됨 / 검색 / 설정)
- [x] 합성 스크립트 `Tools/make_screenshots.py` — iOS ×6, macOS 2880×1800 ×4
- [x] iOS 규격 변경: 6.9" 가로 2868×1320 → 6.5" 세로 1242×2688 (기기를 세워 배치, 캡션 줄바꿈)
- [x] 결과물 검수 (Exposé 글리프 누락 → SF/Gothic 혼용, 좁은 메뉴 막대 겹침 수정) 후 README에 재생성 방법 추가
- [x] iPad — iPhone 전용으로 결정 (`TARGETED_DEVICE_FAMILY = 1`), `project.yml`도 맞춤
- [x] Mac 서버는 Mac App Store 불가 → GitHub Releases 배포로 결정 (다운로드 페이지가 거기로 연결)
- [x] 동반 앱 카드·메뉴 추가에 맞춰 스크린샷 재캡처/재합성

## 앱 두 개 안내 + 서로 이어지는 창구
- [x] `Shared/CompanionLinks.swift` — 두 앱이 같은 다운로드 페이지를 가리킴
- [x] iOS: Mac 검색 화면에 "Mac에도 앱이 필요해요" 카드 + 공유 시트(AirDrop)로 링크 보내기
- [x] iOS: 설정에 "Mac 앱" 섹션
- [x] macOS: 메뉴 "Get the iPhone App…" → QR 코드 창, iPhone이 연결된 적 없으면 실행 시 자동 표시
- [x] 두 타깃 빌드, QR 창 오프스크린 렌더 확인

## GitHub Pages (docs/)
- [x] 다운로드 페이지 `docs/index.html`
- [x] 지원 페이지 `docs/support/`
- [x] 개인정보 처리방침 `docs/privacy/`
- [x] README에 링크
- [x] 커밋/푸시 후 Pages 활성화 (main /docs) 및 배포 확인 — 세 페이지 모두 200
- [ ] (출시 시) `docs/index.html`의 `APP_STORE_URL` 채우기, Mac 앱 GitHub Release 올리기 — 지금 Mac 다운로드 버튼은 빈 Releases로 간다

## 세·네 손가락 제스처
- [x] 세 손가락 탭 → 찾아보기 (⌃⌘D)
- [x] 네 손가락 스와이프 → 세 손가락과 같은 동작
- [x] 네 손가락 오므리기 → Launchpad/Apps, 벌리기 → 데스크탑 보기 (F11)
- [x] 여러 손가락이 한 이벤트에 닿을 때 탭 타이머가 시작 안 되던 문제, 남은 두 손가락이 스크롤로 읽히던 문제 수정
- [ ] 실기기(iPhone + Mac)에서 제스처 확인 — 특히 F11 데스크탑 보기와 엄지 핀치 임계값(30pt)
- [ ] (검토) 두 손가락 페이지 앞/뒤 — 스크롤 이벤트 phase 필드

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
- [ ] (결정 필요) iPad 스크린샷 — 작업 트리 pbxproj는 iPhone 전용(`TARGETED_DEVICE_FAMILY = 1`)이라 제외. `project.yml`은 아직 `"1,2"`
- [ ] (결정 필요) Mac 서버는 샌드박스 비활성이라 Mac App Store 심사 불가 — 웹/Developer ID 배포용으로 쓰거나 샌드박스 대응 필요

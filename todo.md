# TrackpadRemote todo

## 앱 아이콘 (iOS / macOS)
- [x] 아이콘 아트워크 생성 스크립트 작성 (`Tools/make_app_icons.py`)
- [x] iOS 에셋 카탈로그 `Resources/Assets-iOS.xcassets` 생성 (1024 universal)
- [x] macOS 에셋 카탈로그 `Resources/Assets-macOS.xcassets` 생성 (16~512@2x 전체 세트)
- [x] `project.yml`에 카탈로그/`ASSETCATALOG_COMPILER_APPICON_NAME` 추가 후 `xcodegen generate`
- [x] 두 타깃 빌드 검증 — macOS `AppIcon.icns`, iOS `AppIcon60x60@2x` / `AppIcon76x76@2x~ipad` 임베드 확인

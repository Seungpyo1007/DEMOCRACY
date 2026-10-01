# 출시 절차

`main`에 `v*.*.*` 태그가 올라가면 `.github/workflows/release.yml`이 돎.

- Android: AAB 빌드 → Play 내부 테스트 트랙 업로드
- iOS: 아카이브 → App Store Connect 업로드 → TestFlight

프로덕션으로 올리는 건 각 콘솔에서 사람이 함.

## 버전 올리기 (Git Flow)

```bash
git checkout develop && git pull
git checkout -b release/0.2.2
# app/pubspec.yaml  version: 0.2.2+4   (+ 뒤 숫자는 업로드마다 1씩 올려야 함)
# app/lib/src/app/app_version.dart  appVersion / appBuild 같이
git commit -am "Bump to 0.2.2"
git push -u origin release/0.2.2
gh pr create --base main          # CI 통과 후 머지
git checkout main && git pull
git tag -a v0.2.2 -m "v0.2.2" && git push origin v0.2.2   # 여기서 release 워크플로 시작
gh pr create --base develop --head main                   # 백머지
```

## GitHub 시크릿

Settings → Secrets and variables → Actions.

| 이름 | 내용 | 어디서 |
|---|---|---|
| `DART_DEFINES_JSON` | `app/dart_defines.json` 내용 그대로 | 로컬 파일 |
| `ANDROID_KEYSTORE_BASE64` | 업로드 키스토어를 base64로 | `base64 -i upload.jks \| pbcopy` |
| `ANDROID_KEY_ALIAS` | 키 별칭 | `app/android/key.properties` |
| `ANDROID_KEY_PASSWORD` | 키 비밀번호 | 같은 곳 |
| `ANDROID_STORE_PASSWORD` | 스토어 비밀번호 | 같은 곳 |
| `KAKAO_NATIVE_KEY` | 카카오 네이티브 앱 키 (없으면 비워 둠) | Kakao Developers |
| `PLAY_SERVICE_ACCOUNT_JSON` | Play 업로드용 서비스 계정 키 JSON 내용 | 아래 |
| `IOS_KEYS_XCCONFIG` | `app/ios/Flutter/Keys.xcconfig` 내용 | 로컬 파일 |
| `APPLE_TEAM_ID` | 팀 ID | developer.apple.com → Membership |
| `ASC_KEY_ID` | App Store Connect API 키 ID | 아래 |
| `ASC_ISSUER_ID` | Issuer ID | 같은 화면 위쪽 |
| `ASC_KEY_P8` | `.p8` 파일 내용 | 키 만들 때 한 번만 받을 수 있음 |

변수(Variables): `PLAY_RELEASE_STATUS` — 첫 심사 끝나기 전엔 비워 둠(= draft). 심사 통과 뒤 `completed`.

### Play 서비스 계정

1. Google Cloud 콘솔 (프로젝트 `democracy-kr`) → IAM → 서비스 계정 만들기 → 키 추가 → JSON
2. Play Console → 사용자 및 권한 → 새 사용자 초대 → 그 서비스 계정 이메일 → 앱 `DEMOCRACY`에 「출시 관리」 권한
3. JSON 내용을 `PLAY_SERVICE_ACCOUNT_JSON`에

### App Store Connect API 키

App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API → 팀 키 생성. 역할은 **관리자**(배포 인증서를 자동으로 만들려면 필요). `.p8`은 생성 직후 한 번만 내려받을 수 있음.

## 처음 한 번은 손으로

- **Play**: 새 앱은 첫 AAB를 Play Console에서 직접 올려야 API 업로드가 열림. `flutter build appbundle --release --dart-define-from-file=dart_defines.json` → 내부 테스트 → 새 버전 만들기 → `app/build/app/outputs/bundle/release/app-release.aab`
- **Play 앱 서명**: 첫 업로드 뒤 Play Console → 설정 → 앱 서명에 나오는 「앱 서명 키 인증서」 SHA-1을 Firebase `democracy-kr` Android 앱에 추가. 안 하면 스토어에서 받은 앱은 Google 로그인이 안 됨
- **App Store Connect**: 앱 → 새로운 앱 (번들 ID `com.democracy.kr`, 기본 언어 한국어, SKU `democracy-kr`). 이게 있어야 업로드가 받아짐

스토어에 넣을 문구, 등급 설문, 데이터 안전 답은 [store/LISTING.md](store/LISTING.md).

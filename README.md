# YSL ReaPack Repository

Yoon-Soo Lee의 REAPER 도구를 ReaPack으로 설치하고 업데이트하기 위한 저장소입니다.

## ReaPack 저장소 이름

**YSL**

## 포함 패키지

### Sound Lib Manager Pro

REAPER에서 사운드 라이브러리 검색어와 태그를 관리하는 ReaImGui 기반 도구입니다.

주요 기능:

- 실시간 다중 단어 검색
- 검색어 및 태그 편집
- 즐겨찾기와 최근 사용 정렬
- AND/OR 태그 필터
- JSON 백업 및 복원
- CSV 가져오기 및 내보내기

필수 구성:

- REAPER
- ReaPack
- ReaImGui 0.9.2 이상

### Region Sync Manager

Region CSV 가져오기·내보내기, 미리보기, UID 기반 비교·병합, 일괄 편집 및 변경 보고 기능을 제공하는 도구입니다.

필수 구성:

- REAPER
- ReaImGui

선택 구성:

- js_ReaScriptAPI: 네이티브 파일 선택 창 사용
- REAPER 7.62 이상 권장

## 설치 주소

GitHub 저장소를 만든 후 아래 주소에서 `YOUR_GITHUB_NAME`만 본인의 GitHub 사용자명으로 바꿉니다.

```text
https://github.com/YOUR_GITHUB_NAME/YSL-ReaPack/raw/main/index.xml
```

REAPER에서 다음 순서로 등록합니다.

```text
Extensions
→ ReaPack
→ Import repositories
→ 위 주소 붙여넣기
→ OK
→ Synchronize packages
```

그다음 `Extensions > ReaPack > Browse packages`에서 패키지명을 검색해 설치합니다.

## 업데이트 방법

Lua 파일을 수정할 때는 파일 상단의 `@version`을 반드시 올리고 `@changelog`도 갱신합니다.

예:

```lua
-- @version 1.0.2
-- @changelog
--   + 변경 내용을 작성합니다.
```

변경 파일을 GitHub에 Push하면 GitHub Actions가 `index.xml`을 자동으로 검사하고 갱신합니다.  
`index.xml`은 직접 편집하지 않는 것을 권장합니다.

## 라이선스

자세한 내용은 `LICENSE.md`를 확인하세요.

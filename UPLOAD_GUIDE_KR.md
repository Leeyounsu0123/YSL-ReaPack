# YSL ReaPack GitHub 업로드 가이드

## 1. GitHub 저장소 만들기

권장 저장소명:

```text
YSL-ReaPack
```

설정:

- Public 저장소 권장
- 기본 브랜치: `main`
- README, .gitignore, License 자동 생성은 체크하지 않음

## 2. 이 폴더 전체 업로드

압축을 푼 뒤 `YSL-ReaPack` 폴더 안의 내용을 저장소 루트에 올립니다.

다음 항목이 모두 올라가야 합니다.

```text
.github/workflows/reapack-index.yml
Scripts/YSL/Yoon-Soo Lee_Sound Lib Manager Pro.lua
Scripts/YSL/Yoon-Soo Lee_Region Sync Manager.lua
.reapack-index.conf
.gitattributes
.gitignore
index.xml
README.md
LICENSE.md
```

중요: `.github`와 `.reapack-index.conf`처럼 점으로 시작하는 항목도 빠지면 안 됩니다.

GitHub Desktop을 사용할 경우 폴더 전체를 그대로 Commit/Push하면 가장 안전합니다.

## 3. GitHub Actions 확인

첫 Push 후 저장소의 `Actions` 탭에서 `ReaPack index` 작업이 실행됩니다.

정상 완료되면 GitHub Actions가 `index.xml`에 두 패키지 정보를 자동으로 추가하고 새 커밋을 Push합니다.

`index.xml`을 열었을 때 다음 문자열이 보이면 성공입니다.

```xml
<reapack
```

## 4. Actions가 Push 권한 오류를 낼 때

저장소에서 다음 설정을 확인합니다.

```text
Settings
→ Actions
→ General
→ Workflow permissions
→ Read and write permissions
→ Save
```

그 뒤 `Actions` 탭에서 실패한 작업을 다시 실행합니다.

## 5. ReaPack에 등록할 주소

GitHub 사용자명이 `example-user`라면:

```text
https://github.com/example-user/YSL-ReaPack/raw/main/index.xml
```

REAPER에서:

```text
Extensions
→ ReaPack
→ Import repositories
→ 주소 붙여넣기
→ OK
```

저장소 목록에는 `YSL`로 표시됩니다.

## 6. 스크립트 업데이트 규칙

코드를 수정할 때마다 해당 Lua 파일 상단의 버전을 올립니다.

```lua
-- @version 1.0.2
```

그리고 `@changelog`에 변경 사항을 작성한 뒤 Commit/Push합니다.

같은 버전 번호로 코드를 바꾸면 ReaPack이 기존 릴리스 변경을 무시할 수 있으므로 버전 증가는 필수입니다.

## 7. XML 관련 주의사항

- `index.xml`을 손으로 완성하려고 하지 않습니다.
- Lua 파일은 반드시 저장소 루트가 아닌 하위 폴더에 둡니다.
- 현재 구성에서는 `Scripts/YSL` 폴더가 ReaPack 카테고리로 사용됩니다.
- GitHub Actions가 파일명 공백과 한글 설명을 올바르게 인코딩해 XML을 생성합니다.

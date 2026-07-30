# YSL Tools v1.5.0 업로드 안내

이 폴더는 기존 `Leeyounsu0123/YSL-ReaPack` 저장소를 업데이트하기 위한 배포 세트입니다.

## GitHub에서 교체·추가할 파일

| 이 배포 세트의 파일 | GitHub 저장소 경로 | 작업 |
| --- | --- | --- |
| `README.md` | `README.md` | 기존 파일 교체 |
| `index.xml` | `index.xml` | 기존 파일 교체 |
| `Tools/YSL_Region Sync Manager.lua` | 같은 경로 | 기존 파일 교체 |
| `Tools/YSL_Sound Lib Manager Pro.lua` | 같은 경로 | 기존 파일 교체 |
| `Tools/YSL_Item Envelope Manager.lua` | 같은 경로 | 신규 추가 |

기존 저장소의 `.github`, `.reapack-index.conf`, `LICENSE.md` 및 다른 파일은 삭제하지 않습니다.

## 권장 업로드 순서

1. 압축을 해제합니다.
2. 위 표의 다섯 파일을 기존 저장소의 동일 경로에 업로드합니다.
3. 커밋 메시지는 `YSL Tools v1.5.0 release`로 입력합니다.
4. 저장소의 **Actions → deploy**가 완료될 때까지 기다립니다.
5. deploy 작업이 `index.xml`을 다시 생성한 뒤, REAPER에서 **Extensions → ReaPack → Synchronize packages**를 실행합니다.

## ReaPack 확인

- 저장소 표시 이름: `YSL Tools`
- 공통 버전: `1.5.0`
- 설치 주소:

```text
https://raw.githubusercontent.com/Leeyounsu0123/YSL-ReaPack/main/index.xml
```

업데이트 후 ReaPack Browser에는 다음 세 패키지가 표시됩니다.

- `YSL_Region Sync Manager.lua`
- `YSL_Sound Lib Manager Pro.lua`
- `YSL_Item Envelope Manager.lua`

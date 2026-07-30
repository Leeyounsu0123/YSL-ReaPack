# YSL Tools

**게임 사운드 작업을 더 빠르고 편리하게 만드는 REAPER 도구 모음**

안녕하세요. 게임 사운드 디자이너 이윤수(Yoon-Soo Lee)입니다.

YSL Tools는 실제 게임 사운드 작업을 하면서 느꼈던 불편함을 줄이기 위해 제작한 REAPER 스크립트 모음입니다.

리전 정리, 협업 데이터 관리, 사운드 라이브러리 검색처럼 반복적으로 많은 시간이 들어가는 작업을 조금 더 빠르고 안전하게 처리하는 것을 목표로 하고 있습니다.

처음에는 개인 작업을 편하게 만들기 위해 시작했지만, 비슷한 불편을 겪고 있는 다른 사운드 디자이너와 REAPER 사용자에게도 도움이 될 수 있도록 ReaPack을 통해 공개하고 있습니다.

아직 부족한 부분이 있을 수 있지만, 실제 작업에서 계속 사용하고 테스트하면서 기능과 안정성을 개선해 나가고 있습니다.  
사용 중 오류를 발견하거나 새로운 기능에 대한 의견이 있다면 언제든지 편하게 남겨주세요.

여러분의 피드백은 YSL Tools를 더 좋은 도구로 만드는 데 큰 도움이 됩니다.

- 제작자: 이윤수 / Yoon-Soo Lee
- 분야: Game Sound Design · Audio Implementation
- 문의 및 피드백: [dldbstn0123@gmail.com](mailto:dldbstn0123@gmail.com)

## English

Hello, I’m Yoon-Soo Lee, a game sound designer.

YSL Tools is a collection of REAPER scripts created to reduce repetitive work in real-world sound production. The tools focus on region management, collaboration workflows, sound-library organization, and item-envelope editing.

Feedback and bug reports are always welcome and will help improve the tools.

## Tools

### Region Sync Manager

REAPER 리전을 안전하게 편집하고 CSV로 주고받기 위한 협업 도구입니다.

- 변경사항을 확인한 뒤 적용하는 단계식 리전 편집
- CSV 가져오기·내보내기 및 3-Way 병합
- 리전 QC, 일괄 이름 변경, 자동 백업
- 비정상 종료 시 편집 내용 복구

### Sound Lib Manager Pro

사운드 라이브러리 검색어와 태그를 관리하고 Media Explorer 검색으로 연결하는 도구입니다.

- 다중 검색어·태그 검색과 Smart Collections
- 즐겨찾기, 사용 기록, 자동 태그 추천
- Media Explorer 검색 전송 및 검색 기록 관리
- JSON 백업·복원과 CSV 이전

### Item Envelope Manager

아이템 파형 위에서 Take 엔벨로프를 직접 디자인하는 도구입니다.

- Volume, Pitch, Pan, Speed 곡선 편집
- 다중 구간 및 다중 선택 아이템 일괄 적용
- Speed A/B Preview Take
- 사용자 프리셋 및 한국어·영어 UI

## Installation

YSL Tools를 사용하려면 [ReaPack](https://reapack.com/)과 ReaImGui가 필요합니다.

### 1. ReaPack 설치

[ReaPack 공식 홈페이지](https://reapack.com/)에서 ReaPack을 설치합니다.

### 2. YSL Tools 저장소 등록

REAPER 상단 메뉴에서 다음 경로를 엽니다.

**Extensions → ReaPack → Import repositories**

아래 주소를 붙여넣습니다.

```text
https://raw.githubusercontent.com/Leeyounsu0123/YSL-ReaPack/main/index.xml
```

저장소 동기화 후 ReaPack 패키지 목록에서 `YSL Tools` 또는 원하는 도구 이름을 검색해 설치합니다.

### 3. ReaImGui 설치

**Extensions → ReaPack → Browse packages**에서 `ReaImGui`를 검색해 설치합니다.

`js_ReaScriptAPI`는 Region Sync Manager의 네이티브 파일 선택 창과 Sound Lib Manager Pro의 Media Explorer 검색 기록 연동에 사용하는 선택 사항입니다.

## Requirements

- REAPER 7
- ReaPack
- ReaImGui 0.9.2 이상
- js_ReaScriptAPI 선택 설치

## License

Copyright (c) 2026 Yoon-Soo Lee. All rights reserved.

수정본을 포함한 파일의 재배포, 재판매, 재게시 및 2차 배포에는 제작자의 사전 서면 허가가 필요합니다.

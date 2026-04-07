# cc-chips-jy

Claude Code 상태줄을 위한 커스텀 Powerline 칩 테마.
[roger-me/CC-CHIPS](https://github.com/roger-me/CC-CHIPS)를 베이스로, [sangrokjung/claude-forge](https://github.com/sangrokjung/claude-forge)의 `cc-chips-custom` 오버레이를 단일 엔진으로 병합하고, 동적 색상 알림·미니멀 테마·자동 설치 스크립트·Windows PowerShell 지원을 추가한 버전입니다.

## Credits

| 원본 | 역할 |
|------|------|
| [roger-me/CC-CHIPS](https://github.com/roger-me/CC-CHIPS) | 베이스 엔진, Powerline 칩 렌더링, 테마 시스템, Current/Weekly usage |
| [sangrokjung/claude-forge](https://github.com/sangrokjung/claude-forge) (cc-chips-custom) | 모델별 비용 계산, 세션 ID, 캐시 히트율, API 응답시간 칩 |



## 디렉토리 구조

```
cc-chips-jy/
├── engine.sh        ← 단일 병합 엔진 (bash)
├── engine.ps1       ← Windows PowerShell 엔진
├── install.sh       ← 자동 설치 스크립트
├── uninstall.sh     ← 제거 스크립트
└── themes/
    ├── claude.sh    ← 기본 테마 (테라코타)
    ├── cool.sh      ← 블루 + 오렌지
    ├── retro.sh     ← 핑크 + 라임
    ├── cyber.sh     ← 사이버펑크 (노랑 + 틸)
    └── minimal.sh   ← ASCII 전용 (Nerd Font 불필요)
```

## 칩 레이아웃

```
[󰱩 경로] [  브랜치] [ 모델  컨텍스트바 % $ 비용 󱌷 세션ID] [ 캐시율%  응답시간s]
Current:  ██████████──────────  60% used | Resets: 19:00, Monday, 06/04/2026
Weekly:   ████████████────────  70% used | Resets: 0:00, Friday, 10/04/2026
```

**연결 끊김 (DISCONNECTED):**
```
[󰱩 경로] [  브랜치] [DISC  컨텍스트바 % $ 비용] [ DISC 60+s]
```

**Minimal 테마 (Nerd Font 없이):**
```
[# 경로] | [> @ 브랜치] | [~ 모델 % [##---] 48% $ $0.02 & a3f7b21] | [= 85% ! 1.2s]
Current:  ##########--------  60% used | Resets: 19:00, Monday, 06/04/2026
```

## 동적 색상 알림

상태에 따라 칩 색상이 자동으로 변경됩니다:

| 메트릭 | 조건 | 색상 / 동작 |
|--------|------|-------------|
| 컨텍스트 사용률 | ≥ 80% | 빨간색 |
| 컨텍스트 사용률 | 50–79% | 주황색 |
| 컨텍스트 사용률 | < 50% | 테마 기본값 |
| 캐시 히트율 | ≥ 80% | 초록색 |
| 캐시 히트율 | < 20% | 노란색 |
| API 응답시간 | ≥ 10초 | `!!` 경고 아이콘 앞에 표시 |
| API 응답시간 | ≥ 60초 (sentinel) | `DISC` 접두사 + `60+s` 표시 |
| 연결 끊김 / 세션 없음 | session 미확인 또는 캐시 120초 초과 | Chip 3 → 빨간 `DISC` 칩 |

### 스마트 UX — Progressive Disclosure

모든 메트릭이 정상 범위일 때 Chip 4(캐시율/응답시간)를 자동으로 숨깁니다.

| 조건 | Chip 4 표시 여부 |
|------|-----------------|
| 컨텍스트 ≥ 50% | ✅ 표시 |
| 캐시 히트율 < 20% | ✅ 표시 |
| 5시간 사용량 ≥ 80% | ✅ 표시 |
| DISCONNECTED 또는 API sentinel | ✅ 항상 표시 |
| 모든 메트릭 정상 | ❌ 숨김 (조용한 상태) |

### stdin rate_limits (CC v2.1.80+)

Claude Code v2.1.80 이상에서는 stdin JSON에 `rate_limits` 필드가 포함되어  
OAuth API 호출 없이 Current/Weekly 사용량을 즉시 렌더링합니다.  
이전 버전에서는 자동으로 OAuth 캐시로 폴백합니다.

## 설치

### 요구사항

- `jq` — JSON 파싱
- `git` — 브랜치 감지 + 설치 스크립트
- `curl` — Usage API 호출 (Row 2)
- [Nerd Font](https://www.nerdfonts.com/) — `claude`, `cool`, `retro`, `cyber` 테마에 필요 (JetBrains Mono Nerd Font 권장)
  - `minimal` 테마는 Nerd Font 없이도 동작

### 자동 설치 (권장)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/JaeyeonBang/cc-chips-jy/main/install.sh)
```

또는 리포를 클론한 후:

```bash
bash install.sh
```

스크립트가 자동으로:
1. 의존성 확인 (jq, git)
2. `~/.claude/cc-chips`에 클론/업데이트
3. 테마 선택 프롬프트
4. `~/.claude/settings.json`에 `statusLine` 설정 작성
5. 기존 settings.json 백업

### 수동 설치

1. 리포 클론:

```bash
git clone https://github.com/JaeyeonBang/cc-chips-jy.git ~/.claude/cc-chips
```

2. `~/.claude/settings.json`에 추가:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/cc-chips/engine.sh"
  }
}
```

3. Claude Code 재시작

### 제거

```bash
bash ~/.claude/cc-chips/uninstall.sh
```

## 테마 변경

`~/.zshrc` 또는 `~/.bashrc`에 추가:

```bash
export CC_CHIPS_THEME=cyber   # claude (기본) | cool | retro | cyber | minimal
```

## 플랫폼 호환성

| 환경 | 엔진 | 지원 여부 |
|------|------|-----------|
| macOS | engine.sh | ✅ |
| Linux | engine.sh | ✅ |
| Windows (Git Bash) | engine.sh | ✅ |
| Windows (PowerShell) | engine.ps1 | ✅ |

## Windows PowerShell 설정

`~/.claude/settings.json`에서 엔진을 `engine.ps1`으로 지정:

```json
{
  "statusLine": {
    "type": "command",
    "command": "pwsh -NoProfile -File C:\\Users\\USERNAME\\.claude\\cc-chips\\engine.ps1"
  }
}
```

- `USERNAME`을 실제 Windows 사용자명으로 교체
- `pwsh` (PowerShell 7+) 또는 `powershell` (Windows PowerShell 5.1)을 사용
- `engine.ps1`은 ANSI 없이 ASCII 텍스트만 출력 (모든 PowerShell 환경 호환)


## License

MIT License © 2026 JaeyeonBang

이 프로젝트는 다음 MIT 오픈소스 프로젝트를 기반으로 합니다:

```
CC-CHIPS — Copyright (c) roger-me
https://github.com/roger-me/CC-CHIPS
Licensed under the MIT License.

claude-forge (cc-chips-custom) — Copyright (c) sangrokjung
https://github.com/sangrokjung/claude-forge
Licensed under the MIT License.
```

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
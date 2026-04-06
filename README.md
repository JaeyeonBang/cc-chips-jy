# cc-chips-jy

Claude Code 상태줄을 위한 커스텀 Powerline 칩 테마.
[roger-me/CC-CHIPS](https://github.com/roger-me/CC-CHIPS)를 베이스로, [sangrokjung/claude-forge](https://github.com/sangrokjung/claude-forge)의 `cc-chips-custom` 오버레이를 병합하고 Windows(Git Bash) 호환성을 추가한 버전입니다.

## Credits

| 원본 | 역할 |
|------|------|
| [roger-me/CC-CHIPS](https://github.com/roger-me/CC-CHIPS) | 베이스 엔진, Powerline 칩 렌더링, 테마 시스템, Current/Weekly usage |
| [sangrokjung/claude-forge](https://github.com/sangrokjung/claude-forge) (cc-chips-custom) | 모델별 비용 계산, 세션 ID, 캐시 히트율, API 응답시간 칩 |

## 디렉토리 구조

```
cc-chips/           원본 CC-CHIPS (roger-me 기반)
├── engine.sh       ← 커스텀 패치 적용됨
├── themes/
│   ├── claude.sh   ← 커스텀 패치 적용됨
│   ├── cool.sh
│   ├── retro.sh
│   └── cyber.sh

cc-chips-custom/    sangrokjung/claude-forge 오버레이 원본
├── engine.sh
└── themes/
    └── claude.sh
```

## 원본 대비 변경사항

### engine.sh

| 항목 | 내용 |
|------|------|
| 모델 감지 | Opus 4.6, Sonnet 4.6, Sonnet 4.5, Haiku 4.5 패턴 추가 |
| 모델별 비용 | Opus/Sonnet/Haiku 차등 단가 적용 |
| 세션 ID | Chip 3에 키 아이콘 + 세션 ID 앞 8자 표시 |
| 캐시 히트율 | Chip 4 — `cache_read / 전체 입력 토큰 × 100` |
| API 응답시간 | Chip 4 — `total_api_duration_ms`를 초 단위 표시 |
| **Windows 호환** | `stat` 대신 `get_file_mtime()` 헬퍼로 Git Bash/Linux/macOS 모두 지원 |

### themes/claude.sh

Stats 칩 색상 추가 (초록색 `#2E7D32`)

## 칩 레이아웃

```
[Chip 1: 폴더/경로] [Chip 2: Git 브랜치] [Chip 3: 모델·컨텍스트·비용·세션ID] [Chip 4: 캐시히트율·API응답시간]
Current:  ●●●●●●●●○○  80% used | Resets: 19:00, Monday, 06/04/2026
Weekly:   ●●●●●●●○○○  70% used | Resets: 0:00, Friday, 10/04/2026
```

## 설치

### 요구사항

- [Nerd Font](https://www.nerdfonts.com/) (JetBrains Mono Nerd Font 권장)
- `jq`
- `git`
- `curl`

### 설치 방법

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

### 테마 변경

`~/.zshrc` 또는 `~/.bashrc`에 추가:

```bash
export CC_CHIPS_THEME=cyber   # claude (기본) | cool | retro | cyber
```

## 플랫폼 호환성

| 환경 | 지원 여부 |
|------|-----------|
| macOS | ✅ |
| Linux | ✅ |
| Windows (Git Bash) | ✅ |

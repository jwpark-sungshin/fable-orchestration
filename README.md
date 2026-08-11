# Fable 기반 Claude Code 오케스트레이션 가이드

연구와 소프트웨어 개발에서 Claude Code의 작업을 역할별 모델에 분배하는
개인 사용자용 설정입니다. Fable 5가 메인 오케스트레이터로 계획과 분배를
담당하고, 실제 작업의 성격에 따라 Opus·Sonnet·Haiku 서브에이전트를
사용합니다.

이 저장소의 사람용 문서는 한국어로 작성되어 있습니다. Claude가 반복해서
읽는 프롬프트와 agent 정의는 컨텍스트 사용량을 줄이기 위해 간결한 영어로
작성되어 있습니다.

## 지원 환경

- 일반 Linux 배포판
- 설치·검증 스크립트를 실행할 Bash
- 대화형 셸: Bash, Zsh 또는 Fish
- Python 3
- 설치되어 있고 로그인된 Claude Code
- 아래 모델을 사용할 수 있는 Claude 계정

WSL에 의존하는 경로나 명령은 사용하지 않습니다. Debian, Ubuntu, Fedora,
Rocky Linux, Arch Linux 등에서 동일한 사용자 경로인 `~/.claude`와
`~/.local/bin`을 사용합니다. 회사나 학교 시스템에서 홈 디렉터리 정책이
다르면 설치 전에 관리자 정책을 확인하십시오.

## 역할과 모델

| 역할 | 모델 | effort | 담당 작업 |
|---|---|---:|---|
| 메인 | Fable 5 | medium | 계획, 분배, 진행 파악, 결과 종합 |
| `researcher` | Opus 5 | xhigh | 연구 방향, 가설, 시스템 설계, 복잡한 원인 분석, 실험과 해석 |
| `executor` | Opus 5 | high | 일반 구현, 수정, 테스트, 디버깅, 리뷰 |
| `explainer` | Sonnet 5 | high | 왜 또는 어떻게 동작하는지 설명 |
| `runner` | Haiku 4.5 | low | 명령, 빌드, 검색, 파일·로그 확인 |

`max` effort는 기본값으로 사용하지 않습니다. 정말 필요한 작업에서만 사용자가
명시적으로 선택하는 것을 권장합니다.

## 빠른 설치

저장소를 내려받은 뒤 저장소 루트에서 실행합니다.

```bash
bash install.sh
```

설치 프로그램이 출력한 셸 설정 파일을 다시 불러옵니다. 일반적인 예시는
다음과 같습니다.

```bash
# Bash
source ~/.bashrc

# Zsh
source ~/.zshrc

# Fish
source ~/.config/fish/config.fish
```

Fable 모드를 켜고 정적 검사를 실행합니다.

```bash
fable on
bash verify.sh
```

마지막으로 완전히 새로운 세션을 시작합니다.

```bash
claude
```

`--resume`, `--continue`, `-c`로 연 세션은 저장된 모델을 유지할 수 있으므로
최초 검증에는 사용하지 마십시오.

## 설치 프로그램이 변경하는 항목

설치 프로그램은 다음 사용자 파일만 관리합니다.

```text
~/.claude/fable/
~/.claude/.fable-state
~/.claude/agents/researcher.md
~/.claude/agents/executor.md
~/.claude/agents/explainer.md
~/.claude/agents/runner.md
~/.local/bin/fable
~/.claude/settings.json              # Fable PreToolUse/UserPromptSubmit 항목만 병합
셸 시작 파일                         # 표시된 두 marker 사이의 loader만 추가
```

기존 파일이 있으면 먼저 다음 디렉터리에 복사합니다.

```text
~/.claude/fable-backups/YYYYMMDD-HHMMSS-PID/
```

설치 프로그램은 프로젝트의 `CLAUDE.md`나 사용자의
`~/.claude/CLAUDE.md`를 수정하지 않습니다.

## 동작 원리

셸에서 `claude`를 실행하면 작은 셸 함수가 다음 명령으로 전달합니다.

```bash
fable run [원래 Claude 인자]
```

Fable 모드가 켜져 있으면 `fable run`이 사용자가 직접 지정하지 않은 기본값만
추가합니다.

```text
--model claude-fable-5
--effort medium
--append-system-prompt-file ~/.claude/fable/fable.md
```

사용자가 `--model`이나 `--effort`를 직접 지정하면 해당 값이 우선합니다.
Fable 모드가 꺼져 있으면 인자를 변경하지 않고 원래 Claude Code를 실행합니다.

메인 전용 프롬프트는 `CLAUDE.md`에서 import하지 않습니다. 사용자
`CLAUDE.md`는 서브에이전트도 읽을 수 있기 때문에, 그곳에 오케스트레이터
프롬프트를 넣으면 작업 agent가 자신도 오케스트레이터라고 오해할 수 있습니다.

## 사용 방법

일상적으로는 평소처럼 요청하면 됩니다.

```text
Run the build and report the errors.
→ runner

Explain why this cache can become inconsistent.
→ explainer

Fix the failing implementation and add regression tests.
→ executor

Evaluate this systems hypothesis, design experiments, implement the necessary
prototype, and interpret the results.
→ researcher
```

라우팅이 중요할 때는 agent 이름을 명시해도 됩니다.

```text
Use researcher for this task. First determine whether the hypothesis is valid,
then design and run the minimum experiment needed to test it.
```

### 켜기와 끄기

```bash
fable on
fable off
fable status
```

변경 사항은 새 Claude 세션부터 확실하게 적용됩니다.

## 모델 라우팅 검증

### 1. 설치 상태

```bash
fable status
bash verify.sh
```

### 2. 메인 세션

새 세션을 시작했을 때 메인 모델이 `Fable 5`, effort가 `medium`인지 확인합니다.
화면 표시만으로 판단하기 어려우면 아래 실행 기록 검사를 사용합니다.

### 3. 서브에이전트

메인 세션에서 짧은 읽기 전용 작업을 명시적으로 위임합니다.

```text
Use researcher to inspect one small project file and report one research risk.
Do not modify anything.
```

작업이 끝난 다음 일반 셸에서 실행합니다.

```bash
fable audit
```

예상 형태:

```text
Main: claude-fable-5 / medium
Recent subagents:
  researcher   claude-opus-5...   effort=xhigh
```

`resolvedModel`과 서브에이전트 출력의 effort가 실제 실행 판정 기준입니다.
agent에 들어갔을 때 보이는 상단 모델 표시는 부모 세션 정보를 보여줄 수 있으므로
그 표시만으로 판단하지 마십시오.

### `/agents`와 `claude agents`는 다릅니다

- `/agents`: 현재 대화 안에서 메인 agent가 호출한 서브에이전트
- `claude agents`: 독립적인 백그라운드 Claude 세션을 관리하는 화면

독립 세션을 agent 이름 없이 생성하면 별도의 메인 세션이므로 Fable을 사용하는
것이 정상입니다. 특정 역할을 독립 세션으로 시작하려면 해당 agent를 명시합니다.

```bash
claude --agent researcher --bg "Investigate the hypothesis"
```

## 사용량을 줄이는 운영 원칙

- 로그 조회나 빌드를 `researcher`에게 맡기지 않습니다.
- 일반 구현은 `executor`, 연구 판단이 필요한 경우에만 `researcher`를 사용합니다.
- 설명이 주 결과인 요청은 `explainer`를 사용합니다.
- 서로 독립적인 작업만 병렬로 실행합니다.
- 같은 파일을 여러 agent가 동시에 수정하지 않게 합니다.
- `max` effort를 기본 설정으로 만들지 않습니다.
- agent가 이미 확인한 전체 로그를 메인 대화에 다시 붙이지 않습니다.

## 문제 해결

### 새 세션이 Default 또는 다른 모델로 시작함

셸 함수가 로드됐는지 확인합니다.

```bash
type claude
fable status
```

`claude`가 함수로 표시되지 않으면 설치 프로그램이 출력했던 셸 설정 파일을
다시 불러오거나 새 터미널을 여십시오. 셸 함수를 우회하는 `command claude`는
Fable 기본값을 적용하지 않습니다.

### 메인이 medium이 아닌 effort로 시작함

기존 세션을 재개하지 않았는지 확인합니다. 그다음 설치된 명령에 `high`가
들어 있는지 검사합니다.

```bash
grep -- '--effort medium' ~/.local/bin/fable
```

### 모든 서브에이전트가 Fable을 사용함

`/agents`에서 `researcher`, `executor`, `explainer`, `runner` 중 어떤 이름으로
호출됐는지 확인합니다. `general-purpose`처럼 별도 모델이 없는 agent는 메인
모델을 상속할 수 있습니다.

다음 전역 변수가 설정돼 있으면 role별 설정을 덮어쓸 수 있으므로 제거합니다.

```bash
env | grep -E 'CLAUDE_CODE_SUBAGENT_MODEL|CLAUDE_CODE_EFFORT_LEVEL'
```

### explainer가 Opus를 사용함

다음 변수가 설정됐는지 확인합니다.

```bash
env | grep ANTHROPIC_DEFAULT_SONNET_MODEL
```

Sonnet alias를 Opus로 전역 치환하는 값이 있으면 제거해야 합니다.

### 설정 파일의 모델 ID를 사용할 수 없음

Claude Code와 계정에서 사용할 수 있는 모델 이름을 먼저 확인하십시오. 조직별
모델 정책이 다르면 `config/agents/*.md`와 `bin/fable`의 모델 ID를 변경한 뒤
`bash install.sh`를 다시 실행합니다. 모델 이름은 시간이 지나면 바뀔 수 있으므로
수업 시작 전에 담당자가 한 번 검증하는 것을 권장합니다.

### `~/.local/bin/fable`을 찾지 못함

`~/.local/bin`을 `PATH`에 추가하거나 전체 경로로 실행합니다.

```bash
~/.local/bin/fable status
```

## 제거

저장소 루트에서 실행합니다.

```bash
bash uninstall.sh
```

제거된 파일은 즉시 삭제하지 않고 다음 위치로 이동합니다.

```text
~/.claude/fable-backups/uninstall-YYYYMMDD-HHMMSS-PID/
```

설치 전에 존재했던 설정을 자동으로 추측해 복원하지는 않습니다. 필요하면 설치
시점의 백업에서 원하는 파일만 직접 복원하십시오.

## 안전 범위

`orchestration-gate.py`는 메인 agent의 직접 코드 수정을 줄이기 위한 작업 흐름
보조 장치입니다. 완전한 보안 경계나 샌드박스가 아닙니다. Claude Code의 권한
설정, Git diff 검토, 테스트, 백업을 대신하지 않습니다.

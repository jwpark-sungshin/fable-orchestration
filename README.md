# Fable 기반 Claude Code 오케스트레이션 가이드

연구와 소프트웨어 개발에서 Claude Code의 작업을 역할별 모델에 분배하는
개인 사용자용 설정입니다. Fable 5가 메인 오케스트레이터로 계획과 분배를
담당하고, 실제 작업의 성격에 따라 Opus·Sonnet·Haiku 서브에이전트를
사용합니다.

이 저장소의 사람용 문서는 한국어로 작성되어 있습니다. Claude가 반복해서
읽는 프롬프트와 agent 정의는 컨텍스트 사용량을 줄이기 위해 간결한 영어로
작성되어 있습니다.

## 저장소 구조: 루트 = 설치 폴더

저장소 루트는 설치된 `~/.claude/fable` 폴더와 같은 구조입니다. 루트의 설정
파일은 설치 폴더에 그대로(바이트 단위로 동일하게) 들어갑니다.

```text
fable.md                      # 메인 세션 전용 오케스트레이션 프롬프트
env.sh                        # claude 셸 함수 (Bash/Zsh)
empty.md                      # 이전 방식과의 호환용 빈 프롬프트
active.md -> fable.md         # 이전 방식과의 호환용 상대 symlink
agents/{executor,explainer,researcher,runner}.md
hooks/orchestration-gate.py   # PreToolUse 게이트
state/                        # 실행 중 생성되는 게이트 상태 (git에서 제외)
```

나머지는 설치·검증용 파일입니다. 설치 폴더에 함께 복사되지만 Claude Code가
직접 읽지는 않습니다.

```text
bin/fable                     # fable on | off | status
install.sh  uninstall.sh  verify.sh
scripts/manage_settings.py    # settings.json의 Fable 항목만 추가·제거
tests/                        # smoke.sh, gate.sh
```

`state/`는 게이트가 세션별 기록을 남기는 실행 시점 폴더입니다. 저장소에는
포함되지 않으며(`.gitignore`), 설치·재설치할 때도 기존 내용을 그대로 둡니다.

## 지원 환경

- 일반 Linux 배포판
- 설치·검증 스크립트를 실행할 Bash
- 대화형 셸: Bash 또는 Zsh (`env.sh`가 Bash/Zsh 문법을 사용)
- Python 3
- 설치되어 있고 로그인된 Claude Code
- 아래 모델을 사용할 수 있는 Claude 계정

다른 셸을 쓰는 경우 설치 프로그램은 아무것도 바꾸지 않고 멈춥니다. Bash나
Zsh가 읽는 시작 파일이 따로 있다면 `FABLE_RC_FILE`로 지정해 설치할 수
있습니다.

```bash
FABLE_RC_FILE=~/.bashrc bash install.sh
```

## 역할과 모델

| 역할 | 모델 | effort | 담당 작업 |
|---|---|---:|---|
| 메인 | Fable 5 | medium | 계획, 분배, 진행 파악, 결과 종합 |
| `researcher` | Opus 5.5 | xhigh | 연구 방향, 가설, 시스템 설계, 복잡한 원인 분석, 실험과 해석 |
| `executor` | Opus 5.5 | high | 일반 구현, 수정, 테스트, 디버깅, 리뷰 |
| `explainer` | Sonnet 5.5 | high | 왜 또는 어떻게 동작하는지 설명 |
| `runner` | Haiku 4.5 | low | 명령, 빌드, 검색, 파일·로그 확인 |

`max` effort는 기본값으로 사용하지 않습니다. 정말 필요한 작업에서만 사용자가
명시적으로 선택하는 것을 권장합니다.

## 설치

### 방법 1: 복사 설치

저장소를 아무 곳에나 내려받은 뒤 저장소 루트에서 실행합니다.

```bash
bash install.sh
```

설치 프로그램은 저장소 루트(`.git`, `state/` 제외)를 `~/.claude/fable`로
복사합니다. 이전 설치 폴더는 먼저 백업한 뒤, `state/`만 남기고 새 내용으로
교체하므로 예전 구조의 파일(`env.fish`, `shell-rc-path` 등)은 남지 않습니다.
`~/.claude/fable`이 이미 git checkout이면 덮어쓰지 않고 멈춥니다. 이 경우
그 폴더 안의 `install.sh`를 실행하십시오.

### 방법 2: 제자리 설치 (clone 또는 submodule)

저장소 자체를 `~/.claude/fable`에 두면 복사하지 않고 그 자리에서 설치합니다.

```bash
git clone git@github.com:jwpark-sungshin/fable-orchestration.git ~/.claude/fable
bash ~/.claude/fable/install.sh
```

`~/.claude`를 git으로 관리한다면 submodule로 추가할 수 있습니다.

```bash
cd ~/.claude
git submodule add git@github.com:jwpark-sungshin/fable-orchestration.git fable
bash fable/install.sh
```

제자리 설치는 checkout 안의 파일을 바꾸지 않습니다. `state/`는 `.gitignore`에
있으므로 `git status`에 나타나지 않습니다. 업데이트는 `git pull`(submodule이면
`git submodule update --remote fable`) 후 새 Claude 세션을 시작하면 됩니다.

### 설치 후

설치 프로그램이 출력한 셸 설정 파일을 다시 불러오고, Fable 모드를 켠 다음
정적 검사를 실행합니다.

```bash
source ~/.bashrc        # Zsh는 source ~/.zshrc
fable on
bash ~/.claude/fable/verify.sh
claude
```

`--resume`, `--continue`, `-c`로 연 세션은 저장된 모델을 유지할 수 있으므로
최초 검증에는 사용하지 마십시오.

## 설치 프로그램이 변경하는 항목

```text
~/.claude/fable/                     # 복사 설치일 때만 내용 교체 (state/ 유지)
~/.claude/.fable-state               # on/off 상태 (fable on/off가 기록)
~/.claude/agents/{executor,explainer,researcher,runner}.md
                                     # 켜져 있을 때 ../fable/agents/X.md 상대 링크
~/.local/bin/fable                   # ~/.claude/fable/bin/fable 링크
~/.claude/settings.json              # Fable PreToolUse 항목만 병합
셸 시작 파일                         # 표시된 두 marker 사이의 loader만 추가
```

- `settings.json`은 임시 파일에 쓴 뒤 교체하며, 기존 파일 권한(예: `0600`)을
  그대로 유지합니다. `settings.json`이 symlink면 링크는 그대로 두고 실제
  파일을 갱신합니다. 새로 만들 때는 `0600`입니다.
- 예전 설치가 등록한 `UserPromptSubmit` 게이트 항목은 제거합니다. 현재
  게이트는 Claude Code가 넘겨주는 `prompt_id`로 요청 단위를 구분하므로 그
  항목이 필요하지 않습니다.
- 셸 시작 파일에 이미 `fable/env.sh`를 불러오는 줄이 있으면 손대지 않습니다.
- 저장된 on/off 상태를 그대로 적용합니다. 처음 설치하면 꺼진 상태입니다.

바꾸기 전의 파일은 다음 디렉터리에 복사합니다.

```text
~/.claude/fable-backups/YYYYMMDD-HHMMSS-PID/
```

설치 프로그램은 프로젝트의 `CLAUDE.md`나 사용자의 `~/.claude/CLAUDE.md`를
수정하지 않습니다.

## 동작 원리

`env.sh`는 `claude` 셸 함수를 정의합니다. Fable 모드가 켜져 있으면 사용자가
직접 지정하지 않은 기본값만 추가해 원래 Claude Code를 실행합니다.

```text
--model claude-fable-5-1
--effort medium
--append-system-prompt-file ~/.claude/fable/fable.md
```

사용자가 `--model`이나 `--effort`를 직접 지정하면 해당 값이 우선합니다.
`update`, `install`, `doctor`, `mcp`, `plugin`, `agents` 하위 명령과 Fable
모드가 꺼져 있을 때는 인자를 바꾸지 않습니다.

메인 전용 프롬프트는 `CLAUDE.md`에서 import하지 않습니다. 사용자
`CLAUDE.md`는 서브에이전트도 읽을 수 있기 때문에, 그곳에 오케스트레이터
프롬프트를 넣으면 작업 agent가 자신도 오케스트레이터라고 오해할 수 있습니다.

`hooks/orchestration-gate.py`는 Fable 모드가 켜져 있을 때 메인 agent에만
적용됩니다.

- 메인 agent의 Bash 실행은 막고 `runner`·`executor`·`researcher`로 넘기게
  합니다. 서브에이전트의 Bash는 막지 않습니다.
- 메인 agent는 한 요청(`prompt_id`)에서 코드 파일을 최대 2개까지만 직접
  수정할 수 있습니다. 경로는 실제 경로(realpath)로 비교합니다. 문서 같은
  코드가 아닌 파일은 세지 않습니다.
- `prompt_id`가 없거나 입력을 읽을 수 없으면 막지 않습니다(fail open).

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
fable on       # 상태를 on으로 기록하고 agent 링크 생성
fable off      # 상태를 off로 기록하고 Fable이 만든 agent 링크만 제거
fable status
```

변경 사항은 새 Claude 세션부터 적용됩니다. `fable on`은 상대 링크
(`../fable/agents/X.md`)를 만들고, 예전 설치가 만든 절대 경로 링크도 Fable
링크로 인식합니다.

`fable status`의 `shell wrapper` 항목은 `~/.bashrc`만 검사합니다. Zsh나
`FABLE_RC_FILE`로 설치했다면 이 항목이 `[--]`로 보여도 정상일 수 있으며,
`verify.sh`는 `~/.zshrc`와 `FABLE_RC_FILE`도 확인합니다.

## 검증

```bash
fable status
bash ~/.claude/fable/verify.sh
```

새 세션을 시작했을 때 메인 모델이 Fable 5, effort가 `medium`인지 확인합니다.
서브에이전트는 `/agents`에서 `researcher`, `executor`, `explainer`, `runner`
중 어떤 이름으로 호출됐는지 확인합니다.

### `/agents`와 `claude agents`는 다릅니다

- `/agents`: 현재 대화 안에서 메인 agent가 호출한 서브에이전트
- `claude agents`: 독립적인 백그라운드 Claude 세션을 관리하는 화면

독립 세션을 agent 이름 없이 생성하면 별도의 메인 세션이므로 Fable을 사용하는
것이 정상입니다. 특정 역할을 독립 세션으로 시작하려면 해당 agent를 명시합니다.

```bash
claude --agent researcher --bg "Investigate the hypothesis"
```

## 개발자용 테스트

```bash
bash tests/smoke.sh     # 임시 HOME에서 설치·재설치·제거 시나리오 (gate.sh 포함)
bash tests/gate.sh      # 게이트 hook 단독 테스트
```

테스트는 임시 HOME만 사용하며 실제 `~/.claude`를 건드리지 않습니다.

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

`claude`가 함수로 표시되지 않으면 셸 설정 파일을 다시 불러오거나 새 터미널을
여십시오. 셸 함수를 우회하는 `command claude`는 Fable 기본값을 적용하지
않습니다.

### 모든 서브에이전트가 Fable을 사용함

`general-purpose`처럼 별도 모델이 없는 agent는 메인 모델을 상속할 수
있습니다. 다음 전역 변수가 설정돼 있으면 role별 설정을 덮어쓸 수 있으므로
제거합니다.

```bash
env | grep -E 'CLAUDE_CODE_SUBAGENT_MODEL|CLAUDE_CODE_EFFORT_LEVEL'
```

### explainer가 Opus를 사용함

```bash
env | grep ANTHROPIC_DEFAULT_SONNET_MODEL
```

Sonnet alias를 Opus로 전역 치환하는 값이 있으면 제거해야 합니다.

### 설정 파일의 모델 ID를 사용할 수 없음

Claude Code와 계정에서 사용할 수 있는 모델 이름을 먼저 확인하십시오. 모델
ID는 `agents/*.md`와 `env.sh`에 있습니다. 복사 설치라면 저장소에서 고친 뒤
`bash install.sh`를 다시 실행하고, 제자리 설치라면 `~/.claude/fable`에서
직접 고칩니다.

### `~/.local/bin/fable`을 찾지 못함

`~/.local/bin`을 `PATH`에 추가하거나 전체 경로로 실행합니다.

```bash
~/.local/bin/fable status
```

## 제거

```bash
bash ~/.claude/fable/uninstall.sh
```

제거 프로그램은 아무것도 영구 삭제하지 않습니다.

- `settings.json`과 수정할 셸 시작 파일을 먼저 백업 디렉터리에 복사한 뒤,
  Fable 항목과 marker 블록만 제거합니다.
- 시작 marker는 있는데 끝 marker가 없는 파일은 건드리지 않고 경고만
  출력합니다.
- Fable이 만든 agent 링크와 `~/.local/bin/fable` 링크를 제거하고,
  `~/.claude/.fable-state`와 복사 설치된 `~/.claude/fable`은 백업 디렉터리로
  옮깁니다.
- `~/.claude/fable`이 git checkout(clone 또는 submodule)이면 그 자리에
  남겨 둡니다. submodule을 없애려면 `~/.claude`에서
  `git submodule deinit fable && git rm fable`을 직접 실행하십시오.

```text
~/.claude/fable-backups/uninstall-YYYYMMDD-HHMMSS-PID/
```

설치 전에 존재했던 설정을 자동으로 추측해 복원하지는 않습니다. 필요하면
백업에서 원하는 파일만 직접 복원하십시오.

## 안전 범위

`orchestration-gate.py`는 메인 agent의 직접 실행과 코드 수정을 줄이기 위한
작업 흐름 보조 장치입니다. 완전한 보안 경계나 샌드박스가 아닙니다. Claude
Code의 권한 설정, Git diff 검토, 테스트, 백업을 대신하지 않습니다.

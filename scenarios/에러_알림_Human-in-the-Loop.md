# 에러 알림 워크플로우 — Human-in-the-Loop 설계

## 개요

| 항목 | 내용 |
|---|---|
| 시나리오명 | 에러 발생 시 사장님 즉시 알림 |
| 핵심 개념 | Human-in-the-Loop / 탈출구(Escape Hatch) 설계 |
| 적용 대상 | 기존 워크플로우의 모든 외부 API 노드 (Gmail, Twilio 등) |
| 알림 채널 | Gmail + Slack (+ 선택: Twilio SMS → 사장님 핸드폰) |
| 위치 | 별도 워크플로우 또는 기존 워크플로우에 추가 |

---

## 배경 및 목적

자동화 워크플로우는 외부 API 장애, 인증 만료, 네트워크 오류 등으로 언제든지 실패할 수 있다.
이때 "조용히 멈추는" 것이 아니라, **사장님에게 즉시 '무엇이, 왜 실패했는지'를 알려주는 탈출구**를 설계한다.

> 핵심 메시지 예시:  
> "🚨 오유진 고객 SMS 발송 실패 — Twilio 인증 오류 (Error 20003). 즉시 확인 바랍니다."

---

## 설계 원칙

1. **에러가 나도 워크플로우 전체가 죽지 않는다** — 오류 노드만 별도 경로로 빠진다.
2. **누가, 어디서, 왜** 실패했는지 메시지에 담는다.
3. **사람이 개입할 수 있는 창구**를 항상 열어둔다 (이메일 확인, Slack 확인, SMS 수신).
4. 재시도 로직은 별도로 두고, 알림은 **즉시** 보낸다.

---

## 알림 채널 구성

| 채널 | 용도 | 조건 |
|---|---|---|
| Gmail | 상세 오류 리포트 (로그 포함) | 항상 |
| Slack | 실시간 팀 공유 | 항상 |
| Twilio SMS | 사장님 핸드폰 즉시 알림 | 선택 (중요 오류만) |

> **카카오톡**: 캐나다 토론토 비즈니스 환경에서는 Kakao 비즈니스 채널 등록이 불가하므로 제외.  
> **개인 알림 대안**: Twilio SMS → 사장님 개인 번호로 직접 발송.

---

## 에러 트리거 방식

### 방식 A — Error Trigger 노드 (별도 워크플로우)

```
[Error Trigger] → [메시지 구성] → [Gmail 발송] → [Slack 발송] → [Twilio SMS]
```

- n8n의 **Error Trigger** 노드가 다른 워크플로우에서 발생한 오류를 감지
- 대상 워크플로우의 Settings → "Error Workflow"에 이 워크플로우를 지정
- 장점: 한 번 만들면 여러 워크플로우에 재사용 가능

---

## 오류 메시지 포함 정보

| 필드 | 내용 | n8n 표현식 |
|---|---|---|
| 워크플로우명 | 어떤 자동화에서 발생 | `{{ $workflow.name }}` |
| 실패 노드명 | Gmail인지 Twilio인지 | `{{ $json.execution.lastNodeExecuted }}` |
| 오류 메시지 | 구체적인 에러 내용 | `{{ $json.error.message }}` |
| 실행 ID | n8n에서 로그 추적용 | `{{ $execution.id }}` |
| 고객 이름 | 누구의 발송이 실패했는지 | `{{ $json.error.context?.고객이름 }}` |
| 발생 시각 | 언제 | `{{ $now.toISO() }}` |

---

## Gmail 오류 알림 템플릿

**제목**: `🚨 [자동화 오류] {{ $workflow.name }} — {{ $now.toFormat('yyyy-MM-dd HH:mm') }}`

**본문**:
```
안녕하세요, 사장님.

자동화 워크플로우에서 오류가 발생했습니다. 즉시 확인이 필요합니다.

━━━━━━━━━━━━━━━━━━━━
📋 워크플로우: {{ $workflow.name }}
⚠️  실패 노드: {{ $json.execution.lastNodeExecuted }}
❌ 오류 내용: {{ $json.error.message }}
🕐 발생 시각: {{ $now.toISO() }}
🔗 실행 ID:   {{ $execution.id }}
━━━━━━━━━━━━━━━━━━━━

n8n 대시보드에서 해당 실행 로그를 확인하고 수동 재처리 또는 고객 개별 연락 바랍니다.
```

---

## Slack 오류 알림 템플릿

**채널**: `#alerts` 또는 `#automation-errors`

```
🚨 *자동화 오류 발생*
> 워크플로우: {{ $workflow.name }}
> 실패 노드: {{ $json.execution.lastNodeExecuted }}
> 오류: {{ $json.error.message }}
> 시각: {{ $now.toISO() }}
> 실행 ID: {{ $execution.id }}
```

---

## Twilio SMS 알림 템플릿 (사장님 핸드폰)

```
[자동화오류] {{ $workflow.name }}에서 오류 발생.
노드: {{ $json.execution.lastNodeExecuted }}
오류: {{ $json.error.message }}
n8n 확인 요망.
```

> SMS는 160자 제한이 있으므로 핵심 정보만 포함.

---

## 크레딧 / 플레이스홀더

| 항목 | 플레이스홀더 |
|---|---|
| 관리자 이메일 | `PLACEHOLDER_ADMIN_EMAIL` |
| Slack Webhook URL | `PLACEHOLDER_SLACK_WEBHOOK_URL` |
| Slack 채널명 | `PLACEHOLDER_SLACK_CHANNEL` |
| Twilio 발신 번호 | `PLACEHOLDER_TWILIO_FROM` |
| 사장님 핸드폰 (수신) | `PLACEHOLDER_OWNER_PHONE` |

---

## 연결 대상 (기존 휴면고객 워크플로우 기준)

| 노드 | 오류 유형 | 우선순위 |
|---|---|---|
| Gmail 발송 | OAuth 만료, 수신자 주소 오류 | 높음 |
| Twilio SMS 발송 | API 인증 오류, 번호 형식 오류 | 높음 |
| AI 메시지 생성 | OpenAI API 한도 초과, 타임아웃 | 중간 |
| 고객 데이터 읽기 | Sheets 권한 오류 | 높음 |
| Sheets 업데이트 | 쓰기 권한 오류, 행 미발견 | 중간 |

---

## 실습 목표

1. Error Trigger 노드를 이용한 별도 알림 워크플로우 생성
2. 기존 휴면고객 워크플로우 Settings에 에러 워크플로우 연결
3. Gmail + Slack + Twilio SMS 3채널 알림 동시 발송 확인
4. 테스트: 의도적으로 API 크레딧을 잘못 설정해 오류 유발 → 알림 수신 확인

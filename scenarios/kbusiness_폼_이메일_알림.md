# K Business AI — 폼 제출 이메일 알림 시스템

## 개요
kbusiness.ca 웹사이트의 두 가지 문의 폼(클라이언트 상담 / 교육 문의)이 제출되면:
1. 프론트엔드가 DB에 INSERT 후 n8n webhook 호출
2. n8n이 폼 유형(lead / education)에 따라 분기
3. **운영자(Jini)**에게 새 문의 알림 이메일 발송
4. **신청자(고객)**에게 접수 확인 이메일 발송

---

## 워크플로 구성 (1개)

**워크플로명**: KB-Form-Email-Notification

---

## 데이터 구조

### DB 테이블 1: `leads` (클라이언트 상담 신청)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| lead_id | UUID | 고유 식별자 |
| name | VARCHAR(100) | 신청자 이름 |
| phone | VARCHAR(150) | 연락처 |
| business_type | VARCHAR(100) | 업종/비즈니스 유형 |
| problem_description | TEXT | 문의/고민 내용 |
| status | VARCHAR(50) | 상태 (기본값: new) |
| created_at | TIMESTAMP | 생성 시각 |
| email | VARCHAR(255) | 신청자 이메일 |

### DB 테이블 2: `education_inquiries` (교육 문의)
| 컬럼 | 타입 | 설명 |
|---|---|---|
| inquiry_id | UUID | 고유 식별자 |
| organization_name | VARCHAR(255) | 기관/회사명 |
| contact_name | VARCHAR(100) | 담당자 이름 |
| participant_count | VARCHAR(50) | 예상 수강 인원 |
| course_interest | VARCHAR(100) | 관심 과정 |
| message | TEXT | 추가 문의 내용 |
| preferred_start | VARCHAR(100) | 희망 시작 시기 |
| status | VARCHAR(50) | 상태 (기본값: new) |
| created_at | TIMESTAMP | 생성 시각 |
| contact_email | VARCHAR(255) | 담당자 이메일 |
| contact_phone | VARCHAR(100) | 담당자 연락처 |

---

## Webhook Payload 설계

프론트엔드가 DB INSERT 완료 후 아래 형식으로 n8n webhook을 POST 호출한다.

```json
{
  "type": "lead",
  "data": {
    "lead_id": "uuid-...",
    "name": "홍길동",
    "phone": "010-1234-5678",
    "business_type": "음식점",
    "problem_description": "예약 자동화를 도입하고 싶습니다.",
    "status": "new",
    "created_at": "2026-06-30T10:00:00Z",
    "email": "hong@example.com"
  }
}
```

```json
{
  "type": "education",
  "data": {
    "inquiry_id": "uuid-...",
    "organization_name": "ABC 회사",
    "contact_name": "김담당",
    "participant_count": "10명",
    "course_interest": "n8n 업무 자동화",
    "message": "사내 교육으로 진행하고 싶습니다.",
    "preferred_start": "2026년 8월",
    "status": "new",
    "created_at": "2026-06-30T10:00:00Z",
    "contact_email": "kim@abc.com",
    "contact_phone": "02-1234-5678"
  }
}
```

> **프론트엔드 연동 규칙**:
> - Webhook URL: `PLACEHOLDER_WEBHOOK_URL`
> - Method: POST
> - Content-Type: application/json
> - `type` 필드 필수 — 없으면 n8n에서 에러 처리

---

## 워크플로 흐름

```
Webhook Trigger (POST)
    │
    ├─ Validate 입력 (Code 노드)
    │   └─ type 필드 없음 → 400 응답 후 종료
    │
    ├─ IF: type === "lead"
    │   │
    │   ├─ [True] Lead 분기
    │   │   ├─ Gmail: Jini에게 새 상담 신청 알림
    │   │   └─ Gmail: 신청자에게 접수 확인
    │   │
    │   └─ [False] Education 분기
    │       ├─ Gmail: Jini에게 새 교육 문의 알림
    │       └─ Gmail: 담당자에게 접수 확인
    │
    └─ Respond to Webhook (200 OK)
```

---

## 노드 상세 설계

### 1. Webhook Trigger
- **Type**: `n8n-nodes-base.webhook`
- **Method**: POST
- **Path**: `kbusiness-form`
- **Response Mode**: `responseNode` (별도 응답 노드로 처리)
- **Authentication**: None (내부 호출)

### 2. Validate 입력 (Code 노드)
```javascript
const body = $input.first().json.body ?? $input.first().json;
const type = body.type;
const data = body.data;

if (!type || !['lead', 'education'].includes(type)) {
  throw new Error(`Invalid type: "${type}". Expected "lead" or "education".`);
}
if (!data) {
  throw new Error('Missing data field in payload.');
}

return [{ json: { type, data } }];
```

### 3. IF 분기: type === "lead"
- **조건**: `{{ $json.type === 'lead' }}`
- True → Lead 이메일 경로
- False → Education 이메일 경로

---

## 이메일 템플릿

### [Lead] Jini 수신 — 새 상담 신청 알림

```
제목: [K Business AI] 새 클라이언트 상담 신청 — {{ $json.data.name }}

성함: {{ $json.data.name }}
이메일: {{ $json.data.email }}
연락처: {{ $json.data.phone }}
업종: {{ $json.data.business_type }}
문의 내용:
{{ $json.data.problem_description }}

신청 일시: {{ $json.data.created_at }}
```

### [Lead] 신청자 수신 — 접수 확인

```
제목: [K Business AI] 상담 신청이 접수되었습니다

안녕하세요, {{ $json.data.name }}님.

K Business AI에 상담을 신청해 주셔서 감사합니다.
빠른 시일 내에 이메일({{ $json.data.email }})로 연락드리겠습니다.

문의하신 내용:
{{ $json.data.problem_description }}

K Business AI 드림
```

---

### [Education] Jini 수신 — 새 교육 문의 알림

```
제목: [K Business AI] 새 교육 문의 — {{ $json.data.contact_name }} ({{ $json.data.organization_name }})

기관/회사: {{ $json.data.organization_name }}
담당자: {{ $json.data.contact_name }}
연락처: {{ $json.data.contact_phone }}
이메일: {{ $json.data.contact_email }}
관심 과정: {{ $json.data.course_interest }}
예상 인원: {{ $json.data.participant_count }}
희망 시작: {{ $json.data.preferred_start }}
추가 문의:
{{ $json.data.message }}

신청 일시: {{ $json.data.created_at }}
```

### [Education] 담당자 수신 — 접수 확인

```
제목: [K Business AI] 교육 문의가 접수되었습니다

안녕하세요, {{ $json.data.contact_name }}님.

K Business AI 교육 문의를 접수하였습니다.
빠른 시일 내에 이메일({{ $json.data.contact_email }})로 연락드리겠습니다.

문의하신 과정: {{ $json.data.course_interest }}
희망 시작 시기: {{ $json.data.preferred_start }}

K Business AI 드림
```

---

## 노드 구성 요약

| 순번 | 노드명 | 타입 | 설명 |
|---|---|---|---|
| 1 | Webhook | webhook | POST 수신 |
| 2 | 입력 검증 | Code | type/data 유효성 확인 |
| 3 | 유형 분기 | IF | lead vs education |
| 4 | Lead 알림 (Jini) | Gmail | Jini에게 상담 신청 알림 |
| 5 | Lead 확인 (신청자) | Gmail | 신청자에게 접수 확인 |
| 6 | Education 알림 (Jini) | Gmail | Jini에게 교육 문의 알림 |
| 7 | Education 확인 (담당자) | Gmail | 담당자에게 접수 확인 |
| 8 | Respond to Webhook | respondToWebhook | 200 OK 응답 |

> **응답 전략**: 이메일 발송이 완료된 후 200 OK 응답.
> 이메일 실패 시 500 응답 → 프론트엔드 재시도 가능.

---

## Placeholder 목록

| Placeholder | 실제 값 |
|---|---|
| `PLACEHOLDER_WEBHOOK_URL` | n8n Webhook URL (활성화 후 발급) |
| `PLACEHOLDER_GMAIL_JINI` | Gmail OAuth2 credential |
| `PLACEHOLDER_JINI_EMAIL` | jinibyun@gmail.com |

---

## 에러 처리

| 상황 | 처리 방법 |
|---|---|
| type 필드 없음 | Code 노드에서 throw → webhook 500 응답 |
| 이메일 주소 없음 | 해당 Gmail 노드 skip (continueOnFail) |
| Gmail 발송 실패 | 재시도 2회 후 실패 로그 |

---

## 구현 순서
1. n8n에서 워크플로 생성 (MCP)
2. Webhook URL 확인 후 프론트엔드에 전달
3. Gmail credential 연결
4. 프론트엔드 폼 제출 → payload 형식 맞춰 연동
5. 실제 테스트 (lead / education 각각)
6. 워크플로 Activate

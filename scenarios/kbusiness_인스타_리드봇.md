# K Business AI — 인스타그램 AI 고객 응대 에이전트

## 개요

인스타그램 게시물 댓글과 DM을 AI Agent가 통합 처리하는 고객 응대 자동화 시스템.  
댓글로 첫 접점을 만들고, DM으로 이어지는 대화를 AI가 맥락을 기억하며 처리.  
ManyChat(Meta 공식 파트너)이 Instagram 권한 대리 처리,  
n8n AI Agent가 분석·대화·CRM 저장·오너 알림 담당.

**강의/데모 포인트:**  
"댓글 하나가 예약 확정까지 이어지는 완전 자동 고객 여정"  
AI Agent가 Tools를 직접 선택·실행하는 과정을 실시간으로 시연 가능.

---

## 기술 스택

| 항목 | 선택 | 비고 |
|---|---|---|
| Instagram 권한 | ManyChat (Meta 공식 파트너) | 심사 없이 댓글/DM 자동화 가능 |
| AI 모델 | GPT-4o-mini | 비용 효율적, 한국어 우수 |
| 대화 메모리 | Window Buffer Memory (10턴) | 세션키: instagram_handle |
| CRM | Airtable | instagram_leads 테이블 |
| 오너 알림 | Telegram | 폰 푸시 알림 |

---

## ManyChat 사전 설정

### 키워드 트리거
댓글에 아래 키워드 포함 시 자동 대댓글 + Webhook 발동:
- "예약", "할인", "정보", "가격", "DM", "문의", "얼마", "가능"

### 자동 대댓글
```
"DM으로 안내 보내드렸습니다! 😊"
```

### Webhook 설정
- **Webhook 1** (댓글): n8n `KB-Instagram-Comment` URL
- **Webhook 2** (DM 수신): n8n `KB-Instagram-DM` URL

### ManyChat Webhook 페이로드 구조

**댓글 이벤트 (Webhook 1):**
```json
{
  "type": "comment",
  "instagram_handle": "@hong_gildong",
  "comment_text": "예약 어떻게 해요?",
  "post_id": "POST_12345",
  "post_caption": "여름 프로모션 릴스",
  "subscriber_id": "MANYCHAT_SUBSCRIBER_ID",
  "timestamp": "2026-07-10T14:32:00Z"
}
```

**DM 수신 이벤트 (Webhook 2):**
```json
{
  "type": "dm",
  "instagram_handle": "@hong_gildong",
  "message_text": "다음 주 화요일 가능한가요?",
  "subscriber_id": "MANYCHAT_SUBSCRIBER_ID",
  "timestamp": "2026-07-10T14:35:00Z"
}
```

---

## 워크플로우 구성 (2개)

---

### Workflow 1: `KB-Instagram-Comment`

**역할:** 댓글 감지 → AI 첫 DM 발송 + 리드 신규 등록

```
ManyChat Webhook (댓글 이벤트)
    │
    ├─ Set: 데이터 정규화
    │   (instagram_handle, comment_text, post_context)
    │
    └─ AI Agent (GPT-4o-mini)
         ├── Window Buffer Memory (session: instagram_handle)
         ├── Tool: Airtable 조회 (기존 고객 여부 확인)
         ├── Tool: Airtable 저장 (신규 리드 등록)
         ├── Tool: ManyChat API (첫 DM 발송)
         └── Tool: Telegram (오너 알림)
```

**AI Agent System Prompt:**
```
당신은 인스타그램 첫 고객 응대 전문 AI입니다.

새 고객이 게시물에 댓글을 달았습니다.
댓글 내용과 게시물 맥락을 분석하여:

1. 의도 분류: booking(예약) / price(가격) / info(정보) / other
2. Airtable에서 기존 고객 여부 확인
3. 개인화된 첫 DM 메시지 작성 및 발송
   - 댓글 내용을 반드시 언급
   - 친근하고 전문적인 한국어
   - 템플릿 느낌 금지
4. Airtable에 신규 리드 저장 (intent, status: new)
5. 오너 Telegram 알림: "새 리드 등록"

예약 문의 → 예약 링크 안내
가격 문의 → 서비스 가격 안내 (PLACEHOLDER_PRICE_INFO)
일반 관심 → 웰컴 메시지 + 추가 정보 유도
```

---

### Workflow 2: `KB-Instagram-DM`

**역할:** DM 답장 수신 → AI 대화 이어가기 + 리드 상태 업데이트

```
ManyChat Webhook (DM 수신 이벤트)
    │
    ├─ Set: 데이터 정규화
    │   (instagram_handle, message_text)
    │
    └─ AI Agent (GPT-4o-mini)
         ├── Window Buffer Memory (session: instagram_handle)
         │    ← Workflow 1과 동일 세션 키로 대화 이력 공유
         ├── Tool: Airtable 조회 (리드 이력, 상태 확인)
         ├── Tool: Airtable 업데이트 (상태 변경, VIP 체크)
         ├── Tool: ManyChat API (DM 답장 발송)
         └── Tool: Telegram (예약 확정 or 에스컬레이션 알림)
```

**AI Agent System Prompt:**
```
당신은 인스타그램 고객 대화 전문 AI입니다.

이미 대화가 시작된 고객입니다.
이전 대화 맥락을 기억하며 자연스럽게 이어받아:

1. 고객 메시지 의도 파악
2. Airtable에서 리드 정보 조회
3. 상황에 맞는 답장 작성 및 발송:
   - 예약 가능 여부 확인 요청 → 가능 시간 안내
   - 예약 확정 → 확인 메시지 + Airtable status: converted
   - 추가 질문 → 정확히 답변
   - 답하기 어려운 내용 → "확인 후 안내드릴게요"
4. Airtable 리드 상태 업데이트
5. 예약 확정 or 3회 이상 문의 고객 → Telegram 오너 긴급 알림

[VIP 규칙]
contact_count >= 3 → is_vip = true → 오너 즉시 알림
```

---

## AI Agent Tools 상세

### Tool 1: Airtable 조회
```
목적: instagram_handle로 기존 리드 조회
입력: instagram_handle
출력: 리드 정보 (status, intent, contact_count, is_vip)
```

### Tool 2: Airtable 저장/업데이트
```
목적: 리드 생성 또는 상태 업데이트
입력: instagram_handle, intent, status, notes
출력: 저장 완료
```

### Tool 3: ManyChat API (DM 발송)
```
목적: 고객에게 DM 발송
API: POST https://api.manychat.com/fb/sending/sendContent
입력: subscriber_id, message_text
출력: 발송 완료
```

### Tool 4: Telegram (오너 알림)
```
목적: 사장님에게 실시간 알림
입력: 알림 내용 (리드 정보, 액션 타입)
출력: 메시지 전송 완료
```

---

## 전체 고객 여정 시나리오

```
① 14:32 고객 @hong_gildong이 릴스 댓글:
   "예약 어떻게 해요?"
        ↓
② ManyChat: 자동 대댓글 "DM 보내드렸습니다 😊"
   → n8n Webhook 1 호출
        ↓
③ AI Agent 분석:
   - 의도: booking (예약)
   - 기존 고객: 없음 (신규)
   - DM 생성: "안녕하세요! 예약 문의 주셨군요 😊
              저희 헤어 예약은 아래 링크에서 가능해요:
              📅 calendly.com/...
              원하시는 날짜나 서비스 있으시면 편하게 말씀해 주세요!"
        ↓
④ 14:32:30 고객 DM 도착 (30초 이내)
   Airtable 신규 리드 저장 (status: new)
   Telegram → 사장님 "새 리드: @hong_gildong / 예약문의"
        ↓
⑤ 14:35 고객 DM 답장:
   "다음 주 화요일 오후 가능한가요?"
        ↓
⑥ AI Agent (대화 기억):
   - 이전 대화: 예약 링크 보냄
   - 현재 의도: 특정 날짜 확인
   - DM: "화요일 오후는 2시, 4시 가능합니다!
          어느 시간이 좋으세요? 😊"
   Airtable 상태: new → talking
        ↓
⑦ 14:36 고객: "2시로 할게요!"
        ↓
⑧ AI Agent:
   - DM: "완벽해요! 화요일 오후 2시로 예약해드렸습니다 ✅
          예약 확인 문자 곧 받으실 거예요!"
   - Airtable status: talking → converted
   - Telegram → 사장님 "🎉 예약 확정! @hong_gildong / 화요일 2시"
```

---

## Telegram 메시지 포맷

```
[신규 리드]
📱 새 인스타 리드 — 14:32
👤 @hong_gildong
💬 댓글: "예약 어떻게 해요?"
📌 게시물: 여름 프로모션 릴스
🏷️ 분류: 예약문의 (HOT)
✅ AI DM 발송 완료

[예약 확정]
🎉 예약 확정!
👤 @hong_gildong
📅 화요일 오후 2시
✅ Airtable 업데이트 완료

[VIP 알림]
⭐ VIP 고객 문의!
👤 @hong_gildong (3회 이상 문의)
💬 "이번엔 염색도 같이 하고 싶어요"
→ 직접 응대 권장
```

---

## Airtable 데이터 모델

**Base명:** `KB-Instagram-CRM`  
**Table명:** `instagram_leads`

| 필드명 | Airtable 타입 | 설명 |
|---|---|---|
| `instagram_handle` | Single line text | 고객 계정 (@포함) |
| `subscriber_id` | Single line text | ManyChat subscriber ID |
| `first_comment` | Long text | 최초 댓글 내용 |
| `post_context` | Single line text | 댓글 달린 게시물 제목 |
| `intent` | Single select | booking / price / info / other |
| `status` | Single select | new / talking / converted / closed |
| `contact_count` | Number | 누적 문의 횟수 |
| `is_vip` | Checkbox | 3회 이상 문의 고객 |
| `last_interaction` | Date/Time | 마지막 대화 시각 |
| `notes` | Long text | AI 대화 요약 및 메모 |

---

## Placeholder 목록

| Placeholder | 설명 |
|---|---|
| `PLACEHOLDER_MANYCHAT_API_KEY` | ManyChat API Key |
| `PLACEHOLDER_MANYCHAT_PAGE_ID` | ManyChat Page/Bot ID |
| `PLACEHOLDER_OPENAI_API_KEY` | OpenAI API Key (n8n credential) |
| `PLACEHOLDER_AIRTABLE_BASE_ID` | Airtable Base ID (appXXXXXXX) |
| `PLACEHOLDER_AIRTABLE_TABLE_NAME` | instagram_leads |
| `PLACEHOLDER_TELEGRAM_BOT_TOKEN` | Telegram Bot Token |
| `PLACEHOLDER_TELEGRAM_CHAT_ID` | 오너 Telegram Chat ID |
| `PLACEHOLDER_BOOKING_LINK` | 예약 링크 (Calendly 등) |
| `PLACEHOLDER_PRICE_INFO` | 서비스별 가격 정보 |

---

## 노드 구성 요약

### Workflow 1: KB-Instagram-Comment

| 순번 | 노드명 | 타입 | 설명 |
|---|---|---|---|
| 1 | 댓글 Webhook | webhook | ManyChat 댓글 이벤트 수신 |
| 2 | 데이터 정규화 | Set | handle, comment, post 추출 |
| 3 | 인스타 응대 Agent | AI Agent | 의도분석 + DM생성 + 저장 + 알림 |
| 3-1 | GPT-4o-mini | LLM | 언어 모델 |
| 3-2 | 대화 메모리 | Window Buffer Memory | 10턴 기억, 세션: instagram_handle |
| 3-3 | Airtable 조회 Tool | HTTP Request Tool | 기존 리드 확인 |
| 3-4 | Airtable 저장 Tool | HTTP Request Tool | 신규 리드 등록 |
| 3-5 | ManyChat DM Tool | HTTP Request Tool | 첫 DM 발송 |
| 3-6 | Telegram Tool | Telegram Tool | 오너 신규 리드 알림 |

### Workflow 2: KB-Instagram-DM

| 순번 | 노드명 | 타입 | 설명 |
|---|---|---|---|
| 1 | DM Webhook | webhook | ManyChat DM 수신 이벤트 |
| 2 | 데이터 정규화 | Set | handle, message 추출 |
| 3 | 대화 지속 Agent | AI Agent | 대화이력 + 답장 + 상태업데이트 |
| 3-1 | GPT-4o-mini | LLM | 언어 모델 |
| 3-2 | 대화 메모리 | Window Buffer Memory | 10턴 기억, 세션: instagram_handle |
| 3-3 | Airtable 조회 Tool | HTTP Request Tool | 리드 이력 조회 |
| 3-4 | Airtable 업데이트 Tool | HTTP Request Tool | 상태 변경 |
| 3-5 | ManyChat DM Tool | HTTP Request Tool | 답장 발송 |
| 3-6 | Telegram Tool | Telegram Tool | 예약확정/VIP 알림 |

---

## 비용 참고

| 항목 | 무료 | 유료 |
|---|---|---|
| ManyChat | 25 Active Contacts/월 | Pro $15/월 (500명) |
| n8n | 자체 서버 | — |
| OpenAI | — | gpt-4o-mini 약 $0.001/메시지 |

강의 구성: 무료 플랜으로 구조 학습 → 실전 배포 시 Pro 전환 안내

---

## 구현 순서

1. ManyChat 계정 + Instagram 연결 + 키워드/Webhook 설정
2. Airtable `KB-Instagram-CRM` 베이스 + `instagram_leads` 테이블 생성
3. Telegram Bot 생성 (@BotFather → /newbot)
4. Workflow 1 `KB-Instagram-Comment` 생성
5. Workflow 2 `KB-Instagram-DM` 생성
6. ManyChat Webhook URL 등록 (활성화 후 URL 확인)
7. 테스트 계정으로 전체 흐름 검증
8. 워크플로우 백업

---

## 검증 방법

| 단계 | 테스트 방법 |
|---|---|
| 댓글 감지 | 테스트 인스타 계정으로 키워드 댓글 → ManyChat 감지 확인 |
| 첫 DM | 댓글 후 30초 내 DM 수신 확인 |
| 대화 연속성 | DM 답장 3회 → AI가 이전 맥락 기억하는지 확인 |
| 예약 확정 | "확정" 메시지 → Airtable status: converted 확인 |
| VIP 처리 | contact_count >= 3 → is_vip = true + Telegram 알림 확인 |
| CRM 저장 | Airtable 리드 생성 + 상태 업데이트 정확성 확인 |

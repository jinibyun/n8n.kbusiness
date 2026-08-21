# 시나리오: KB-Workflow-Builder (요구사항 수집 → 시나리오 자동 생성)

## Context

kBusiness.ca 로그인 사용자가 자신의 비즈니스 프로세스 자동화 요구사항을
채팅으로 제출하면, AI Agent가 구조화된 질문으로 요구사항을 정제하고
n8n 워크플로우 시나리오 md를 자동 생성해 주는 서비스.

**핵심 설계 원칙:**
- Form = Chat: 별도 폼 없이 AI가 채팅으로 항목별 질문
- Draft 검토도 채팅 안에서 (동적 피드백)
- Email은 최종 산출물 전달 전용
- 기존 KB-AI-Chatbot과 동일한 Webhook 패턴 적용
- 사용 횟수 제한: 무료 3회 (Neon DB 카운팅)

---

## 사용자 여정 (Chat 흐름)

```
1. 사용자: /workflow-builder 접속 (로그인 필수)
2. AI: 인사 + 기존 자료 첨부 또는 긴 텍스트 붙여넣기 안내 (선택사항)
   → "자동화하려는 프로세스에 대한 문서, 절차서, 샘플 데이터가 있으면
      첨부하거나 붙여넣기 해주세요. 없으면 '없음'으로 진행합니다."
2-1. 사용자: (선택) 파일 첨부 또는 텍스트 붙여넣기
     → 자료 있으면: AI가 내용 분석 후 중복 질문 생략하여 진행
     → 자료 없으면: 순서대로 질문
3. AI ↔ 사용자: 항목별 질문/답변 반복 (최대 8개 항목)
4. AI: 애매한 답변 → 즉시 추가 질문으로 정제
5. AI: 전체 수집 완료 → Draft 요약을 채팅에 출력
6. 사용자: 수정/확인
7. AI: 확정 → 산출물 생성 → Drive 저장 + 이메일 발송
8. AI: 채팅에 완료 메시지 + Drive 링크 안내
```

**파일 첨부 지원 형식**: PDF, Word (.docx), Excel (.xlsx), 텍스트 붙여넣기
**Frontend 처리**: multipart/form-data로 파일 전송 → n8n Webhook 수신 → Extract from File 노드로 텍스트 추출 → chatInput에 포함하여 AI에게 전달

---

## 워크플로우 구성

```
[kBusiness.ca /workflow-builder - 로그인 사용자]
    ↓ POST { chatInput, sessionId: user_id, userEmail }
[Webhook /workflow-builder-api]
    ↓
[Usage Check (Code Tool)] → Neon DB
    count ≥ 3 → 차단 메시지 반환
    count < 3 → 계속
    ↓
[AI Agent: KB-Workflow-Builder Agent]
    GPT-4o-mini
    Memory Buffer (sessionId = user_id)
    ↓ Tools
    ├─ [generate_scenario_md] ← 확정 시 호출
    ├─ [save_to_google_drive] ← user_id 폴더에 저장
    ├─ [send_final_email]     ← Gmail, 최종 산출물만
    └─ [increment_usage]      ← Neon DB usage_count +1
    ↓
[Respond to Webhook]
{ answer: "AI 응답 텍스트" }
```

---

## AI Agent 수집 항목 (채팅 질문 순서)

AI가 아래 항목을 채팅으로 하나씩 질문한다.
애매하면 즉시 추가 질문, 명확하면 다음 항목으로 이동.

| # | 항목 | 예시 질문 | 목적 |
|---|---|---|---|
| 1 | 프로세스 이름/목적 | "어떤 업무를 자동화하고 싶으신가요?" | 전체 맥락 파악 |
| 2 | 트리거 | "언제 실행되어야 하나요? (매일 정해진 시간 / 이벤트 발생 시 / 폼 제출 시)" | 트리거 타입 결정 |
| 3 | 입력 데이터 | "데이터는 어디서 오나요? (Excel, Google Sheets, 이메일, 외부 API 등)" | 소스 노드 결정 |
| 4 | 핵심 처리 | "중간에 어떤 작업이 필요한가요? (변환, 분류, 계산, AI 판단 등)" | 처리 노드 결정 |
| 5 | 출력/저장 | "최종 결과는 어디로 가야 하나요? (Drive, DB, 이메일, Slack 등)" | 출력 노드 결정 |
| 6 | 외부 연동 | "현재 사용 중인 툴/서비스가 있나요?" | credential 목록 |
| 7 | AI 필요 여부 | "분류/판단/생성 같은 AI 기능이 필요한가요?" | AI Agent 포함 여부 |
| 8 | 에러/예외 처리 | "실패하면 어떻게 해야 하나요? (알림, 재시도, 무시)" | 신뢰성 설계 |

---

## Draft 검토 (채팅 내 동적 피드백)

8개 항목 수집 완료 후 AI가 채팅에 아래 형식으로 Draft 요약 출력:

```
📋 수집된 요구사항 요약입니다. 확인해 주세요.

■ 프로세스: [수집된 내용]
■ 트리거: [수집된 내용]
■ 입력: [수집된 내용]
■ 처리: [수집된 내용]
■ 출력: [수집된 내용]
■ 연동 툴: [수집된 내용]
■ AI 필요: [Yes/No + 용도]
■ 에러 처리: [수집된 내용]

수정할 항목이 있으면 말씀해 주세요.
모두 맞으면 "확정" 이라고 입력해 주세요.
```

사용자가 수정 요청 시 → 해당 항목만 재수집 → 다시 Draft 출력
사용자가 "확정" 입력 시 → 산출물 생성 단계로 이동

---

## 산출물 생성 (확정 후)

### generate_scenario_md Tool (Code Tool)
수집된 항목을 기반으로 scenario md 텍스트 생성:
- 워크플로우 이름, 목적, 트리거, 노드 구성, 에러 처리
- `00.system-prompt.md` + `01.user-prompt-template.md` 적용 형식
- Placeholder 포함 (실제 credential 값 제외)

### save_to_google_drive Tool (Google Drive Tool)
- 저장 경로: `Workflow Builder / {user_id} / {YYYY-MM-DD}_{프로세스명}.md`
- 동일 이름 파일 덮어쓰기

### send_final_email Tool (Gmail Tool)
- 수신: 로그인 사용자 이메일 (`userEmail`)
- 제목: `[KB Workflow Builder] 시나리오 생성 완료 - {프로세스명}`
- 본문: 요약 + Drive 파일 링크

### increment_usage Tool (Code Tool → Neon DB HTTP)
- `workflow_builder_usage` 테이블 usage_count +1

---

## 채팅 완료 메시지

```
✅ 시나리오 생성이 완료되었습니다!

📄 파일명: {프로세스명}.md
📁 Drive 저장: [링크]
📧 이메일 발송: {userEmail}

남은 무료 횟수: {3 - usage_count}회
```

---

## AI Agent 시스템 프롬프트 핵심

```
역할: 너는 n8n 워크플로우 요구사항 수집 전문가다.
      kBusiness.ca 사용자의 비즈니스 프로세스 자동화 요구사항을
      채팅으로 수집하고 정제하는 것이 목표다.

질문 원칙:
1. 한 번에 하나의 항목만 질문한다.
2. 답변이 모호하면 구체적인 예시를 들어 추가 질문한다.
3. 기술 용어는 쉬운 말로 바꿔서 질문한다.
4. 8개 항목이 모두 명확해지면 Draft 요약을 출력한다.
5. 사용자가 "확정" 입력 시 generate_scenario_md 도구를 호출한다.
6. 이메일은 최종 확정 후 send_final_email 도구로만 발송한다.

금지:
- 8개 항목 수집 전 산출물 생성 금지
- 사용자 확인 전 이메일 발송 금지
- credential 실제 값 요청 금지

파일/텍스트 첨부 처리:
- 첨부 자료가 있으면 내용을 분석하여 이미 답변된 항목은 질문 생략
- 불명확한 부분만 추가 질문
- 첨부 없어도 정상 진행
```

---

## Frontend (kBusiness.ca) 추가 사항

### 신규 페이지: `/workflow-builder`
- 로그인 미완료 시 `/login` 리다이렉트
- 기존 챗봇 UI 컴포넌트 재사용
- API endpoint: `POST https://n8n.kbusiness.ca/webhook/workflow-builder-api`
- 요청 payload: `{ chatInput, sessionId: userId, userEmail }`
- 상단 배지: "남은 무료 횟수: N회" 표시

### Neon DB 추가 테이블

```sql
CREATE TABLE workflow_builder_usage (
  user_id TEXT PRIMARY KEY,
  usage_count INTEGER DEFAULT 0,
  last_used_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## n8n Nodes 구성 (KB-AI-Chatbot 패턴 기반)

| 노드 | 타입 | 역할 |
|---|---|---|
| Webhook | `n8n-nodes-base.webhook` | POST /workflow-builder-api |
| Usage Check | `@n8n/n8n-nodes-langchain.toolCode` | Neon DB usage_count 조회/차단 |
| KB-WFB Agent | `@n8n/n8n-nodes-langchain.agent` v3.1 | 요구사항 수집 AI |
| OpenAI gpt-4o-mini | `@n8n/n8n-nodes-langchain.lmChatOpenAi` | 언어모델 |
| Memory Buffer | `@n8n/n8n-nodes-langchain.memoryBufferWindow` | 세션 메모리 (user_id 키) |
| generate_scenario_md | `@n8n/n8n-nodes-langchain.toolCode` | 시나리오 md 생성 |
| save_to_google_drive | `n8n-nodes-base.googleDriveTool` | Drive 저장 |
| send_final_email | `n8n-nodes-base.gmailTool` | 최종 이메일 발송 |
| increment_usage | `@n8n/n8n-nodes-langchain.toolCode` | usage_count +1 |
| Respond to Webhook | `n8n-nodes-base.respondToWebhook` | 채팅 응답 반환 |

---

## Placeholder 목록

| 이름 | 설명 |
|---|---|
| PLACEHOLDER_OPENAI_API_KEY | OpenAI API Key |
| PLACEHOLDER_GMAIL_OAUTH | Gmail OAuth2 credential |
| PLACEHOLDER_GDRIVE_OAUTH | Google Drive OAuth2 credential |
| PLACEHOLDER_NEON_DB_URL | Neon DB connection string (usage 카운팅용) |
| PLACEHOLDER_GDRIVE_ROOT_FOLDER_ID | Workflow Builder 루트 폴더 ID |

---

## 검증 방법

1. 로그인 사용자로 `/workflow-builder` 접속
2. 채팅으로 8개 항목 응답
3. Draft 요약 → "확정" 입력
4. Drive에 md 파일 저장 확인
5. 이메일 수신 확인
6. Neon DB usage_count +1 확인
7. 3회 초과 시 차단 메시지 확인

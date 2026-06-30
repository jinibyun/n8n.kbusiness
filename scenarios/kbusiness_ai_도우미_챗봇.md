# K Business AI 도우미 챗봇 시스템

## 개요
K Business AI 웹사이트(kbusiness.ca)에 임베드되는 한국어 챗봇.  
비즈니스 자동화 서비스 및 교육 관련 Q&A와 상담 신청을 처리한다.  
Vector DB(Qdrant)에 저장된 K Business AI 소개 자료를 기반으로 답변하며,  
상담 신청 시 운영자(Jini)에게 Gmail 알림 + 고객에게 접수 확인 이메일을 발송한다.

---

## 워크플로 구성 (2개)

### 워크플로 A: KB-Knowledge-Loader (Vector DB 데이터 입력)
- 목적: Qdrant 컬렉션 `kbusiness_ai`에 지식 소스를 적재
- 수동 실행 또는 파일 업로드 트리거

### 워크플로 B: KB-AI-Chatbot (웹사이트 챗봇)
- 목적: 웹사이트 방문자와 대화 — Q&A + 상담 신청 처리
- Chat Trigger (public webhook) 방식으로 웹사이트에 임베드

---

## 워크플로 A: KB-Knowledge-Loader 상세

### 트리거
- Manual Trigger (필요할 때마다 수동 실행)
- 입력: 텍스트 파일 / HTML / PDF / 마크다운 업로드

### 처리 흐름
```
파일 업로드 (Manual/Form Trigger)
    → 파일 형식 판별 (Code 노드)
    → 텍스트 추출
    → Recursive Character Text Splitter (chunkSize: 500, overlap: 50)
    → OpenAI Embeddings (text-embedding-3-small)
    → Qdrant Vector Store INSERT (컬렉션: kbusiness_ai)
    → 완료 로그 출력
```

### Qdrant 컬렉션 설정
| 항목 | 값 |
|---|---|
| 컬렉션명 | `kbusiness_ai` |
| 임베딩 모델 | text-embedding-3-small |
| Chunk Size | 500 |
| Chunk Overlap | 50 |

### 적재 대상 소스 (순차 업로드)
| 소스 | 형식 | 비고 |
|---|---|---|
| kbusiness.ca 웹사이트 내용 | 텍스트/마크다운 | 서비스 소개, 컨설팅, 교육 |
| 수업 커리큘럼 문서 | 마크다운/PDF | n8n 강의 커리큘럼 |
| n8n 튜터리얼 | HTML | 기존 HTML 파일 |
| 서비스 소개서 | PDF | 제작 후 추가 |
| 회사 소개 | 마크다운 | 제작 후 추가 |

> **운영 정책**: 소스 업데이트 시 해당 컬렉션 재적재 또는 추가 적재

---

## 워크플로 B: KB-AI-Chatbot 상세

### 챗봇 페르소나
- **이름**: K Business AI 도우미
- **언어**: 한국어 고정
- **톤**: 전문적이고 친절하게, 간결하게 답변
- **역할 범위**:
  - K Business AI 서비스/교육 관련 Q&A
  - 상담 신청 접수 (이름/이메일/관심 분야/문의 내용 수집)
  - 범위 외 질문은 정중히 안내

### 트리거
- `@n8n/n8n-nodes-langchain.chatTrigger`
- mode: `webhook`, public: `true`
- 웹사이트 임베드용 Chat Widget URL 발급

### 시스템 프롬프트
```
너는 K Business AI의 공식 AI 도우미야.
한국어로만 답변하며, 제공된 문서(Vector DB)를 기반으로 정확하게 답변한다.

[역할]
1. K Business AI 서비스(AI 자동화 컨설팅, n8n 교육)에 대한 질문에 답변
2. 문서에 없는 내용은 "정확한 정보를 위해 직접 문의해 주세요"로 안내
3. 사용자가 상담 신청 의향을 보이면 아래 정보를 순차적으로 수집:
   - 성함
   - 이메일 주소
   - 관심 분야 (AI 자동화 컨설팅 / n8n 교육 / 기타)
   - 문의 내용 (자유 기입)
4. 모든 정보 수집 완료 후 "신청을 접수했습니다" 안내 후 booking_tool 호출

[금지]
- 가격/일정 확정 답변 금지 (문서에 없는 경우)
- 경쟁사 비교 금지
- 한국어 외 언어로 전환 금지
```

### 노드 구성

```
Chat Trigger (public webhook)
    └→ AI Agent (gpt-4o-mini)
         ├── OpenAI Chat Model (gpt-4o-mini)
         ├── Memory Buffer Window (contextWindow: 10)
         ├── Tool: Qdrant Vector Store Retrieval (kbusiness_ai)
         └── Tool: 상담신청 처리 (n8n Tool 노드 → Sub-workflow)
                    ↓
             [상담신청 Sub-flow]
             Set 노드 (신청 데이터 정리)
                 ├→ Gmail: Jini에게 신청 알림
                 └→ Gmail: 고객에게 접수 확인 이메일
```

### AI Agent 설정
| 항목 | 값 |
|---|---|
| 모델 | gpt-4o-mini |
| 메모리 | Buffer Window (10턴) |
| Vector Tool | Qdrant Retrieval (kbusiness_ai) |
| 상담신청 Tool | n8n Tool (상담 접수 서브플로) |

### 상담신청 처리 (Tool 호출 시)

**수집 데이터**
| 필드 | 타입 | 필수 |
|---|---|---|
| name | string | Y |
| email | string | Y |
| interest | string (컨설팅/교육/기타) | Y |
| message | string | Y |

**Jini 수신 이메일 (Gmail)**
```
제목: [K Business AI] 새 상담 신청 - {name}
내용:
  성함: {name}
  이메일: {email}
  관심 분야: {interest}
  문의 내용: {message}
  신청 일시: {timestamp}
```

**고객 수신 이메일 (Gmail)**
```
제목: [K Business AI] 상담 신청이 접수되었습니다
내용:
  안녕하세요, {name}님.
  상담 신청이 정상적으로 접수되었습니다.
  빠른 시일 내에 이메일({email})로 연락드리겠습니다.
  감사합니다.

  K Business AI 드림
```

---

## Placeholder 목록
| Placeholder | 실제 값 |
|---|---|
| `PLACEHOLDER_OPENAI_API` | OpenAI API Key credential |
| `PLACEHOLDER_QDRANT_API` | Qdrant credential (기존 사용 중) |
| `PLACEHOLDER_GMAIL_JINI` | Jini Gmail credential |
| `PLACEHOLDER_JINI_EMAIL` | jinibyun@gmail.com |
| `PLACEHOLDER_QDRANT_COLLECTION` | kbusiness_ai |

---

## 웹사이트 임베드 방식
n8n Chat Trigger 활성화 후 생성되는 Chat Widget 스크립트를 kbusiness.ca에 추가:
```html
<!-- kbusiness.ca에 추가 -->
<link href="https://n8n.kbusiness.ca/chat/assets/chat.css" rel="stylesheet" />
<script type="module">
  import { createChat } from 'https://n8n.kbusiness.ca/chat/assets/chat.js'
  createChat({
    webhookUrl: 'PLACEHOLDER_CHAT_WEBHOOK_URL',
    initialMessages: ['안녕하세요! K Business AI 도우미입니다. 무엇을 도와드릴까요?'],
    i18n: {
      en: {
        title: 'K Business AI 도우미',
        subtitle: 'AI 자동화 · 교육 문의',
        inputPlaceholder: '메시지를 입력하세요...',
      }
    }
  })
</script>
```

---

## 구현 순서
1. Vector DB 컬렉션 `kbusiness_ai` 생성 확인
2. 워크플로 A 생성 → 소스 파일 순차 적재
3. 워크플로 B 생성 → 로컬 테스트
4. 워크플로 B Activate → Chat Webhook URL 확인
5. kbusiness.ca에 임베드 스크립트 추가
6. 실제 대화 테스트 (Q&A + 상담 신청 플로)

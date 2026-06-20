# 기능 요구사항: USD/CAD 환율 모니터링 및 슬랙 임계값 알림 시스템

## 1. 개요 및 트리거
- **실행 주기:** 매일 오전 9시부터 오후 6시까지 30분 간격으로 자동 실행 (Schedule Trigger 노드 사용).
- **목적:** 외환 시장의 변동성을 모니터링하여 설정한 저점/고점 임계값을 돌파할 때 슬랙 채널에 공지 메시지 발행.

## 2. 데이터 수집 (HTTP Request)
- **대상 API:** 외환 허브 API (`https://api.exchangerate-api.com/v6/latest/USD`)
- **메서드:** GET
- **인증:** Headers에 `Authorization: Bearer {{ $secrets.EXCHANGE_API_KEY }}` 전달 (더미 플레이스홀더 처리 가능).
- **기능:** 응답 데이터에서 CAD 환율 값(`$json.rates.CAD`)을 추출.

## 3. 조건 분기 및 로직 제어 (IF & Code)
- **분기 조건 (IF Node):**
  - **조건 A (고환율 통제):** `CAD` 환율이 `1.3800` 이상인 경우.
  - **조건 B (저환율 통제):** `CAD` 환율이 `1.3200` 이하인 경우.
- **데이터 정제 (Code Node):**
  - 조건 A 또는 B에 걸린 데이터만 진입.
  - Luxon 라이브러리를 사용하여 현재 통보 시간(`YYYY-MM-DD HH:mm:ss`)을 생성하고, 메시지 본문에 들어갈 텍스트를 포맷팅.
  - 예시 표현식: `{{ $now.setZone('America/Toronto').toFormat('yyyy-MM-DD HH:mm:ss') }}`

## 4. 공지 및 알림 배포 (Slack)
- **대상 노드:** Slack Node (`n8n-nodes-base.slack`)
- **인증:** Slack OAuth2 (또는 Webhook URL 사용).
- **출력 포맷:** 단순 텍스트가 아닌 Slack Block Kit 구조의 Rich Text로 공지 포맷팅.
  - **헤더 블록:** 🚨 [환율 변동성 경보] USD/CAD 임계값 돌파
  - **섹션 블록:** 현재 환율 및 기준 시간 표기. 방어적 코딩(`??`)을 적용하여 데이터 유실 방지.
  - 예시 본문: `*현재 환율:* {{ $json.currentRate ?? '조회 실패' }} CAD (기준: {{ $json.alertTime }})`
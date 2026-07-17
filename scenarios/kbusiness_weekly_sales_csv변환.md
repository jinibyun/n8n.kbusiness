# 시나리오: Weekly Sales xlsx → CSV 변환 (n8n 워크플로우)

## Context

매일 Google Drive에 올라오는 weekly sales xlsx 파일을 flat CSV로 변환하는 n8n 워크플로우.
외부 의존성 없이 n8n 내장 노드만 사용. AI 연동 없음.
xlsx는 수정하지 않고, 변환된 CSV를 Google Drive 동일 위치에 같은 이름(.csv)으로 저장.

---

## xlsx 구조

한 시트, 여러 주 가로 연속 배치:
- **Col A**: 메트릭명 (Gross sale, Ubereats, Balance...)
- **Col B**: 서브 레이블 (POS, Card batch...)
- **Col C~**: 날짜별 값 (15-Dec, 16-Dec, ...)
- Row 1: 날짜 헤더 / Row 2: 요일 / Row 3~: 데이터

스킵 대상 행:
`Weekly Total Sales` / `Weekly Cash Total` / `Weekly sales after commission` / `APPS fee`

---

## 워크플로우 구성

```
Schedule Trigger (11PM)
    ↓
Google Drive — xlsx 다운로드 (binary)
    ↓
Spreadsheet File — xlsx → JSON rows (전체 행 배열)
    ↓
Code 노드 — transpose + 집계행 제거 → flat rows
    ↓
Spreadsheet File — JSON → CSV binary
    ↓
Google Drive — CSV 업로드 (동일 폴더, 동일 이름.csv)
```

---

## 노드별 설정

### 1. Schedule Trigger
- 매일 23:00 KST

### 2. Google Drive — 다운로드
- Operation: `file` / `download`
- File ID: `PLACEHOLDER_GDRIVE_FILE_ID`
- Output: binary (xlsx)

### 3. Spreadsheet File — 읽기
- Operation: `fromFile`
- Header Row: false (날짜값 중복 방지, raw 처리)
- 출력: 각 행이 하나의 item, 키는 컬럼 인덱스(0, 1, 2...)

### 4. Code 노드 — 변환 로직 (JavaScript, runOnceForAllItems)

처리 순서:
1. `$input.all()` → 전체 행 배열 수집
2. Row 0 (날짜행)에서 날짜 컬럼 인덱스 탐지 (Date 객체 또는 "15-Dec" 형태)
3. Row 0 → `date`, Row 1 → `day_of_week`
4. 메트릭명(Col A) → 행 번호 매핑 빌드 (스킵 레이블 제외)
5. 날짜 컬럼마다 flat record 생성 (22컬럼)
6. `null`/`undefined` → 0 또는 빈 문자열 처리
7. `date`: ISO 형식 (2024-12-15)으로 정규화

출력: flat records 배열 (날짜 수만큼 items)

### 5. Spreadsheet File — 쓰기
- Operation: `toFile`
- File Format: CSV
- File Name: `PLACEHOLDER_GDRIVE_FILE_NAME.csv`

### 6. Google Drive — 업로드
- Operation: `file` / `upload`
- Parent Folder ID: `PLACEHOLDER_GDRIVE_FOLDER_ID` (xlsx와 동일 폴더)
- 동일 이름 파일 덮어쓰기

---

## CSV 컬럼 (22개)

| 컬럼명 | 원본 행 |
|---|---|
| date | Row 1 날짜 |
| day_of_week | Row 2 요일 |
| gross_sale | Gross sale |
| card_without_tips | Card without tips |
| paid_out | Paid out |
| card_with_tips | Card with tips |
| cash_sale_incl_gross | Cash sale [incl.in gross] |
| ubereats | Ubereats (sales) |
| doordash | Doordash (sales) |
| cash_and_carry | Cash and carry |
| total_sale | Total Sale |
| cash_expenses | Cash expenses |
| cash_left | Cash Left |
| actual_cash | Actual Cash |
| total_cash | Total Cash |
| balance | Balance |
| ubereats_commission_rate | Apps fee > Ubereats % |
| ubereats_commission | Apps fee > Ubereats 금액 |
| doordash_commission_rate | Apps fee > Doordash % |
| doordash_commission | Apps fee > Doordash 금액 |
| total_commissions | Total commissions |
| total_sale_after_commission | Total sale after commission |

---

## 검증

- 15-Dec 행 `gross_sale` = 1,056.69 (스크린샷 대조)
- 총 행 수 = 날짜 수 (주간 집계 행 없음)
- 컬럼 수 = 22개
- CSV Google Drive 저장 확인

---

## Placeholder

| 이름 | 설명 |
|---|---|
| PLACEHOLDER_GDRIVE_FILE_ID | xlsx 파일 Google Drive ID |
| PLACEHOLDER_GDRIVE_FOLDER_ID | 저장 폴더 Google Drive ID (xlsx와 동일) |
| PLACEHOLDER_GDRIVE_FILE_NAME | xlsx 파일명 (확장자 제외) |

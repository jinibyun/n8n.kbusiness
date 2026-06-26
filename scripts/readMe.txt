backup-n8n-workflows.ps1 사용 방법

=======
핵심 기능
=======
1. 전체 워크플로우 조회 후 개별 상세를 JSON으로 저장
2. 기본 저장 위치: source/오늘날짜(yyyyMMdd)
3. API 키 우선순위:
   - 파라미터 -ApiKey
   - 환경변수 N8N_API_KEY
   - fetch_workflow.http의 X-N8N-API-KEY 자동 추출
4. 테스트 모드: -DryRun (파일 생성 없이 경로만 출력)

==============
중요 확인 결과
==============
1. 현재 Public API 기준으로는 폴더 메타데이터 엔드포인트가 없어 폴더 구조를 가져오지 못합니다.
2. 그래서 지금은 날짜 폴더 아래 평면(Flat) 저장으로 동작합니다.
3. 스크립트에서 이 상황을 경고로 출력하도록 반영했습니다.

==============
사용법 요약
==============
1. 미리보기(저장 안 함)
   backup-n8n-workflows.ps1 -DryRun

2. 실제 백업
   backup-n8n-workflows.ps1

3. 날짜 폴더 직접 지정
   backup-n8n-workflows.ps1 -DateFolder 20260619

4. API 키 직접 지정
   backup-n8n-workflows.ps1 -ApiKey "발급받은_API_KEY"


==============================================
backup-single-workflow.ps1 사용 방법 (단일 백업)
==============================================

핵심 기능
---------
- 워크플로우 1개만 선택해서 JSON으로 저장
- ID 또는 이름으로 지정 가능
- 저장 위치: source/{워크플로우명}_{ID}.json (기본값)
- API 키 읽기 방식은 기존 스크립트와 동일

사용법
------
1. ID로 백업 (가장 빠름)
   backup-single-workflow.ps1 -WorkflowId "KqzAJQoKuoVnjImT"

2. 이름으로 백업
   backup-single-workflow.ps1 -WorkflowName "토론토 식당 재무 자동 마감"

3. 저장 위치 직접 지정
   backup-single-workflow.ps1 -WorkflowId "KqzAJQoKuoVnjImT" -OutputFile "backup/my_workflow.json"

4. 미리보기 (파일 저장 안 함)
   backup-single-workflow.ps1 -WorkflowId "KqzAJQoKuoVnjImT" -DryRun

5. API 키 직접 지정
   backup-single-workflow.ps1 -WorkflowId "KqzAJQoKuoVnjImT" -ApiKey "발급받은_API_KEY"

# SQL 실행 순서

전용으로 비어 있는 데모 스키마에서 실행합니다. 환경에 맞게 placeholder 스키마명 `MARITIME_DEMO`를 모든 파일에 동일하게 적용하세요.

1. `00-setup/00_preflight.sql`
2. `01-data/10_ddl.sql`
3. `01-data/11_seed_golden_scenario.sql`
4. `01-data/12_comments.sql`
5. `01-data/13_validate_golden_scenario.sql`
6. `02-decision/20_create_decision_views.sql`
7. `02-decision/21_validate_decisions.sql`
8. `02-semantics/20_create_semantic_network.sql`부터 `25_validate_semantic_inference.sql`까지
9. `03-property-graph/30_create_graph_projections.sql`부터 `32_validate_graph.sql`까지
10. `04-action/40_create_action_preview.sql`과 `41_validate_action_preview.sql`

스크립트는 `fail-closed` 방식으로 작성되었습니다. 선행 조건이나 기대 검증 결과가 통과하지 않으면 실행을 중단하세요. 모든 스크립트는 합성 데모 객체만 생성하며 외부 시스템 호출이나 운영 조치를 수행하지 않습니다.

-- Maritime Actionable Ontology Demo Kit
-- Fail-fast safety and count validation for action preview.

SET SERVEROUTPUT ON

DECLARE
  l_total          NUMBER;
  l_alternate      NUMBER;
  l_expedite       NUMBER;
  l_keep_leak      NUMBER;
  l_control_leak   NUMBER;
  l_duplicate_id   NUMBER;
  l_duplicate_target NUMBER;
  l_non_preview    NUMBER;
  l_external       NUMBER;
  l_workflow_assumption_error NUMBER;
  l_provenance_error NUMBER;

  PROCEDURE assert_equal(
    p_label     VARCHAR2,
    p_actual    NUMBER,
    p_expected  NUMBER
  ) IS
  BEGIN
    IF p_actual IS NULL OR p_actual <> p_expected THEN
      RAISE_APPLICATION_ERROR(
        -20400,
        p_label || ': expected ' || p_expected || ', got ' || NVL(TO_CHAR(p_actual), 'NULL')
      );
    END IF;
    DBMS_OUTPUT.PUT_LINE('PASS ' || p_label || ' = ' || p_actual);
  END;
BEGIN
  IF UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')) <> 'MARITIME_DEMO'
     OR UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')) <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Connect directly as MARITIME_DEMO.');
  END IF;

  SELECT
    COUNT(*),
    SUM(CASE WHEN ACTION_TYPE = 'REVIEW_ALTERNATE_VOYAGE' THEN 1 ELSE 0 END),
    SUM(CASE WHEN ACTION_TYPE = 'EXPEDITE_YARD_TRANSFER' THEN 1 ELSE 0 END),
    SUM(CASE WHEN DECISION_CODE = 'KEEP' THEN 1 ELSE 0 END),
    SUM(CASE WHEN CONTAINER_ID = 'CNT-MAR-CTRL' THEN 1 ELSE 0 END),
    SUM(CASE WHEN APPROVAL_STATE <> 'PREVIEW_ONLY' THEN 1 ELSE 0 END),
    SUM(CASE WHEN EXTERNAL_EXECUTION_YN <> 'N' THEN 1 ELSE 0 END),
    SUM(CASE WHEN WORKFLOW_ASSUMPTION_YN <> 'Y' THEN 1 ELSE 0 END),
    SUM(
      CASE
        WHEN FIXTURE_VERSION <> 'MARITIME-AO-FIXTURE-0.1.0'
          OR CONTRACT_VERSION <> 'MARITIME-AO-CONTRACT-0.1.0'
          OR ONTOLOGY_VERSION <> 'MARITIME-AO-ONTOLOGY-0.2.0'
          OR POLICY_VERSION <> 'MARITIME-AO-CONNECTION-0.1.0'
          OR CONTEXT_SCENARIO_ID <> 'INC-MAR-0001'
          OR DATA_AS_OF_TS <> TO_TIMESTAMP_TZ(
            '2026-08-12 09:00:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR'
          )
          OR SELECTED_ETA_EVENT_ID <> 'ETA-MAR-0002'
          OR SELECTED_REVISION_NO <> 2
          OR SELECTED_SOURCE_EVENT_AT <> TO_TIMESTAMP_TZ(
            '2026-08-12 08:55:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR'
          )
          OR RUN_MODE <> 'SYNTHETIC_DEMO'
          OR RESULT_PROVENANCE <> 'SYNTHETIC_FIXTURE'
        THEN 1 ELSE 0
      END
    )
  INTO
    l_total,
    l_alternate,
    l_expedite,
    l_keep_leak,
    l_control_leak,
    l_non_preview,
    l_external,
    l_workflow_assumption_error,
    l_provenance_error
  FROM MARITIME_DEMO.MARITIME_SS_ACTION_PREVIEW_V
  WHERE INCIDENT_ID = 'INC-MAR-0001';

  assert_equal('action preview rows', l_total, 15);
  assert_equal('alternate-voyage review rows', l_alternate, 9);
  assert_equal('yard-expedite review rows', l_expedite, 6);
  assert_equal('KEEP rows in action preview', l_keep_leak, 0);
  assert_equal('negative-control rows in action preview', l_control_leak, 0);
  assert_equal('non-preview action rows', l_non_preview, 0);
  assert_equal('external execution rows', l_external, 0);
  assert_equal('non-assumption workflow rows', l_workflow_assumption_error, 0);
  assert_equal('action provenance errors', l_provenance_error, 0);

  SELECT COUNT(*)
    INTO l_duplicate_id
    FROM (
      SELECT ACTION_PREVIEW_ID
      FROM MARITIME_DEMO.MARITIME_SS_ACTION_PREVIEW_V
      GROUP BY ACTION_PREVIEW_ID
      HAVING COUNT(*) <> 1
    );
  assert_equal('duplicate action preview IDs', l_duplicate_id, 0);

  SELECT COUNT(*)
    INTO l_duplicate_target
    FROM (
      SELECT INCIDENT_ID, CONTAINER_ID
      FROM MARITIME_DEMO.MARITIME_SS_ACTION_PREVIEW_V
      GROUP BY INCIDENT_ID, CONTAINER_ID
      HAVING COUNT(*) <> 1
    );
  assert_equal('duplicate action targets', l_duplicate_target, 0);

  DBMS_OUTPUT.PUT_LINE('PASS action preview is read-only and presentation safe');
END;
/

SELECT
  INCIDENT_ID,
  ACTION_PREVIEW_COUNT,
  ALTERNATE_VOYAGE_REVIEW_COUNT,
  YARD_EXPEDITE_REVIEW_COUNT,
  REVIEW_ROLE_COUNT,
  POLICY_VERSION,
  FIXTURE_VERSION,
  CONTRACT_VERSION,
  ONTOLOGY_VERSION,
  DATA_AS_OF_TS,
  RUN_MODE,
  RESULT_PROVENANCE,
  APPROVAL_STATE,
  EXTERNAL_EXECUTION_YN,
  WORKFLOW_ASSUMPTION_YN
FROM MARITIME_DEMO.MARITIME_SS_ACTION_SUMMARY_V
WHERE INCIDENT_ID = 'INC-MAR-0001';

-- Maritime Actionable Ontology Demo Kit
-- Fail-fast validation for as-of replay, time arithmetic, and 9/6/21 policy results.

SET SERVEROUTPUT ON

DECLARE
  l_user                   VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
  l_schema                 VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
  l_context_rows           NUMBER;
  l_health_rows            NUMBER;
  l_selected_revision      NUMBER;
  l_revision_delta         NUMBER;
  l_schedule_variance      NUMBER;
  l_ingest_lag             NUMBER;
  l_out_of_order           NUMBER;
  l_future_excluded        NUMBER;
  l_assessed               NUMBER;
  l_container_count        NUMBER;
  l_booking_count          NUMBER;
  l_miss                   NUMBER;
  l_tight                  NUMBER;
  l_keep                   NUMBER;
  l_preview_candidates     NUMBER;
  l_control_leak           NUMBER;
  l_duplicate_grain        NUMBER;
  l_boundary_errors        NUMBER;
  l_boundary_unit_errors   NUMBER;
  l_rep_count              NUMBER;
  l_exec_enabled           NUMBER;
  l_incident_delay_errors  NUMBER;

  PROCEDURE assert_equal(
    p_label     VARCHAR2,
    p_actual    NUMBER,
    p_expected  NUMBER
  ) IS
  BEGIN
    IF p_actual IS NULL OR p_actual <> p_expected THEN
      RAISE_APPLICATION_ERROR(
        -20200,
        p_label || ': expected ' || p_expected || ', got ' || NVL(TO_CHAR(p_actual), 'NULL')
      );
    END IF;
    DBMS_OUTPUT.PUT_LINE('PASS ' || p_label || ' = ' || p_actual);
  END;
BEGIN
  IF l_user <> 'MARITIME_DEMO' OR l_schema <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Safety stop: connect directly as MARITIME_DEMO.');
  END IF;

  SELECT COUNT(*)
    INTO l_context_rows
    FROM MARITIME_SS_CONTEXT_V
   WHERE FIXTURE_VERSION = 'MARITIME-AO-FIXTURE-0.1.0'
     AND CONTRACT_VERSION = 'MARITIME-AO-CONTRACT-0.1.0'
     AND ONTOLOGY_VERSION = 'MARITIME-AO-ONTOLOGY-0.2.0'
     AND POLICY_VERSION = 'MARITIME-AO-CONNECTION-0.1.0'
     AND SCENARIO_ID = 'INC-MAR-0001'
     AND DATA_AS_OF_TS = TO_TIMESTAMP_TZ(
       '2026-08-12 09:00:00 UTC',
       'YYYY-MM-DD HH24:MI:SS TZR'
     )
     AND RUN_MODE = 'SYNTHETIC_DEMO'
     AND RESULT_PROVENANCE = 'SYNTHETIC_FIXTURE'
     AND APPROVAL_STATE = 'PREVIEW_ONLY'
     AND EXTERNAL_EXECUTION_YN = 'N';
  assert_equal('manifest-bound runtime context rows', l_context_rows, 1);

  SELECT
    COUNT(*),
    MAX(SELECTED_REVISION_NO),
    MAX(ETA_REVISION_DELTA_MINUTES),
    MAX(SCHEDULE_VARIANCE_MINUTES),
    MAX(INGEST_LAG_MINUTES),
    MAX(OUT_OF_ORDER_EVENT_COUNT),
    MAX(FUTURE_EVENT_EXCLUDED_COUNT)
  INTO
    l_health_rows,
    l_selected_revision,
    l_revision_delta,
    l_schedule_variance,
    l_ingest_lag,
    l_out_of_order,
    l_future_excluded
  FROM MARITIME_SS_INGEST_HEALTH_V
  WHERE PORT_CALL_ID = 'PC-ALPHA-260812';

  assert_equal('golden ingest-health rows', l_health_rows, 1);
  assert_equal('selected as-of revision', l_selected_revision, 2);
  assert_equal('ETA revision delta minutes', l_revision_delta, 420);
  assert_equal('schedule variance minutes', l_schedule_variance, 420);
  assert_equal('selected event ingest lag', l_ingest_lag, 2);
  assert_equal('out-of-order event count', l_out_of_order, 1);
  assert_equal('post-as-of events excluded', l_future_excluded, 1);

  SELECT
    COUNT(*),
    COUNT(DISTINCT CONTAINER_ID),
    COUNT(DISTINCT BOOKING_ID),
    SUM(CASE WHEN DECISION_CODE = 'MISS' THEN 1 ELSE 0 END),
    SUM(CASE WHEN DECISION_CODE = 'TIGHT' THEN 1 ELSE 0 END),
    SUM(CASE WHEN DECISION_CODE = 'KEEP' THEN 1 ELSE 0 END),
    SUM(CASE WHEN DECISION_CODE IN ('MISS', 'TIGHT') THEN 1 ELSE 0 END),
    SUM(CASE WHEN EXTERNAL_EXECUTION_YN <> 'N' THEN 1 ELSE 0 END)
  INTO
    l_assessed,
    l_container_count,
    l_booking_count,
    l_miss,
    l_tight,
    l_keep,
    l_preview_candidates,
    l_exec_enabled
  FROM MARITIME_SS_CONNECTION_DECISION_V
  WHERE INCIDENT_ID = 'INC-MAR-0001';

  assert_equal('assessed connections', l_assessed, 36);
  assert_equal('assessed containers', l_container_count, 36);
  assert_equal('assessed bookings', l_booking_count, 18);
  assert_equal('MISS decisions', l_miss, 9);
  assert_equal('TIGHT decisions', l_tight, 6);
  assert_equal('KEEP decisions', l_keep, 21);
  assert_equal('preview candidate decisions', l_preview_candidates, 15);
  assert_equal('externally executable decisions', l_exec_enabled, 0);

  SELECT COUNT(*)
    INTO l_control_leak
    FROM MARITIME_SS_CONNECTION_DECISION_V
   WHERE CONNECTION_ID = 'CONN-MAR-CTRL'
      OR CONTAINER_ID = 'CNT-MAR-CTRL'
      OR PORT_CALL_ID = 'PC-CTRL-260812';
  assert_equal('negative-control leaks', l_control_leak, 0);

  SELECT COUNT(*)
    INTO l_duplicate_grain
    FROM (
      SELECT CONNECTION_ID
      FROM MARITIME_SS_CONNECTION_DECISION_V
      GROUP BY CONNECTION_ID
      HAVING COUNT(*) <> 1
    );
  assert_equal('duplicate decision grains', l_duplicate_grain, 0);

  SELECT COUNT(*)
    INTO l_boundary_errors
    FROM MARITIME_SS_CONNECTION_DECISION_V
   WHERE (DECISION_CODE = 'MISS' AND ESTIMATED_READY_AT <= LOAD_CUTOFF_AT)
      OR (DECISION_CODE = 'TIGHT'
          AND (ESTIMATED_READY_AT > LOAD_CUTOFF_AT
               OR ESTIMATED_READY_AT
                    <= LOAD_CUTOFF_AT
                       - NUMTODSINTERVAL(TIGHT_THRESHOLD_MIN, 'MINUTE')))
      OR (DECISION_CODE = 'KEEP'
          AND ESTIMATED_READY_AT
                > LOAD_CUTOFF_AT
                   - NUMTODSINTERVAL(TIGHT_THRESHOLD_MIN, 'MINUTE'));
  assert_equal('timestamp policy boundary errors', l_boundary_errors, 0);

  SELECT COUNT(*)
    INTO l_boundary_unit_errors
    FROM (
      SELECT
        EXPECTED_CODE,
        CASE
          WHEN READY_AT > CUTOFF_AT THEN 'MISS'
          WHEN READY_AT > CUTOFF_AT - NUMTODSINTERVAL(90, 'MINUTE') THEN 'TIGHT'
          ELSE 'KEEP'
        END AS ACTUAL_CODE
      FROM (
        SELECT 'MISS' EXPECTED_CODE,
               TO_TIMESTAMP_TZ('2026-08-12 12:00:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR') CUTOFF_AT,
               TO_TIMESTAMP_TZ('2026-08-12 12:00:01 UTC', 'YYYY-MM-DD HH24:MI:SS TZR') READY_AT
          FROM DUAL
        UNION ALL
        SELECT 'TIGHT',
               TO_TIMESTAMP_TZ('2026-08-12 12:00:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR'),
               TO_TIMESTAMP_TZ('2026-08-12 12:00:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR')
          FROM DUAL
        UNION ALL
        SELECT 'TIGHT',
               TO_TIMESTAMP_TZ('2026-08-12 12:00:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR'),
               TO_TIMESTAMP_TZ('2026-08-12 10:30:01 UTC', 'YYYY-MM-DD HH24:MI:SS TZR')
          FROM DUAL
        UNION ALL
        SELECT 'KEEP',
               TO_TIMESTAMP_TZ('2026-08-12 12:00:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR'),
               TO_TIMESTAMP_TZ('2026-08-12 10:30:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR')
          FROM DUAL
      )
    )
   WHERE ACTUAL_CODE <> EXPECTED_CODE;
  assert_equal('exact timestamp boundary unit errors', l_boundary_unit_errors, 0);

  SELECT COUNT(*)
    INTO l_incident_delay_errors
    FROM MARITIME_SS_INCIDENTS i
    JOIN MARITIME_SS_INGEST_HEALTH_V h
      ON h.PORT_CALL_ID = i.PORT_CALL_ID
   WHERE i.INCIDENT_ID = 'INC-MAR-0001'
     AND (
       i.RECORDED_DELAY_MIN <> h.ETA_REVISION_DELTA_MINUTES
       OR i.RECORDED_DELAY_MIN <> h.SCHEDULE_VARIANCE_MINUTES
     );
  assert_equal('incident versus computed delay mismatches', l_incident_delay_errors, 0);

  SELECT COUNT(*)
    INTO l_rep_count
    FROM MARITIME_SS_CONNECTION_DECISION_V
   WHERE CONNECTION_ID = 'CONN-MAR-001'
     AND ESTIMATED_READY_AT = TO_TIMESTAMP_TZ(
       '2026-08-12 16:20:00 UTC',
       'YYYY-MM-DD HH24:MI:SS TZR'
     )
     AND LOAD_CUTOFF_AT = TO_TIMESTAMP_TZ(
       '2026-08-12 14:00:00 UTC',
       'YYYY-MM-DD HH24:MI:SS TZR'
     )
     AND CONNECTION_SLACK_MINUTES = -140
     AND CONNECTION_SLACK_SECONDS = -8400
     AND DECISION_CODE = 'MISS'
     AND POLICY_VERSION = 'MARITIME-AO-CONNECTION-0.1.0'
     AND DATA_AS_OF_TS = TO_TIMESTAMP_TZ(
       '2026-08-12 09:00:00 UTC',
       'YYYY-MM-DD HH24:MI:SS TZR'
     )
     AND RUN_MODE = 'SYNTHETIC_DEMO'
     AND APPROVAL_STATE = 'PREVIEW_ONLY';
  assert_equal('representative MISS calculation', l_rep_count, 1);

  DBMS_OUTPUT.PUT_LINE('PASS deterministic connection decision contract ready');
END;
/

SELECT
  INCIDENT_ID,
  ETA_REVISION_DELTA_MINUTES,
  SCHEDULE_VARIANCE_MINUTES,
  FUTURE_EVENT_EXCLUDED_COUNT,
  ASSESSED_CONNECTION_COUNT,
  BOOKING_COUNT,
  CONTAINER_COUNT,
  MISS_COUNT,
  TIGHT_COUNT,
  KEEP_COUNT,
  FIXTURE_VERSION,
  CONTRACT_VERSION,
  ONTOLOGY_VERSION,
  POLICY_VERSION,
  DATA_AS_OF_TS,
  RUN_MODE,
  RESULT_PROVENANCE,
  APPROVAL_STATE,
  EXTERNAL_EXECUTION_YN
FROM MARITIME_SS_EXECUTIVE_V
WHERE INCIDENT_ID = 'INC-MAR-0001';

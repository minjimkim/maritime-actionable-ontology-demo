-- Maritime Actionable Ontology Demo Kit
-- Fail-fast relational, as-of replay, and ship-to-shore event validation.

SET SERVEROUTPUT ON

DECLARE
  l_clock_count              NUMBER;
  l_clock_as_of              TIMESTAMP WITH TIME ZONE;
  l_manifest_count           NUMBER;
  l_manifest_expected        NUMBER;
  l_manifest_as_of           TIMESTAMP WITH TIME ZONE;
  l_active_policy_count      NUMBER;
  l_context_policy_count     NUMBER;
  l_vessel_count             NUMBER;
  l_voyage_count             NUMBER;
  l_port_count               NUMBER;
  l_call_count               NUMBER;
  l_eta_count                NUMBER;
  l_cutoff_count             NUMBER;
  l_incident_count           NUMBER;
  l_booking_count            NUMBER;
  l_container_count          NUMBER;
  l_booking_edge_count       NUMBER;
  l_connection_count         NUMBER;
  l_main_booking_count       NUMBER;
  l_main_container_count     NUMBER;
  l_main_connection_count    NUMBER;
  l_control_connection_count NUMBER;
  l_latest_revision          NUMBER;
  l_latest_eta               TIMESTAMP WITH TIME ZONE;
  l_previous_eta             TIMESTAMP WITH TIME ZONE;
  l_planned_eta              TIMESTAMP WITH TIME ZONE;
  l_schedule_variance_min    NUMBER;
  l_revision_delta_min       NUMBER;
  l_recorded_delay_min       NUMBER;
  l_future_excluded_count    NUMBER;
  l_future_event_exact       NUMBER;
  l_out_of_order_count       NUMBER;
  l_orphan_count             NUMBER;
  l_booking_teu_errors       NUMBER;
  l_voyage_role_errors       NUMBER;
  l_bad_scope_count          NUMBER;

  PROCEDURE assert_equal(
    p_label     VARCHAR2,
    p_actual    NUMBER,
    p_expected  NUMBER
  ) IS
  BEGIN
    IF p_actual IS NULL OR p_actual <> p_expected THEN
      RAISE_APPLICATION_ERROR(
        -20100,
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

  SELECT COUNT(*)
    INTO l_clock_count
    FROM MARITIME_DEMO.MARITIME_SS_DEMO_CLOCK
   WHERE CLOCK_ID = 1
     AND TIMEZONE_REGION = 'UTC'
     AND DATA_SCOPE = 'SYNTHETIC_SHIP_SHORE_DEMO';
  assert_equal('demo clock rows', l_clock_count, 1);

  SELECT AS_OF_TS
    INTO l_clock_as_of
    FROM MARITIME_DEMO.MARITIME_SS_DEMO_CLOCK
   WHERE CLOCK_ID = 1;

  SELECT COUNT(*)
    INTO l_manifest_count
    FROM MARITIME_DEMO.MARITIME_SS_FIXTURE_MANIFEST;
  assert_equal('fixture manifest singleton rows', l_manifest_count, 1);

  SELECT COUNT(*)
    INTO l_manifest_expected
    FROM MARITIME_DEMO.MARITIME_SS_FIXTURE_MANIFEST
   WHERE FIXTURE_VERSION = 'MARITIME-AO-FIXTURE-0.1.0'
     AND CONTRACT_VERSION = 'MARITIME-AO-CONTRACT-0.1.0'
     AND ONTOLOGY_VERSION = 'MARITIME-AO-ONTOLOGY-0.2.0'
     AND POLICY_VERSION = 'MARITIME-AO-CONNECTION-0.1.0'
     AND SCENARIO_ID = 'INC-MAR-0001'
     AND DATA_SCOPE = 'SYNTHETIC_SHIP_SHORE_DEMO';
  assert_equal('expected fixture manifest rows', l_manifest_expected, 1);

  SELECT DATA_AS_OF_TS
    INTO l_manifest_as_of
    FROM MARITIME_DEMO.MARITIME_SS_FIXTURE_MANIFEST
   WHERE FIXTURE_VERSION = 'MARITIME-AO-FIXTURE-0.1.0';

  IF l_clock_as_of <> l_manifest_as_of THEN
    RAISE_APPLICATION_ERROR(-20101, 'Demo clock and fixture manifest data-as-of differ.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PASS clock equals manifest data-as-of');

  SELECT COUNT(*)
    INTO l_active_policy_count
    FROM MARITIME_DEMO.MARITIME_SS_POLICY_VERSIONS
   WHERE ACTIVE_YN = 'Y';
  assert_equal('active policy singleton rows', l_active_policy_count, 1);

  SELECT COUNT(*)
    INTO l_context_policy_count
    FROM MARITIME_DEMO.MARITIME_SS_FIXTURE_MANIFEST m
    JOIN MARITIME_DEMO.MARITIME_SS_POLICY_VERSIONS p
      ON p.POLICY_VERSION = m.POLICY_VERSION
    JOIN MARITIME_DEMO.MARITIME_SS_DEMO_CLOCK c
      ON c.CLOCK_ID = 1
     AND c.AS_OF_TS = m.DATA_AS_OF_TS
   WHERE m.FIXTURE_VERSION = 'MARITIME-AO-FIXTURE-0.1.0'
     AND p.POLICY_VERSION = 'MARITIME-AO-CONNECTION-0.1.0'
     AND p.ACTIVE_YN = 'Y'
     AND p.EFFECTIVE_FROM_TS <= c.AS_OF_TS
     AND p.TIGHT_THRESHOLD_MIN = 90
     AND p.MAX_INGEST_LAG_MIN = 5
     AND p.APPROVAL_STATE = 'PREVIEW_ONLY'
     AND p.EXTERNAL_EXECUTION_YN = 'N';
  assert_equal('manifest-bound effective policy rows', l_context_policy_count, 1);

  SELECT COUNT(*) INTO l_vessel_count FROM MARITIME_DEMO.MARITIME_SS_VESSELS;
  SELECT COUNT(*) INTO l_voyage_count FROM MARITIME_DEMO.MARITIME_SS_VOYAGES;
  SELECT COUNT(*) INTO l_port_count FROM MARITIME_DEMO.MARITIME_SS_PORTS;
  SELECT COUNT(*) INTO l_call_count FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS;
  SELECT COUNT(*) INTO l_eta_count FROM MARITIME_DEMO.MARITIME_SS_ETA_EVENTS;
  SELECT COUNT(*) INTO l_cutoff_count FROM MARITIME_DEMO.MARITIME_SS_TERMINAL_CUTOFFS;
  SELECT COUNT(*) INTO l_incident_count FROM MARITIME_DEMO.MARITIME_SS_INCIDENTS;
  SELECT COUNT(*) INTO l_booking_count FROM MARITIME_DEMO.MARITIME_SS_BOOKINGS;
  SELECT COUNT(*) INTO l_container_count FROM MARITIME_DEMO.MARITIME_SS_CONTAINERS;
  SELECT COUNT(*) INTO l_booking_edge_count FROM MARITIME_DEMO.MARITIME_SS_BOOKING_CONTAINERS;
  SELECT COUNT(*) INTO l_connection_count FROM MARITIME_DEMO.MARITIME_SS_CONNECTIONS;

  assert_equal('vessels including control', l_vessel_count, 5);
  assert_equal('voyages including control', l_voyage_count, 6);
  assert_equal('ports', l_port_count, 1);
  assert_equal('port calls including control', l_call_count, 2);
  assert_equal('ETA events including late, future, and control', l_eta_count, 5);
  assert_equal('terminal cutoffs including control', l_cutoff_count, 4);
  assert_equal('incidents', l_incident_count, 1);
  assert_equal('bookings including control', l_booking_count, 19);
  assert_equal('containers including control', l_container_count, 37);
  assert_equal('booking-container edges including control', l_booking_edge_count, 37);
  assert_equal('connections including control', l_connection_count, 37);

  SELECT COUNT(*) INTO l_main_booking_count
    FROM MARITIME_DEMO.MARITIME_SS_BOOKINGS
   WHERE BOOKING_STATUS = 'CONFIRMED';
  SELECT COUNT(*) INTO l_main_container_count
    FROM MARITIME_DEMO.MARITIME_SS_CONTAINERS
   WHERE CONTAINER_ID <> 'CNT-MAR-CTRL';
  SELECT COUNT(*) INTO l_main_connection_count
    FROM MARITIME_DEMO.MARITIME_SS_CONNECTIONS
   WHERE PORT_CALL_ID = 'PC-ALPHA-260812'
     AND INBOUND_VOYAGE_ID = 'VYG-DEMO-2608E';
  SELECT COUNT(*) INTO l_control_connection_count
    FROM MARITIME_DEMO.MARITIME_SS_CONNECTIONS
   WHERE CONNECTION_ID = 'CONN-MAR-CTRL'
     AND PORT_CALL_ID = 'PC-CTRL-260812';

  assert_equal('golden bookings', l_main_booking_count, 18);
  assert_equal('golden containers', l_main_container_count, 36);
  assert_equal('golden assessed connections', l_main_connection_count, 36);
  assert_equal('negative-control connections', l_control_connection_count, 1);

  SELECT REVISION_NO, REPORTED_ETA_AT
    INTO l_latest_revision, l_latest_eta
    FROM (
      SELECT e.REVISION_NO, e.REPORTED_ETA_AT
        FROM MARITIME_DEMO.MARITIME_SS_ETA_EVENTS e
       WHERE e.PORT_CALL_ID = 'PC-ALPHA-260812'
         AND e.RECEIVED_AT <= l_clock_as_of
       ORDER BY e.REVISION_NO DESC, e.SOURCE_EVENT_AT DESC, e.ETA_EVENT_ID
    )
   WHERE ROWNUM = 1;

  SELECT REPORTED_ETA_AT
    INTO l_previous_eta
    FROM (
      SELECT e.REPORTED_ETA_AT
        FROM MARITIME_DEMO.MARITIME_SS_ETA_EVENTS e
       WHERE e.PORT_CALL_ID = 'PC-ALPHA-260812'
         AND e.REVISION_NO < l_latest_revision
         AND e.RECEIVED_AT <= l_clock_as_of
       ORDER BY e.REVISION_NO DESC, e.SOURCE_EVENT_AT DESC, e.ETA_EVENT_ID
    )
   WHERE ROWNUM = 1;

  SELECT PLANNED_ARRIVAL_AT
    INTO l_planned_eta
    FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS
   WHERE PORT_CALL_ID = 'PC-ALPHA-260812';

  l_schedule_variance_min := ROUND(
    (
      CAST(SYS_EXTRACT_UTC(l_latest_eta) AS DATE)
      - CAST(SYS_EXTRACT_UTC(l_planned_eta) AS DATE)
    ) * 1440
  );
  l_revision_delta_min := ROUND(
    (
      CAST(SYS_EXTRACT_UTC(l_latest_eta) AS DATE)
      - CAST(SYS_EXTRACT_UTC(l_previous_eta) AS DATE)
    ) * 1440
  );

  SELECT RECORDED_DELAY_MIN
    INTO l_recorded_delay_min
    FROM MARITIME_DEMO.MARITIME_SS_INCIDENTS
   WHERE INCIDENT_ID = 'INC-MAR-0001';

  assert_equal('as-of selected ETA revision', l_latest_revision, 2);
  assert_equal('schedule variance minutes', l_schedule_variance_min, 420);
  assert_equal('ETA revision delta minutes', l_revision_delta_min, 420);
  assert_equal('recorded delay equals ETA revision delta', l_recorded_delay_min, l_revision_delta_min);

  IF l_latest_eta <> TO_TIMESTAMP_TZ(
    '2026-08-12 14:00:00 UTC',
    'YYYY-MM-DD HH24:MI:SS TZR'
  ) THEN
    RAISE_APPLICATION_ERROR(-20102, 'As-of latest ETA must be 2026-08-12 14:00 UTC.');
  END IF;
  DBMS_OUTPUT.PUT_LINE('PASS as-of latest ETA = 2026-08-12 14:00 UTC');

  SELECT COUNT(*)
    INTO l_future_excluded_count
    FROM MARITIME_DEMO.MARITIME_SS_ETA_EVENTS
   WHERE PORT_CALL_ID = 'PC-ALPHA-260812'
     AND RECEIVED_AT > l_clock_as_of;
  assert_equal('post-as-of ETA events excluded', l_future_excluded_count, 1);

  SELECT COUNT(*)
    INTO l_future_event_exact
    FROM MARITIME_DEMO.MARITIME_SS_ETA_EVENTS
   WHERE ETA_EVENT_ID = 'ETA-MAR-0003-FUTURE'
     AND PORT_CALL_ID = 'PC-ALPHA-260812'
     AND REVISION_NO = 3
     AND SOURCE_EVENT_AT = TO_TIMESTAMP_TZ(
       '2026-08-12 09:05:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR'
     )
     AND RECEIVED_AT = TO_TIMESTAMP_TZ(
       '2026-08-12 09:07:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR'
     )
     AND REPORTED_ETA_AT = TO_TIMESTAMP_TZ(
       '2026-08-12 15:00:00 UTC', 'YYYY-MM-DD HH24:MI:SS TZR'
     );
  assert_equal('exact post-as-of revision 3 event', l_future_event_exact, 1);

  SELECT COUNT(*)
    INTO l_out_of_order_count
    FROM MARITIME_DEMO.MARITIME_SS_ETA_EVENTS e
   WHERE e.PORT_CALL_ID = 'PC-ALPHA-260812'
     AND e.RECEIVED_AT <= l_clock_as_of
     AND EXISTS (
       SELECT 1
         FROM MARITIME_DEMO.MARITIME_SS_ETA_EVENTS newer
        WHERE newer.PORT_CALL_ID = e.PORT_CALL_ID
          AND newer.REVISION_NO > e.REVISION_NO
          AND newer.RECEIVED_AT <= l_clock_as_of
          AND newer.RECEIVED_AT < e.RECEIVED_AT
     );
  assert_equal('as-of out-of-order ETA events', l_out_of_order_count, 1);

  SELECT COUNT(*)
    INTO l_orphan_count
    FROM MARITIME_DEMO.MARITIME_SS_CONNECTIONS c
    LEFT JOIN MARITIME_DEMO.MARITIME_SS_CONTAINERS ctr
      ON ctr.CONTAINER_ID = c.CONTAINER_ID
    LEFT JOIN MARITIME_DEMO.MARITIME_SS_BOOKING_CONTAINERS bc
      ON bc.CONTAINER_ID = c.CONTAINER_ID
    LEFT JOIN MARITIME_DEMO.MARITIME_SS_PORT_CALLS pc
      ON pc.PORT_CALL_ID = c.PORT_CALL_ID
     AND pc.VOYAGE_ID = c.INBOUND_VOYAGE_ID
    LEFT JOIN MARITIME_DEMO.MARITIME_SS_TERMINAL_CUTOFFS tc
      ON tc.PORT_CALL_ID = c.PORT_CALL_ID
     AND tc.OUTBOUND_VOYAGE_ID = c.OUTBOUND_VOYAGE_ID
   WHERE ctr.CONTAINER_ID IS NULL
      OR bc.CONTAINER_ID IS NULL
      OR pc.PORT_CALL_ID IS NULL
      OR tc.OUTBOUND_VOYAGE_ID IS NULL;
  assert_equal('connection orphans', l_orphan_count, 0);

  SELECT COUNT(*)
    INTO l_booking_teu_errors
    FROM (
      SELECT b.BOOKING_ID
        FROM MARITIME_DEMO.MARITIME_SS_BOOKINGS b
        LEFT JOIN MARITIME_DEMO.MARITIME_SS_BOOKING_CONTAINERS bc
          ON bc.BOOKING_ID = b.BOOKING_ID
       GROUP BY b.BOOKING_ID, b.TOTAL_TEU
      HAVING NVL(SUM(bc.ALLOCATION_TEU), 0) <> b.TOTAL_TEU
    );
  assert_equal('booking TEU allocation mismatches', l_booking_teu_errors, 0);

  SELECT COUNT(*)
    INTO l_voyage_role_errors
    FROM MARITIME_DEMO.MARITIME_SS_CONNECTIONS c
    JOIN MARITIME_DEMO.MARITIME_SS_VOYAGES vin
      ON vin.VOYAGE_ID = c.INBOUND_VOYAGE_ID
    JOIN MARITIME_DEMO.MARITIME_SS_VOYAGES vout
      ON vout.VOYAGE_ID = c.OUTBOUND_VOYAGE_ID
   WHERE (c.CONNECTION_STATE = 'PLANNED'
          AND (vin.VOYAGE_ROLE <> 'INBOUND' OR vout.VOYAGE_ROLE <> 'OUTBOUND'))
      OR (c.CONNECTION_STATE = 'CONTROL'
          AND (vin.VOYAGE_ROLE <> 'CONTROL' OR vout.VOYAGE_ROLE <> 'CONTROL'));
  assert_equal('connection voyage-role mismatches', l_voyage_role_errors, 0);

  SELECT
    (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_DEMO_CLOCK WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_POLICY_VERSIONS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_FIXTURE_MANIFEST WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_VESSELS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_VOYAGES WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_PORTS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_ETA_EVENTS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_TERMINAL_CUTOFFS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_INCIDENTS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_BOOKINGS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_CONTAINERS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_BOOKING_CONTAINERS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_CONNECTIONS WHERE DATA_SCOPE <> 'SYNTHETIC_SHIP_SHORE_DEMO')
    INTO l_bad_scope_count
    FROM DUAL;
  assert_equal('non-synthetic scope rows', l_bad_scope_count, 0);

  DBMS_OUTPUT.PUT_LINE('PASS relational as-of ledger replay ready');
END;
/

SELECT
  'INC-MAR-0001' AS INCIDENT_ID,
  2 AS EXPECTED_AS_OF_REVISION,
  420 AS EXPECTED_ETA_REVISION_DELTA_MIN,
  420 AS EXPECTED_SCHEDULE_VARIANCE_MIN,
  5 AS EXPECTED_TOTAL_ETA_EVENTS,
  1 AS EXPECTED_FUTURE_EXCLUDED,
  18 AS EXPECTED_BOOKINGS,
  36 AS EXPECTED_CONTAINERS,
  36 AS EXPECTED_CONNECTIONS,
  1 AS EXPECTED_NEGATIVE_CONTROL
FROM DUAL;

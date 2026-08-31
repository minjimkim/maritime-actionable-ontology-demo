-- Maritime Actionable Ontology Demo Kit
-- Fail-fast TRUSTED materialized projection integrity and GRAPH_TABLE validation.

SET SERVEROUTPUT ON

DECLARE
  l_graph_count          NUMBER;
  l_valid_mview_count    NUMBER;
  l_fresh_mview_count    NUMBER;
  l_vertex_count         NUMBER;
  l_edge_count           NUMBER;
  l_path_count           NUMBER;
  l_path_containers      NUMBER;
  l_path_bookings        NUMBER;
  l_miss                 NUMBER;
  l_tight                NUMBER;
  l_keep                 NUMBER;
  l_control_leak         NUMBER;
  l_projection_error     NUMBER;
  l_edge_key_error       NUMBER;
  l_endpoint_error       NUMBER;

  PROCEDURE assert_equal(
    p_label     VARCHAR2,
    p_actual    NUMBER,
    p_expected  NUMBER
  ) IS
  BEGIN
    IF p_actual IS NULL OR p_actual <> p_expected THEN
      RAISE_APPLICATION_ERROR(
        -20300,
        p_label || ': expected ' || p_expected || ', got ' || NVL(TO_CHAR(p_actual), 'NULL')
      );
    END IF;
    DBMS_OUTPUT.PUT_LINE('PASS ' || p_label || ' = ' || p_actual);
  END;

  PROCEDURE assert_parity(
    p_label       VARCHAR2,
    p_view_name   VARCHAR2,
    p_mview_name  VARCHAR2,
    p_column_list VARCHAR2
  ) IS
    l_source_minus_mview NUMBER;
    l_mview_minus_source NUMBER;
    l_source_count       NUMBER;
    l_mview_count        NUMBER;
    l_sql                VARCHAR2(32767);
  BEGIN
    -- Each direction is a separate parenthesized MINUS query so Oracle set-operator
    -- evaluation cannot hide drift in the opposite direction.
    l_sql :=
      'SELECT COUNT(*) FROM (' ||
      'SELECT ' || p_column_list || ' FROM MARITIME_DEMO.' || p_view_name ||
      ' MINUS SELECT ' || p_column_list || ' FROM MARITIME_DEMO.' || p_mview_name ||
      ')';
    EXECUTE IMMEDIATE l_sql INTO l_source_minus_mview;
    assert_equal(p_label || ' source-minus-MV rows', l_source_minus_mview, 0);

    l_sql :=
      'SELECT COUNT(*) FROM (' ||
      'SELECT ' || p_column_list || ' FROM MARITIME_DEMO.' || p_mview_name ||
      ' MINUS SELECT ' || p_column_list || ' FROM MARITIME_DEMO.' || p_view_name ||
      ')';
    EXECUTE IMMEDIATE l_sql INTO l_mview_minus_source;
    assert_equal(p_label || ' MV-minus-source rows', l_mview_minus_source, 0);

    EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM MARITIME_DEMO.' || p_view_name
      INTO l_source_count;
    EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM MARITIME_DEMO.' || p_mview_name
      INTO l_mview_count;
    assert_equal(p_label || ' row-count parity', l_mview_count, l_source_count);
  END;
BEGIN
  IF UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')) <> 'MARITIME_DEMO'
     OR UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')) <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Connect directly as MARITIME_DEMO.');
  END IF;

  SELECT COUNT(*)
    INTO l_graph_count
    FROM USER_OBJECTS
   WHERE OBJECT_NAME = 'MARITIME_SS_SHIP_SHORE_G'
     AND OBJECT_TYPE = 'PROPERTY GRAPH'
     AND STATUS = 'VALID';
  assert_equal('valid property graph objects', l_graph_count, 1);

  SELECT COUNT(*)
    INTO l_valid_mview_count
    FROM USER_OBJECTS
   WHERE OBJECT_NAME IN (
     'MARITIME_SS_E_VOYAGE_VESSEL_MV', 'MARITIME_SS_E_VOYAGE_CALL_MV',
     'MARITIME_SS_E_CALL_PORT_MV', 'MARITIME_SS_E_INCIDENT_CALL_MV',
     'MARITIME_SS_E_CARRIED_ON_MV', 'MARITIME_SS_E_CONNECTS_TO_MV',
     'MARITIME_SS_E_INCIDENT_CONTAINER_MV'
   )
     AND OBJECT_TYPE = 'MATERIALIZED VIEW'
     AND STATUS = 'VALID';
  assert_equal('valid graph materialized views', l_valid_mview_count, 7);

  SELECT COUNT(*)
    INTO l_fresh_mview_count
    FROM USER_MVIEWS
   WHERE MVIEW_NAME IN (
     'MARITIME_SS_E_VOYAGE_VESSEL_MV', 'MARITIME_SS_E_VOYAGE_CALL_MV',
     'MARITIME_SS_E_CALL_PORT_MV', 'MARITIME_SS_E_INCIDENT_CALL_MV',
     'MARITIME_SS_E_CARRIED_ON_MV', 'MARITIME_SS_E_CONNECTS_TO_MV',
     'MARITIME_SS_E_INCIDENT_CONTAINER_MV'
   )
     AND STALENESS = 'FRESH'
     AND COMPILE_STATE = 'VALID';
  assert_equal('fresh and compiled graph materialized views', l_fresh_mview_count, 7);

  assert_parity(
    'voyage-vessel projection',
    'MARITIME_SS_E_VOYAGE_VESSEL_V',
    'MARITIME_SS_E_VOYAGE_VESSEL_MV',
    'EDGE_ID, VOYAGE_ID, VESSEL_ID, VOYAGE_ROLE, DATA_SCOPE'
  );
  assert_parity(
    'voyage-call projection',
    'MARITIME_SS_E_VOYAGE_CALL_V',
    'MARITIME_SS_E_VOYAGE_CALL_MV',
    'EDGE_ID, VOYAGE_ID, PORT_CALL_ID, TERMINAL_CODE, DATA_SCOPE'
  );
  assert_parity(
    'call-port projection',
    'MARITIME_SS_E_CALL_PORT_V',
    'MARITIME_SS_E_CALL_PORT_MV',
    'EDGE_ID, PORT_CALL_ID, PORT_CODE, DATA_SCOPE'
  );
  assert_parity(
    'incident-call projection',
    'MARITIME_SS_E_INCIDENT_CALL_V',
    'MARITIME_SS_E_INCIDENT_CALL_MV',
    'EDGE_ID, INCIDENT_ID, PORT_CALL_ID, RECORDED_DELAY_MIN, DATA_SCOPE'
  );
  assert_parity(
    'carried-on projection',
    'MARITIME_SS_E_CARRIED_ON_V',
    'MARITIME_SS_E_CARRIED_ON_MV',
    'EDGE_ID, CONNECTION_ID, CONTAINER_ID, INBOUND_VOYAGE_ID, ' ||
    'PORT_CALL_ID, CONNECTION_STATE, DATA_SCOPE'
  );
  assert_parity(
    'connects-to projection',
    'MARITIME_SS_E_CONNECTS_TO_V',
    'MARITIME_SS_E_CONNECTS_TO_MV',
    'EDGE_ID, CONNECTION_ID, CONTAINER_ID, OUTBOUND_VOYAGE_ID, ' ||
    'PORT_CALL_ID, PLANNED_READY_OFFSET_MIN, CONNECTION_STATE, DATA_SCOPE'
  );
  assert_parity(
    'incident-container projection',
    'MARITIME_SS_E_INCIDENT_CONTAINER_V',
    'MARITIME_SS_E_INCIDENT_CONTAINER_MV',
    'EDGE_ID, INCIDENT_ID, CONTAINER_ID, CONNECTION_ID, DECISION_CODE, ' ||
    'CONNECTION_SLACK_MINUTES, POLICY_VERSION, DATA_SCOPE'
  );

  SELECT
    (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_E_VOYAGE_VESSEL_MV WHERE EDGE_ID IS NULL OR VOYAGE_ID IS NULL OR VESSEL_ID IS NULL)
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_E_VOYAGE_CALL_MV WHERE EDGE_ID IS NULL OR VOYAGE_ID IS NULL OR PORT_CALL_ID IS NULL)
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_E_CALL_PORT_MV WHERE EDGE_ID IS NULL OR PORT_CALL_ID IS NULL OR PORT_CODE IS NULL)
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CALL_MV WHERE EDGE_ID IS NULL OR INCIDENT_ID IS NULL OR PORT_CALL_ID IS NULL)
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_BOOKING_CONTAINERS WHERE EDGE_ID IS NULL OR BOOKING_ID IS NULL OR CONTAINER_ID IS NULL)
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_E_CARRIED_ON_MV WHERE EDGE_ID IS NULL OR CONNECTION_ID IS NULL OR CONTAINER_ID IS NULL OR INBOUND_VOYAGE_ID IS NULL)
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_E_CONNECTS_TO_MV WHERE EDGE_ID IS NULL OR CONNECTION_ID IS NULL OR CONTAINER_ID IS NULL OR OUTBOUND_VOYAGE_ID IS NULL)
    + (SELECT COUNT(*) FROM MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_MV WHERE EDGE_ID IS NULL OR INCIDENT_ID IS NULL OR CONNECTION_ID IS NULL OR CONTAINER_ID IS NULL OR POLICY_VERSION IS NULL)
    INTO l_projection_error
    FROM DUAL;
  assert_equal('null graph projection keys', l_projection_error, 0);

  SELECT SUM(KEY_ERROR_COUNT)
    INTO l_edge_key_error
    FROM (
      SELECT COUNT(*) - COUNT(DISTINCT EDGE_ID) AS KEY_ERROR_COUNT FROM MARITIME_DEMO.MARITIME_SS_E_VOYAGE_VESSEL_MV
      UNION ALL
      SELECT COUNT(*) - COUNT(DISTINCT EDGE_ID) FROM MARITIME_DEMO.MARITIME_SS_E_VOYAGE_CALL_MV
      UNION ALL
      SELECT COUNT(*) - COUNT(DISTINCT EDGE_ID) FROM MARITIME_DEMO.MARITIME_SS_E_CALL_PORT_MV
      UNION ALL
      SELECT COUNT(*) - COUNT(DISTINCT EDGE_ID) FROM MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CALL_MV
      UNION ALL
      SELECT COUNT(*) - COUNT(DISTINCT EDGE_ID) FROM MARITIME_DEMO.MARITIME_SS_BOOKING_CONTAINERS
      UNION ALL
      SELECT COUNT(*) - COUNT(DISTINCT EDGE_ID) FROM MARITIME_DEMO.MARITIME_SS_E_CARRIED_ON_MV
      UNION ALL
      SELECT COUNT(*) - COUNT(DISTINCT EDGE_ID) FROM MARITIME_DEMO.MARITIME_SS_E_CONNECTS_TO_MV
      UNION ALL
      SELECT COUNT(*) - COUNT(DISTINCT EDGE_ID) FROM MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_MV
    );
  assert_equal('TRUSTED edge key duplicates', l_edge_key_error, 0);

  SELECT
    (SELECT COUNT(*)
       FROM MARITIME_DEMO.MARITIME_SS_E_VOYAGE_VESSEL_MV e
      WHERE NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_VOYAGES v WHERE v.VOYAGE_ID = e.VOYAGE_ID)
         OR NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_VESSELS v WHERE v.VESSEL_ID = e.VESSEL_ID))
    + (SELECT COUNT(*)
         FROM MARITIME_DEMO.MARITIME_SS_E_VOYAGE_CALL_MV e
        WHERE NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_VOYAGES v WHERE v.VOYAGE_ID = e.VOYAGE_ID)
           OR NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS pc WHERE pc.PORT_CALL_ID = e.PORT_CALL_ID))
    + (SELECT COUNT(*)
         FROM MARITIME_DEMO.MARITIME_SS_E_CALL_PORT_MV e
        WHERE NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS pc WHERE pc.PORT_CALL_ID = e.PORT_CALL_ID)
           OR NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_PORTS p WHERE p.PORT_CODE = e.PORT_CODE))
    + (SELECT COUNT(*)
         FROM MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CALL_MV e
        WHERE NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_INCIDENTS i WHERE i.INCIDENT_ID = e.INCIDENT_ID)
           OR NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS pc WHERE pc.PORT_CALL_ID = e.PORT_CALL_ID))
    + (SELECT COUNT(*)
         FROM MARITIME_DEMO.MARITIME_SS_BOOKING_CONTAINERS e
        WHERE NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_BOOKINGS b WHERE b.BOOKING_ID = e.BOOKING_ID)
           OR NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_CONTAINERS c WHERE c.CONTAINER_ID = e.CONTAINER_ID))
    + (SELECT COUNT(*)
         FROM MARITIME_DEMO.MARITIME_SS_E_CARRIED_ON_MV e
        WHERE NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_CONTAINERS c WHERE c.CONTAINER_ID = e.CONTAINER_ID)
           OR NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_VOYAGES v WHERE v.VOYAGE_ID = e.INBOUND_VOYAGE_ID))
    + (SELECT COUNT(*)
         FROM MARITIME_DEMO.MARITIME_SS_E_CONNECTS_TO_MV e
        WHERE NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_CONTAINERS c WHERE c.CONTAINER_ID = e.CONTAINER_ID)
           OR NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_VOYAGES v WHERE v.VOYAGE_ID = e.OUTBOUND_VOYAGE_ID))
    + (SELECT COUNT(*)
         FROM MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_MV e
        WHERE NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_INCIDENTS i WHERE i.INCIDENT_ID = e.INCIDENT_ID)
           OR NOT EXISTS (SELECT 1 FROM MARITIME_DEMO.MARITIME_SS_CONTAINERS c WHERE c.CONTAINER_ID = e.CONTAINER_ID))
    INTO l_endpoint_error
    FROM DUAL;
  assert_equal('TRUSTED edge endpoint orphans', l_endpoint_error, 0);

  SELECT COUNT(*)
    INTO l_vertex_count
    FROM GRAPH_TABLE (
      MARITIME_DEMO.MARITIME_SS_SHIP_SHORE_G
      MATCH (v)
      COLUMNS (VERTEX_ID(v) AS VERTEX_IDENTIFIER)
    );
  assert_equal('graph vertices', l_vertex_count, 71);

  SELECT COUNT(*)
    INTO l_edge_count
    FROM GRAPH_TABLE (
      MARITIME_DEMO.MARITIME_SS_SHIP_SHORE_G
      MATCH (a)-[e]->(b)
      COLUMNS (EDGE_ID(e) AS EDGE_IDENTIFIER)
    );
  assert_equal('graph edges', l_edge_count, 158);

  SELECT COUNT(*)
    INTO l_path_count
    FROM GRAPH_TABLE (
      MARITIME_DEMO.MARITIME_SS_SHIP_SHORE_G
      MATCH
        (i IS DELAY_INCIDENT)
          -[ic IS AFFECTS_PORT_CALL]->
        (pc IS PORT_CALL)
          <-[vc IS CALLS_AT]-
        (v IS VOYAGE)
          -[ov IS OPERATED_BY]->
        (ves IS VESSEL)
      WHERE i.INCIDENT_ID = 'INC-MAR-0001'
      COLUMNS (
        i.INCIDENT_ID AS INCIDENT_ID,
        pc.PORT_CALL_ID AS PORT_CALL_ID,
        v.VOYAGE_ID AS VOYAGE_ID,
        ves.VESSEL_ID AS VESSEL_ID
      )
    );
  assert_equal('incident-port call-voyage-vessel paths', l_path_count, 1);

  SELECT
    COUNT(*),
    COUNT(DISTINCT CONTAINER_ID),
    COUNT(DISTINCT BOOKING_ID),
    SUM(CASE WHEN DECISION_CODE = 'MISS' THEN 1 ELSE 0 END),
    SUM(CASE WHEN DECISION_CODE = 'TIGHT' THEN 1 ELSE 0 END),
    SUM(CASE WHEN DECISION_CODE = 'KEEP' THEN 1 ELSE 0 END)
  INTO
    l_path_count,
    l_path_containers,
    l_path_bookings,
    l_miss,
    l_tight,
    l_keep
  FROM GRAPH_TABLE (
    MARITIME_DEMO.MARITIME_SS_SHIP_SHORE_G
    MATCH
      (i IS DELAY_INCIDENT)
        -[impact IS AFFECTS_CONTAINER]->
      (c IS SHIPPING_CONTAINER)
        <-[bc IS CONTAINS_CONTAINER]-
      (b IS BOOKING),
      (c)
        -[next_leg IS CONNECTS_TO]->
      (outbound IS VOYAGE)
    WHERE i.INCIDENT_ID = 'INC-MAR-0001'
      AND impact.CONNECTION_ID = next_leg.CONNECTION_ID
    COLUMNS (
      c.CONTAINER_ID AS CONTAINER_ID,
      b.BOOKING_ID AS BOOKING_ID,
      outbound.VOYAGE_ID AS OUTBOUND_VOYAGE_ID,
      impact.DECISION_CODE AS DECISION_CODE,
      impact.CONNECTION_SLACK_MINUTES AS CONNECTION_SLACK_MINUTES
    )
  );

  assert_equal('incident-container-booking-next voyage paths', l_path_count, 36);
  assert_equal('graph path containers', l_path_containers, 36);
  assert_equal('graph path bookings', l_path_bookings, 18);
  assert_equal('graph MISS edges', l_miss, 9);
  assert_equal('graph TIGHT edges', l_tight, 6);
  assert_equal('graph KEEP edges', l_keep, 21);

  SELECT COUNT(*)
    INTO l_control_leak
    FROM GRAPH_TABLE (
      MARITIME_DEMO.MARITIME_SS_SHIP_SHORE_G
      MATCH
        (i IS DELAY_INCIDENT)
          -[impact IS AFFECTS_CONTAINER]->
        (c IS SHIPPING_CONTAINER)
      WHERE i.INCIDENT_ID = 'INC-MAR-0001'
        AND c.CONTAINER_ID = 'CNT-MAR-CTRL'
      COLUMNS (
        c.CONTAINER_ID AS CONTAINER_ID
      )
    );
  assert_equal('negative-control graph leaks', l_control_leak, 0);

  DBMS_OUTPUT.PUT_LINE('PASS MARITIME_SS MV-backed TRUSTED Property Graph contract ready');
END;
/

SELECT *
FROM GRAPH_TABLE (
  MARITIME_DEMO.MARITIME_SS_SHIP_SHORE_G
  MATCH
    (i IS DELAY_INCIDENT)
      -[impact IS AFFECTS_CONTAINER]->
    (c IS SHIPPING_CONTAINER)
      -[next_leg IS CONNECTS_TO]->
    (outbound IS VOYAGE)
  WHERE i.INCIDENT_ID = 'INC-MAR-0001'
    AND c.CONTAINER_ID = 'CNT-MAR-001'
    AND impact.CONNECTION_ID = next_leg.CONNECTION_ID
  COLUMNS (
    i.INCIDENT_ID AS INCIDENT_ID,
    c.CONTAINER_ID AS CONTAINER_ID,
    outbound.VOYAGE_ID AS OUTBOUND_VOYAGE_ID,
    impact.CONNECTION_ID AS CONNECTION_ID,
    impact.DECISION_CODE AS DECISION_CODE,
    impact.CONNECTION_SLACK_MINUTES AS CONNECTION_SLACK_MINUTES
  )
);

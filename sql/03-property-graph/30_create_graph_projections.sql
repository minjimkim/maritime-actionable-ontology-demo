-- Maritime Actionable Ontology Demo Kit
-- Read-only edge projections plus materialized snapshots for the SQL Property Graph.

SET SERVEROUTPUT ON

BEGIN
  IF UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')) <> 'MARITIME_DEMO'
     OR UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')) <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Connect directly as MARITIME_DEMO.');
  END IF;
END;
/

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_E_VOYAGE_VESSEL_V AS
SELECT
  'E-OPERATED-' || VOYAGE_ID AS EDGE_ID,
  VOYAGE_ID,
  VESSEL_ID,
  VOYAGE_ROLE,
  DATA_SCOPE
FROM MARITIME_DEMO.MARITIME_SS_VOYAGES;

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_E_VOYAGE_CALL_V AS
SELECT
  'E-CALL-' || PORT_CALL_ID AS EDGE_ID,
  VOYAGE_ID,
  PORT_CALL_ID,
  TERMINAL_CODE,
  DATA_SCOPE
FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS;

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_E_CALL_PORT_V AS
SELECT
  'E-PORT-' || PORT_CALL_ID AS EDGE_ID,
  PORT_CALL_ID,
  PORT_CODE,
  DATA_SCOPE
FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS;

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CALL_V AS
SELECT
  'E-INC-CALL-' || INCIDENT_ID AS EDGE_ID,
  INCIDENT_ID,
  PORT_CALL_ID,
  RECORDED_DELAY_MIN,
  DATA_SCOPE
FROM MARITIME_DEMO.MARITIME_SS_INCIDENTS;

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_E_CARRIED_ON_V AS
SELECT
  'E-CARRY-' || CONNECTION_ID AS EDGE_ID,
  CONNECTION_ID,
  CONTAINER_ID,
  INBOUND_VOYAGE_ID,
  PORT_CALL_ID,
  CONNECTION_STATE,
  DATA_SCOPE
FROM MARITIME_DEMO.MARITIME_SS_CONNECTIONS;

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_E_CONNECTS_TO_V AS
SELECT
  'E-CONNECT-' || CONNECTION_ID AS EDGE_ID,
  CONNECTION_ID,
  CONTAINER_ID,
  OUTBOUND_VOYAGE_ID,
  PORT_CALL_ID,
  PLANNED_READY_OFFSET_MIN,
  CONNECTION_STATE,
  DATA_SCOPE
FROM MARITIME_DEMO.MARITIME_SS_CONNECTIONS;

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_V AS
SELECT
  'E-INC-CONT-' || d.INCIDENT_ID || '-' || d.CONNECTION_ID
    || '-' || d.POLICY_VERSION AS EDGE_ID,
  d.INCIDENT_ID,
  d.CONTAINER_ID,
  d.CONNECTION_ID,
  d.DECISION_CODE,
  d.CONNECTION_SLACK_MINUTES,
  d.POLICY_VERSION,
  d.DATA_SCOPE
FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;

COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_V IS
  'Derived incident-to-container relationship with policy classification evidence.';
COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_V.DECISION_CODE IS
  'Policy classification on an edge; it does not assert that a failure has completed.';

-- Oracle RAC may temporarily reject ordinary views as graph element objects while a
-- two-stage rolling update is incomplete (ORA-42449). Keep the views as the stable
-- relational contract, but expose complete-refresh materialized snapshots to the graph.
DECLARE
  l_existing_mv_count PLS_INTEGER := 0;
  l_created_mv_count  PLS_INTEGER := 0;

  PROCEDURE ensure_materialized_view(
    p_mview_name VARCHAR2,
    p_create_ddl VARCHAR2
  ) IS
    l_mview_count    NUMBER;
    l_conflict_count NUMBER;
  BEGIN
    SELECT COUNT(*)
      INTO l_mview_count
      FROM USER_OBJECTS
     WHERE OBJECT_NAME = p_mview_name
       AND OBJECT_TYPE = 'MATERIALIZED VIEW';

    IF l_mview_count = 1 THEN
      l_existing_mv_count := l_existing_mv_count + 1;
      RETURN;
    ELSIF l_mview_count <> 0 THEN
      RAISE_APPLICATION_ERROR(
        -20311,
        'Materialized-view identity is ambiguous: ' || p_mview_name ||
        ', count=' || l_mview_count
      );
    END IF;

    SELECT COUNT(*)
      INTO l_conflict_count
      FROM USER_OBJECTS
     WHERE OBJECT_NAME = p_mview_name
       AND OBJECT_TYPE IN (
         'TABLE', 'VIEW', 'SEQUENCE', 'SYNONYM', 'PROCEDURE', 'FUNCTION',
         'PACKAGE', 'TYPE', 'PROPERTY GRAPH'
       );

    IF l_conflict_count <> 0 THEN
      RAISE_APPLICATION_ERROR(
        -20312,
        'Cannot create materialized view because its name is already used: ' ||
        p_mview_name
      );
    END IF;

    EXECUTE IMMEDIATE p_create_ddl;
    l_created_mv_count := l_created_mv_count + 1;
  END;
BEGIN
  ensure_materialized_view(
    'MARITIME_SS_E_VOYAGE_VESSEL_MV',
    q'[
      CREATE MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_VOYAGE_VESSEL_MV
        BUILD IMMEDIATE
        REFRESH COMPLETE ON DEMAND
      AS
      SELECT
        EDGE_ID,
        VOYAGE_ID,
        VESSEL_ID,
        VOYAGE_ROLE,
        DATA_SCOPE
      FROM MARITIME_DEMO.MARITIME_SS_E_VOYAGE_VESSEL_V
    ]'
  );

  ensure_materialized_view(
    'MARITIME_SS_E_VOYAGE_CALL_MV',
    q'[
      CREATE MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_VOYAGE_CALL_MV
        BUILD IMMEDIATE
        REFRESH COMPLETE ON DEMAND
      AS
      SELECT
        EDGE_ID,
        VOYAGE_ID,
        PORT_CALL_ID,
        TERMINAL_CODE,
        DATA_SCOPE
      FROM MARITIME_DEMO.MARITIME_SS_E_VOYAGE_CALL_V
    ]'
  );

  ensure_materialized_view(
    'MARITIME_SS_E_CALL_PORT_MV',
    q'[
      CREATE MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_CALL_PORT_MV
        BUILD IMMEDIATE
        REFRESH COMPLETE ON DEMAND
      AS
      SELECT
        EDGE_ID,
        PORT_CALL_ID,
        PORT_CODE,
        DATA_SCOPE
      FROM MARITIME_DEMO.MARITIME_SS_E_CALL_PORT_V
    ]'
  );

  ensure_materialized_view(
    'MARITIME_SS_E_INCIDENT_CALL_MV',
    q'[
      CREATE MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CALL_MV
        BUILD IMMEDIATE
        REFRESH COMPLETE ON DEMAND
      AS
      SELECT
        EDGE_ID,
        INCIDENT_ID,
        PORT_CALL_ID,
        RECORDED_DELAY_MIN,
        DATA_SCOPE
      FROM MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CALL_V
    ]'
  );

  ensure_materialized_view(
    'MARITIME_SS_E_CARRIED_ON_MV',
    q'[
      CREATE MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_CARRIED_ON_MV
        BUILD IMMEDIATE
        REFRESH COMPLETE ON DEMAND
      AS
      SELECT
        EDGE_ID,
        CONNECTION_ID,
        CONTAINER_ID,
        INBOUND_VOYAGE_ID,
        PORT_CALL_ID,
        CONNECTION_STATE,
        DATA_SCOPE
      FROM MARITIME_DEMO.MARITIME_SS_E_CARRIED_ON_V
    ]'
  );

  ensure_materialized_view(
    'MARITIME_SS_E_CONNECTS_TO_MV',
    q'[
      CREATE MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_CONNECTS_TO_MV
        BUILD IMMEDIATE
        REFRESH COMPLETE ON DEMAND
      AS
      SELECT
        EDGE_ID,
        CONNECTION_ID,
        CONTAINER_ID,
        OUTBOUND_VOYAGE_ID,
        PORT_CALL_ID,
        PLANNED_READY_OFFSET_MIN,
        CONNECTION_STATE,
        DATA_SCOPE
      FROM MARITIME_DEMO.MARITIME_SS_E_CONNECTS_TO_V
    ]'
  );

  ensure_materialized_view(
    'MARITIME_SS_E_INCIDENT_CONTAINER_MV',
    q'[
      CREATE MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_MV
        BUILD IMMEDIATE
        REFRESH COMPLETE ON DEMAND
      AS
      SELECT
        EDGE_ID,
        INCIDENT_ID,
        CONTAINER_ID,
        CONNECTION_ID,
        DECISION_CODE,
        CONNECTION_SLACK_MINUTES,
        POLICY_VERSION,
        DATA_SCOPE
      FROM MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_V
    ]'
  );

  IF l_existing_mv_count + l_created_mv_count <> 7 THEN
    RAISE_APPLICATION_ERROR(
      -20313,
      'Materialized-view lifecycle count failed: existing=' ||
      l_existing_mv_count || ', created=' || l_created_mv_count
    );
  END IF;

  -- Replacing a source view can invalidate its dependent materialized view. On a
  -- rerun (or partial first-run recovery), compile all seven and refresh them in
  -- one transaction to one source point in time.
  IF l_existing_mv_count > 0 THEN
    EXECUTE IMMEDIATE
      'ALTER MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_VOYAGE_VESSEL_MV COMPILE';
    EXECUTE IMMEDIATE
      'ALTER MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_VOYAGE_CALL_MV COMPILE';
    EXECUTE IMMEDIATE
      'ALTER MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_CALL_PORT_MV COMPILE';
    EXECUTE IMMEDIATE
      'ALTER MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CALL_MV COMPILE';
    EXECUTE IMMEDIATE
      'ALTER MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_CARRIED_ON_MV COMPILE';
    EXECUTE IMMEDIATE
      'ALTER MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_CONNECTS_TO_MV COMPILE';
    EXECUTE IMMEDIATE
      'ALTER MATERIALIZED VIEW MARITIME_DEMO.MARITIME_SS_E_INCIDENT_CONTAINER_MV COMPILE';

    DBMS_MVIEW.REFRESH(
      list =>
        'MARITIME_SS_E_VOYAGE_VESSEL_MV,MARITIME_SS_E_VOYAGE_CALL_MV,' ||
        'MARITIME_SS_E_CALL_PORT_MV,MARITIME_SS_E_INCIDENT_CALL_MV,' ||
        'MARITIME_SS_E_CARRIED_ON_MV,MARITIME_SS_E_CONNECTS_TO_MV,' ||
        'MARITIME_SS_E_INCIDENT_CONTAINER_MV',
      method => 'CCCCCCC',
      atomic_refresh => TRUE
    );

    DBMS_OUTPUT.PUT_LINE(
      'PASS MARITIME_SS graph materialized views atomically complete-refreshed'
    );
  ELSE
    DBMS_OUTPUT.PUT_LINE(
      'PASS MARITIME_SS graph materialized views created with BUILD IMMEDIATE'
    );
  END IF;
END;
/

DECLARE
  l_valid_projection_count NUMBER;
  l_valid_mview_count      NUMBER;
  l_fresh_mview_count      NUMBER;

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
    -- Keep both MINUS directions in independent inline views. Do not combine the
    -- set operators without parentheses; Oracle evaluates them left to right.
    l_sql :=
      'SELECT COUNT(*) FROM (' ||
      'SELECT ' || p_column_list || ' FROM MARITIME_DEMO.' || p_view_name ||
      ' MINUS SELECT ' || p_column_list || ' FROM MARITIME_DEMO.' || p_mview_name ||
      ')';
    EXECUTE IMMEDIATE l_sql INTO l_source_minus_mview;

    l_sql :=
      'SELECT COUNT(*) FROM (' ||
      'SELECT ' || p_column_list || ' FROM MARITIME_DEMO.' || p_mview_name ||
      ' MINUS SELECT ' || p_column_list || ' FROM MARITIME_DEMO.' || p_view_name ||
      ')';
    EXECUTE IMMEDIATE l_sql INTO l_mview_minus_source;

    EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM MARITIME_DEMO.' || p_view_name
      INTO l_source_count;
    EXECUTE IMMEDIATE
      'SELECT COUNT(*) FROM MARITIME_DEMO.' || p_mview_name
      INTO l_mview_count;

    IF l_source_minus_mview <> 0
       OR l_mview_minus_source <> 0
       OR l_source_count <> l_mview_count THEN
      RAISE_APPLICATION_ERROR(
        -20314,
        p_label || ' parity failed: source_minus_mv=' || l_source_minus_mview ||
        ', mv_minus_source=' || l_mview_minus_source ||
        ', source_count=' || l_source_count || ', mv_count=' || l_mview_count
      );
    END IF;

    DBMS_OUTPUT.PUT_LINE(
      'PASS ' || p_label || ' source-minus-MV=0, MV-minus-source=0, rows=' ||
      l_source_count
    );
  END;
BEGIN
  SELECT COUNT(*)
    INTO l_valid_projection_count
    FROM USER_OBJECTS
   WHERE OBJECT_NAME IN (
     'MARITIME_SS_E_VOYAGE_VESSEL_V', 'MARITIME_SS_E_VOYAGE_CALL_V',
     'MARITIME_SS_E_CALL_PORT_V', 'MARITIME_SS_E_INCIDENT_CALL_V',
     'MARITIME_SS_E_CARRIED_ON_V', 'MARITIME_SS_E_CONNECTS_TO_V',
     'MARITIME_SS_E_INCIDENT_CONTAINER_V'
   )
     AND OBJECT_TYPE = 'VIEW'
     AND STATUS = 'VALID';

  IF l_valid_projection_count <> 7 THEN
    RAISE_APPLICATION_ERROR(
      -20310,
      'Graph projection postcondition failed: valid_views=' || l_valid_projection_count
    );
  END IF;

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

  IF l_valid_mview_count <> 7 THEN
    RAISE_APPLICATION_ERROR(
      -20315,
      'Graph snapshot postcondition failed: valid_materialized_views=' ||
      l_valid_mview_count
    );
  END IF;

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

  IF l_fresh_mview_count <> 7 THEN
    RAISE_APPLICATION_ERROR(
      -20316,
      'Graph snapshot freshness failed: fresh_valid_materialized_views=' ||
      l_fresh_mview_count
    );
  END IF;

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

  DBMS_OUTPUT.PUT_LINE(
    'PASS MARITIME_SS graph projections and materialized snapshots validated'
  );
END;
/

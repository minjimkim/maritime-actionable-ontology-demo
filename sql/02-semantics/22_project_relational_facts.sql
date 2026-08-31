-- Maritime Actionable Ontology Demo Kit
-- Deterministic relational-to-RDF ABox projection.
-- SQL remains the sole calculator/classifier for ETA and connection slack.

SET SERVEROUTPUT ON

PROMPT ================================================================
PROMPT 22_project_relational_facts.sql
PROMPT Project manifest-bound MARITIME decision facts into MARITIME_SS_ABOX
PROMPT ================================================================

DECLARE
  TYPE t_name_list IS TABLE OF VARCHAR2(128);
  l_required_objects t_name_list := t_name_list(
    'MARITIME_SS_CONTEXT_V',
    'MARITIME_SS_SEMANTIC_INPUT_V',
    'MARITIME_SS_VESSELS',
    'MARITIME_SS_VOYAGES',
    'MARITIME_SS_PORTS',
    'MARITIME_SS_PORT_CALLS'
  );
  l_user     VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
  l_schema   VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
  l_count    NUMBER;
  l_missing  VARCHAR2(4000);
BEGIN
  IF l_user <> 'MARITIME_DEMO' OR l_schema <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Safety stop: connect directly as MARITIME_DEMO.');
  END IF;

  FOR i IN 1 .. l_required_objects.COUNT LOOP
    SELECT COUNT(*)
      INTO l_count
      FROM USER_OBJECTS
     WHERE OBJECT_NAME = l_required_objects(i)
       AND OBJECT_TYPE IN ('TABLE', 'VIEW')
       AND STATUS = 'VALID';

    IF l_count = 0 THEN
      l_missing := l_missing || CASE WHEN l_missing IS NULL THEN NULL ELSE ', ' END ||
                   l_required_objects(i);
    END IF;
  END LOOP;

  IF l_missing IS NOT NULL THEN
    RAISE_APPLICATION_ERROR(
      -20522,
      'Required relational semantic sources are missing/invalid: ' || l_missing ||
      '. Run sql/01-data and sql/02-decision first.'
    );
  END IF;

  SELECT COUNT(*)
    INTO l_count
    FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
   WHERE FIXTURE_VERSION = 'MARITIME-AO-FIXTURE-0.1.0'
     AND CONTRACT_VERSION = 'MARITIME-AO-CONTRACT-0.1.0'
     AND ONTOLOGY_VERSION = 'MARITIME-AO-ONTOLOGY-0.2.0'
     AND POLICY_VERSION = 'MARITIME-AO-CONNECTION-0.1.0'
     AND RUN_MODE = 'SYNTHETIC_DEMO'
     AND RESULT_PROVENANCE = 'SYNTHETIC_FIXTURE'
     AND APPROVAL_STATE = 'PREVIEW_ONLY'
     AND EXTERNAL_EXECUTION_YN = 'N';

  IF l_count <> 1 THEN
    RAISE_APPLICATION_ERROR(
      -20522,
      'Semantic projection requires exactly one manifest-bound 0.2.0 synthetic demo context; found ' ||
      l_count
    );
  END IF;

  SELECT COUNT(*)
    INTO l_count
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
   WHERE CONTEXT_SCENARIO_ID = 'INC-MAR-0001';

  IF l_count <> 36 THEN
    RAISE_APPLICATION_ERROR(
      -20522,
      'Semantic projection requires 36 deterministic SQL decisions; found ' || l_count
    );
  END IF;
END;
/

BEGIN
  SEM_APIS.TRUNCATE_RDF_GRAPH(
    rdf_graph_name => 'MARITIME_SS_ABOX',
    network_owner  => 'MARITIME_DEMO',
    network_name   => 'MARITIME_SS_RDF_NET'
  );
END;
/

DECLARE
  c_graph    CONSTANT VARCHAR2(30)  := 'MARITIME_SS_ABOX';
  c_network  CONSTANT VARCHAR2(30)  := 'MARITIME_SS_RDF_NET';
  c_owner    CONSTANT VARCHAR2(128) := 'MARITIME_DEMO';
  c_ns       CONSTANT VARCHAR2(500) := 'https://example.org/maritime-actionable-ontology/ontology/';
  c_id       CONSTANT VARCHAR2(500) := 'https://example.org/maritime-actionable-ontology/id/';
  c_rdf_type CONSTANT VARCHAR2(500) := '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>';
  c_xsd      CONSTANT VARCHAR2(500) := 'http://www.w3.org/2001/XMLSchema#';

  PROCEDURE log_rows(p_label IN VARCHAR2) IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE(RPAD(p_label, 44) || TO_CHAR(SQL%ROWCOUNT) || ' triples');
  END log_rows;
BEGIN
  -- One manifest-bound execution context ------------------------------------
  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'context/' || ctx.FIXTURE_VERSION || '>',
           c_rdf_type,
           '<' || c_ns || 'SemanticRunContext>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V ctx;
  log_rows('Semantic context type');

  FOR p IN (
    SELECT 'fixtureVersion' AS PREDICATE_NAME, FIXTURE_VERSION AS LEXICAL_VALUE
      FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
    UNION ALL
    SELECT 'contractVersion', CONTRACT_VERSION FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
    UNION ALL
    SELECT 'ontologyVersion', ONTOLOGY_VERSION FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
    UNION ALL
    SELECT 'policyVersion', POLICY_VERSION FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
    UNION ALL
    SELECT 'runMode', RUN_MODE FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
    UNION ALL
    SELECT 'resultProvenance', RESULT_PROVENANCE FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
    UNION ALL
    SELECT 'approvalState', APPROVAL_STATE FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
    UNION ALL
    SELECT 'externalExecutionYn', EXTERNAL_EXECUTION_YN FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
    UNION ALL
    SELECT 'dataScope', DATA_SCOPE FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V
  ) LOOP
    INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
    SELECT SDO_RDF_TRIPLE_S(
             c_graph,
             '<' || c_id || 'context/' || ctx.FIXTURE_VERSION || '>',
             '<' || c_ns || p.PREDICATE_NAME || '>',
             '"' || p.LEXICAL_VALUE || '"^^<' || c_xsd || 'string>',
             c_owner,
             c_network
           )
      FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V ctx;
  END LOOP;
  DBMS_OUTPUT.PUT_LINE(RPAD('Semantic context string facts', 44) || '9 triples');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'context/' || ctx.FIXTURE_VERSION || '>',
           '<' || c_ns || 'dataAsOf>',
           '"' || TO_CHAR(
             SYS_EXTRACT_UTC(ctx.DATA_AS_OF_TS),
             'YYYY-MM-DD"T"HH24:MI:SS"Z"'
           ) || '"^^<' || c_xsd || 'dateTime>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V ctx;
  log_rows('Semantic context as-of');

  -- Maritime master and event facts ----------------------------------------
  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'vessel/' || v.VESSEL_ID || '>',
           c_rdf_type,
           '<' || c_ns || 'Vessel>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_VESSELS v
   WHERE EXISTS (
     SELECT 1
       FROM MARITIME_DEMO.MARITIME_SS_VOYAGES voyage
      WHERE voyage.VESSEL_ID = v.VESSEL_ID
        AND (
          voyage.VOYAGE_ID IN (
            SELECT d.INBOUND_VOYAGE_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
          )
          OR voyage.VOYAGE_ID IN (
            SELECT d.OUTBOUND_VOYAGE_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
          )
        )
   );
  log_rows('Vessel types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'voyage/' || voyage.VOYAGE_ID || '>',
           c_rdf_type,
           '<' || c_ns || 'Voyage>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_VOYAGES voyage
   WHERE voyage.VOYAGE_ID IN (
     SELECT d.INBOUND_VOYAGE_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
     UNION
     SELECT d.OUTBOUND_VOYAGE_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
   );
  log_rows('Voyage types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'voyage/' || voyage.VOYAGE_ID || '>',
           '<' || c_ns || 'operatedBy>',
           '<' || c_id || 'vessel/' || voyage.VESSEL_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_VOYAGES voyage
   WHERE voyage.VOYAGE_ID IN (
     SELECT d.INBOUND_VOYAGE_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
     UNION
     SELECT d.OUTBOUND_VOYAGE_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
   );
  log_rows('Voyage-to-vessel facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'port/' || pc.PORT_CODE || '>',
           c_rdf_type,
           '<' || c_ns || 'Port>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS pc
   WHERE pc.PORT_CALL_ID IN (
     SELECT d.PORT_CALL_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
   );
  log_rows('Port types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'port-call/' || pc.PORT_CALL_ID || '>',
           c_rdf_type,
           '<' || c_ns || 'PortCall>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS pc
   WHERE pc.PORT_CALL_ID IN (
     SELECT d.PORT_CALL_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
   );
  log_rows('Port-call types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'port-call/' || pc.PORT_CALL_ID || '>',
           '<' || c_ns || 'locatedAt>',
           '<' || c_id || 'port/' || pc.PORT_CODE || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_PORT_CALLS pc
   WHERE pc.PORT_CALL_ID IN (
     SELECT d.PORT_CALL_ID FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
   );
  log_rows('Port-call-to-port facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'voyage/' || d.INBOUND_VOYAGE_ID || '>',
           '<' || c_ns || 'callsAt>',
           '<' || c_id || 'port-call/' || d.PORT_CALL_ID || '>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT INBOUND_VOYAGE_ID, PORT_CALL_ID
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Inbound-voyage-to-call facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'eta-event/' || d.SELECTED_ETA_EVENT_ID || '>',
           c_rdf_type,
           '<' || c_ns || 'EtaEvent>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT SELECTED_ETA_EVENT_ID
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Selected ETA-event types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'eta-event/' || d.SELECTED_ETA_EVENT_ID || '>',
           '<' || c_ns || 'reportedFor>',
           '<' || c_id || 'port-call/' || d.PORT_CALL_ID || '>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT SELECTED_ETA_EVENT_ID, PORT_CALL_ID
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Selected ETA-to-call facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'eta-event/' || d.SELECTED_ETA_EVENT_ID || '>',
           '<' || c_ns || 'revisionNumber>',
           '"' || TO_CHAR(d.SELECTED_REVISION_NO, 'FM9999999990') ||
             '"^^<' || c_xsd || 'integer>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT SELECTED_ETA_EVENT_ID, SELECTED_REVISION_NO
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Selected ETA revision facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'eta-event/' || d.SELECTED_ETA_EVENT_ID || '>',
           '<' || c_ns || 'reportedEtaAt>',
           '"' || TO_CHAR(
             SYS_EXTRACT_UTC(d.SELECTED_ETA_AT),
             'YYYY-MM-DD"T"HH24:MI:SS"Z"'
           ) || '"^^<' || c_xsd || 'dateTime>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT SELECTED_ETA_EVENT_ID, SELECTED_ETA_AT
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Selected ETA timestamp facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'eta-event/' || d.SELECTED_ETA_EVENT_ID || '>',
           '<' || c_ns || 'receivedAt>',
           '"' || TO_CHAR(
             SYS_EXTRACT_UTC(d.SELECTED_RECEIVED_AT),
             'YYYY-MM-DD"T"HH24:MI:SS"Z"'
           ) || '"^^<' || c_xsd || 'dateTime>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT SELECTED_ETA_EVENT_ID, SELECTED_RECEIVED_AT
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Selected ETA receipt facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'incident/' || d.INCIDENT_ID || '>',
           c_rdf_type,
           '<' || c_ns || 'DelayIncident>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT INCIDENT_ID
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Delay-incident types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'incident/' || d.INCIDENT_ID || '>',
           '<' || c_ns || 'affectsPortCall>',
           '<' || c_id || 'port-call/' || d.PORT_CALL_ID || '>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT INCIDENT_ID, PORT_CALL_ID
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Incident-to-call facts');

  -- Booking, container, and connection topology ----------------------------
  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'booking/' || d.BOOKING_ID || '>',
           c_rdf_type,
           '<' || c_ns || 'Booking>',
           c_owner,
           c_network
         )
    FROM (
      SELECT DISTINCT BOOKING_ID
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
    ) d;
  log_rows('Booking types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'booking/' || d.BOOKING_ID || '>',
           '<' || c_ns || 'containsContainer>',
           '<' || c_id || 'container/' || d.CONTAINER_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Booking-to-container facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'container/' || d.CONTAINER_ID || '>',
           c_rdf_type,
           '<' || c_ns || 'ShippingContainer>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Container types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'container/' || d.CONTAINER_ID || '>',
           '<' || c_ns || 'carriedOn>',
           '<' || c_id || 'voyage/' || d.INBOUND_VOYAGE_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Container inbound-voyage facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'container/' || d.CONTAINER_ID || '>',
           '<' || c_ns || 'connectsTo>',
           '<' || c_id || 'voyage/' || d.OUTBOUND_VOYAGE_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Container outbound-voyage facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'container/' || d.CONTAINER_ID || '>',
           '<' || c_ns || 'hasAssessment>',
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Container-to-assessment facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'connection/' || d.CONNECTION_ID || '>',
           c_rdf_type,
           '<' || c_ns || 'ContainerConnection>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Connection types');

  -- SQL-authored decision assertions ---------------------------------------
  -- The CASE below maps an already-computed DECISION_CODE. It does not
  -- perform numeric or timestamp classification in RDF/OWL.
  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           c_rdf_type,
           '<' || c_ns ||
             CASE d.DECISION_CODE
               WHEN 'MISS'  THEN 'MissAssessment'
               WHEN 'TIGHT' THEN 'TightAssessment'
               WHEN 'KEEP'  THEN 'KeepAssessment'
             END || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('SQL decision-specific assessment types');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'aboutIncident>',
           '<' || c_id || 'incident/' || d.INCIDENT_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment-to-incident facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'assessesConnection>',
           '<' || c_id || 'connection/' || d.CONNECTION_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment-to-connection facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'assessesBooking>',
           '<' || c_id || 'booking/' || d.BOOKING_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment-to-booking facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'selectedEtaEvent>',
           '<' || c_id || 'eta-event/' || d.SELECTED_ETA_EVENT_ID || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment-to-ETA facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'decisionResult>',
           '<' || c_ns || INITCAP(LOWER(d.DECISION_CODE)) || '>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('SQL decision-result concept facts');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'connectionId>',
           '"' || d.CONNECTION_ID || '"^^<' || c_xsd || 'string>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment connection-id literals');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'connectionSlackMinutes>',
           '"' || TO_CHAR(d.CONNECTION_SLACK_MINUTES, 'FM9999999990') ||
             '"^^<' || c_xsd || 'integer>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment slack-minute literals');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'connectionSlackSeconds>',
           '"' || TO_CHAR(d.CONNECTION_SLACK_SECONDS, 'FM9999999990') ||
             '"^^<' || c_xsd || 'integer>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment slack-second literals');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'policyVersion>',
           '"' || d.POLICY_VERSION || '"^^<' || c_xsd || 'string>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment policy-version literals');

  INSERT INTO MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX (TRIPLE)
  SELECT SDO_RDF_TRIPLE_S(
           c_graph,
           '<' || c_id || 'assessment/' || d.CONNECTION_ID || '>',
           '<' || c_ns || 'dataAsOf>',
           '"' || TO_CHAR(
             SYS_EXTRACT_UTC(d.DATA_AS_OF_TS),
             'YYYY-MM-DD"T"HH24:MI:SS"Z"'
           ) || '"^^<' || c_xsd || 'dateTime>',
           c_owner,
           c_network
         )
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d;
  log_rows('Assessment as-of literals');

  COMMIT;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/

DECLARE
  l_abox_count NUMBER;
  l_decisions  NUMBER;
  l_miss       NUMBER;
  l_tight      NUMBER;
  l_keep       NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO l_abox_count
    FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX;

  SELECT COUNT(*),
         SUM(CASE WHEN DECISION_CODE = 'MISS' THEN 1 ELSE 0 END),
         SUM(CASE WHEN DECISION_CODE = 'TIGHT' THEN 1 ELSE 0 END),
         SUM(CASE WHEN DECISION_CODE = 'KEEP' THEN 1 ELSE 0 END)
    INTO l_decisions, l_miss, l_tight, l_keep
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V;

  IF l_abox_count <> 664
     OR l_decisions <> 36
     OR l_miss <> 9
     OR l_tight <> 6
     OR l_keep <> 21 THEN
    RAISE_APPLICATION_ERROR(
      -20522,
      'ABox projection postcondition failed: triples=' || l_abox_count ||
      ', decisions=' || l_decisions || ', MISS/TIGHT/KEEP=' ||
      l_miss || '/' || l_tight || '/' || l_keep
    );
  END IF;

  DBMS_OUTPUT.PUT_LINE(
    'PASS MARITIME_SS_ABOX projected: 664 triples; SQL decisions 36 (9/6/21)'
  );
END;
/

PROMPT ===> ABox ready. Next: sql/02-semantics/23_create_inferred_graph.sql

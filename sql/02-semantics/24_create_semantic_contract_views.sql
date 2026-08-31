-- Maritime Actionable Ontology Demo Kit
-- Stable relational contracts over the active RDF graph collection.
-- Contracts fail closed if asserted TBox/ABox content changes after inference.

SET SERVEROUTPUT ON

PROMPT ================================================================
PROMPT 24_create_semantic_contract_views.sql
PROMPT Publish JVM-free active-triple adapter and stable semantic contracts
PROMPT ================================================================

DECLARE
  l_user   VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
  l_schema VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
BEGIN
  IF l_user <> 'MARITIME_DEMO' OR l_schema <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Safety stop: connect directly as MARITIME_DEMO.');
  END IF;
END;
/

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V AS
WITH current_tbox AS (
  SELECT (SELECT COUNT(*)
            FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_TBOX) AS TRIPLE_COUNT,
         MARITIME_DEMO.MARITIME_SS_RDF_GRAPH_SHA256('MARITIME_SS_TBOX') AS CONTENT_FINGERPRINT
    FROM DUAL
),
current_abox AS (
  SELECT (SELECT COUNT(*)
            FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX) AS TRIPLE_COUNT,
         MARITIME_DEMO.MARITIME_SS_RDF_GRAPH_SHA256('MARITIME_SS_ABOX') AS CONTENT_FINGERPRINT
    FROM DUAL
)
SELECT
  a.ACTIVE_RUN_ID,
  r.RUN_STATUS,
  a.INFERRED_GRAPH_NAME,
  a.COLLECTION_NAME,
  r.ONTOLOGY_VERSION,
  r.RULEBASE_VERSION,
  r.RUN_COMPLETED_AT AS INFERENCE_TS,
  a.ACTIVATED_AT,
  a.TBOX_TRIPLE_COUNT,
  a.ABOX_TRIPLE_COUNT,
  a.TBOX_FINGERPRINT,
  a.ABOX_FINGERPRINT,
  ctx.FIXTURE_VERSION,
  ctx.CONTRACT_VERSION,
  ctx.POLICY_VERSION,
  ctx.SCENARIO_ID,
  ctx.DATA_AS_OF_TS,
  ctx.RUN_MODE,
  ctx.RESULT_PROVENANCE,
  ctx.APPROVAL_STATE,
  ctx.EXTERNAL_EXECUTION_YN,
  ctx.DATA_SCOPE
FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE a
JOIN MARITIME_DEMO.MARITIME_SS_SEMANTIC_RUN r
  ON r.RUN_ID = a.ACTIVE_RUN_ID
 AND r.RUN_STATUS = 'SUCCEEDED'
 AND r.INFERRED_GRAPH_NAME = a.INFERRED_GRAPH_NAME
 AND r.COLLECTION_NAME = a.COLLECTION_NAME
 AND r.ONTOLOGY_VERSION = a.ONTOLOGY_VERSION
 AND r.RULEBASE_VERSION = a.RULEBASE_VERSION
 AND r.TBOX_TRIPLE_COUNT = a.TBOX_TRIPLE_COUNT
 AND r.ABOX_TRIPLE_COUNT = a.ABOX_TRIPLE_COUNT
 AND r.TBOX_FINGERPRINT = a.TBOX_FINGERPRINT
 AND r.ABOX_FINGERPRINT = a.ABOX_FINGERPRINT
 AND r.FIXTURE_VERSION = a.FIXTURE_VERSION
 AND r.CONTRACT_VERSION = a.CONTRACT_VERSION
 AND r.POLICY_VERSION = a.POLICY_VERSION
 AND r.SCENARIO_ID = a.SCENARIO_ID
 AND r.DATA_AS_OF_TS = a.DATA_AS_OF_TS
 AND r.RUN_MODE = a.RUN_MODE
 AND r.RESULT_PROVENANCE = a.RESULT_PROVENANCE
 AND r.APPROVAL_STATE = a.APPROVAL_STATE
 AND r.EXTERNAL_EXECUTION_YN = a.EXTERNAL_EXECUTION_YN
 AND r.DATA_SCOPE = a.DATA_SCOPE
CROSS JOIN current_tbox tbox
CROSS JOIN current_abox abox
CROSS JOIN MARITIME_DEMO.MARITIME_SS_CONTEXT_V ctx
WHERE a.CONTRACT_KEY = 'MARITIME_ACTIONABLE_ONTOLOGY'
  AND a.ONTOLOGY_VERSION = 'MARITIME-AO-ONTOLOGY-0.2.0'
  AND a.RULEBASE_VERSION = 'MARITIME-AO-RULEBASE-0.1.0'
  AND a.ONTOLOGY_VERSION = ctx.ONTOLOGY_VERSION
  AND a.FIXTURE_VERSION = ctx.FIXTURE_VERSION
  AND a.CONTRACT_VERSION = ctx.CONTRACT_VERSION
  AND a.POLICY_VERSION = ctx.POLICY_VERSION
  AND a.SCENARIO_ID = ctx.SCENARIO_ID
  AND a.DATA_AS_OF_TS = ctx.DATA_AS_OF_TS
  AND a.RUN_MODE = ctx.RUN_MODE
  AND a.RESULT_PROVENANCE = ctx.RESULT_PROVENANCE
  AND a.APPROVAL_STATE = ctx.APPROVAL_STATE
  AND a.EXTERNAL_EXECUTION_YN = ctx.EXTERNAL_EXECUTION_YN
  AND a.DATA_SCOPE = ctx.DATA_SCOPE
  AND a.TBOX_TRIPLE_COUNT = tbox.TRIPLE_COUNT
  AND a.ABOX_TRIPLE_COUNT = abox.TRIPLE_COUNT
  AND a.TBOX_FINGERPRINT = tbox.CONTENT_FINGERPRINT
  AND a.ABOX_FINGERPRINT = abox.CONTENT_FINGERPRINT;

DECLARE
  c_network         CONSTANT VARCHAR2(30) := 'MARITIME_SS_RDF_NET';
  c_owner           CONSTANT VARCHAR2(30) := 'MARITIME_DEMO';
  l_active_run_id   NUMBER;
  l_inferred_graph  VARCHAR2(128);
  l_collection      VARCHAR2(128);
  l_collection_lit  VARCHAR2(300);
  l_graph_lit       VARCHAR2(300);
  l_semu_object     VARCHAR2(261);
  l_value_object    VARCHAR2(261);
  l_sql             VARCHAR2(32767);
  l_count           NUMBER;
BEGIN
  BEGIN
    SELECT ACTIVE_RUN_ID, INFERRED_GRAPH_NAME, COLLECTION_NAME
      INTO l_active_run_id, l_inferred_graph, l_collection
      FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(
        -20526,
        'No active semantic run matches the current TBox/ABox fingerprints and ' ||
        'manifest ontology version. Run 21, 22, and 23 again.'
      );
    WHEN TOO_MANY_ROWS THEN
      RAISE_APPLICATION_ERROR(-20526, 'Semantic context must be a singleton.');
  END;

  l_inferred_graph := UPPER(DBMS_ASSERT.SIMPLE_SQL_NAME(l_inferred_graph));
  l_collection := DBMS_ASSERT.SIMPLE_SQL_NAME(l_collection);

  -- The A/B pair is a closed contract. Do not let metadata or an injected
  -- object name redirect the adapter to an unrelated collection.
  IF NOT (
       (l_collection = 'MARITIME_SS_KG_A' AND l_inferred_graph = 'MARITIME_SS_OWL2RL_A')
    OR (l_collection = 'MARITIME_SS_KG_B' AND l_inferred_graph = 'MARITIME_SS_OWL2RL_B')
  ) THEN
    RAISE_APPLICATION_ERROR(
      -20526,
      'Active semantic A/B slot is outside the Maritime Actionable Ontology allowlist.'
    );
  END IF;

  l_semu_object := DBMS_ASSERT.SQL_OBJECT_NAME(c_network || '#SEMU_' || l_collection);
  l_value_object := DBMS_ASSERT.SQL_OBJECT_NAME(c_network || '#RDF_VALUE$');

  SELECT COUNT(*)
    INTO l_count
    FROM USER_OBJECTS
   WHERE OBJECT_NAME = UPPER(l_semu_object)
     AND OBJECT_TYPE = 'VIEW'
     AND STATUS = 'VALID';

  IF l_count <> 1 THEN
    RAISE_APPLICATION_ERROR(
      -20526,
      'Active RDF graph collection ' || l_collection || ' is missing or invalid.'
    );
  END IF;

  SELECT COUNT(DISTINCT COLUMN_NAME)
    INTO l_count
    FROM USER_TAB_COLUMNS
   WHERE TABLE_NAME = UPPER(l_semu_object)
     AND COLUMN_NAME IN (
       'P_VALUE_ID', 'START_NODE_ID', 'CANON_END_NODE_ID',
       'END_NODE_ID', 'G_ID', 'MODEL_ID'
     );

  IF l_count <> 6 THEN
    RAISE_APPLICATION_ERROR(
      -20526,
      'Active SEMU collection does not expose the expected six-column contract.'
    );
  END IF;

  SELECT COUNT(*)
    INTO l_count
    FROM USER_OBJECTS
   WHERE OBJECT_NAME = UPPER(l_value_object)
     AND OBJECT_TYPE IN ('TABLE', 'VIEW')
     AND STATUS = 'VALID';

  IF l_count <> 1 THEN
    RAISE_APPLICATION_ERROR(-20526, 'RDF_VALUE$ is missing or invalid.');
  END IF;

  SELECT COUNT(DISTINCT COLUMN_NAME)
    INTO l_count
    FROM USER_TAB_COLUMNS
   WHERE TABLE_NAME = UPPER(l_value_object)
     AND COLUMN_NAME IN ('VALUE_ID', 'VALUE_NAME', 'VALUE_TYPE');

  IF l_count <> 3 THEN
    RAISE_APPLICATION_ERROR(
      -20526,
      'RDF_VALUE$ does not expose VALUE_ID, VALUE_NAME, and VALUE_TYPE.'
    );
  END IF;

  SELECT COUNT(*)
    INTO l_count
    FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#SEM_VMODEL_INFO
   WHERE OWNER = c_owner
     AND VIRTUAL_MODEL_NAME = l_collection
     AND STATUS = 'VALID';

  IF l_count <> 1 THEN
    RAISE_APPLICATION_ERROR(
      -20526,
      'Active RDF graph collection metadata is not exactly one VALID row.'
    );
  END IF;

  SELECT COUNT(*)
    INTO l_count
    FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#SEM_RULES_INDEX_INFO
   WHERE OWNER = c_owner
     AND INDEX_NAME = l_inferred_graph
     AND STATUS = 'VALID';

  IF l_count <> 1 THEN
    RAISE_APPLICATION_ERROR(
      -20526,
      'Active inferred graph metadata is not exactly one VALID row.'
    );
  END IF;

  l_collection_lit := DBMS_ASSERT.ENQUOTE_LITERAL(l_collection);
  l_graph_lit := DBMS_ASSERT.ENQUOTE_LITERAL(l_inferred_graph);

  -- JVM-free, owner-only implementation adapter. The active run ID and A/B
  -- object pair are embedded at publication time. A pointer switch, graph
  -- fingerprint drift, context drift, or invalid Oracle metadata therefore
  -- produces zero rows until this script republishes the adapter.
  l_sql := q'~
    CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V AS
    WITH bound_context AS (
      SELECT ctx.ACTIVE_RUN_ID,
             ctx.INFERRED_GRAPH_NAME,
             ctx.COLLECTION_NAME,
             ctx.TBOX_FINGERPRINT,
             ctx.ABOX_FINGERPRINT
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V ctx
       WHERE ctx.ACTIVE_RUN_ID = ~' || TO_CHAR(
         l_active_run_id,
         'TM9',
         'NLS_NUMERIC_CHARACTERS=''.,'''
       ) || q'~
         AND ctx.COLLECTION_NAME = ~' || l_collection_lit || q'~
         AND ctx.INFERRED_GRAPH_NAME = ~' || l_graph_lit || q'~
         AND (
           SELECT COUNT(*)
             FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#SEM_VMODEL_INFO vm
            WHERE vm.OWNER = 'MARITIME_DEMO'
              AND vm.VIRTUAL_MODEL_NAME = ctx.COLLECTION_NAME
         ) = 1
         AND (
           SELECT COUNT(*)
             FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#SEM_VMODEL_INFO vm
            WHERE vm.OWNER = 'MARITIME_DEMO'
              AND vm.VIRTUAL_MODEL_NAME = ctx.COLLECTION_NAME
              AND vm.STATUS = 'VALID'
         ) = 1
         AND (
           SELECT COUNT(*)
             FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#SEM_RULES_INDEX_INFO ri
            WHERE ri.OWNER = 'MARITIME_DEMO'
              AND ri.INDEX_NAME = ctx.INFERRED_GRAPH_NAME
         ) = 1
         AND (
           SELECT COUNT(*)
             FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#SEM_RULES_INDEX_INFO ri
            WHERE ri.OWNER = 'MARITIME_DEMO'
              AND ri.INDEX_NAME = ctx.INFERRED_GRAPH_NAME
              AND ri.STATUS = 'VALID'
         ) = 1
    )
    SELECT DISTINCT
      bc.ACTIVE_RUN_ID,
      bc.INFERRED_GRAPH_NAME,
      bc.COLLECTION_NAME,
      bc.TBOX_FINGERPRINT,
      bc.ABOX_FINGERPRINT,
      sv.VALUE_NAME AS SUBJECT_VALUE,
      sv.VALUE_TYPE AS SUBJECT_VALUE_TYPE,
      pv.VALUE_NAME AS PREDICATE_VALUE,
      pv.VALUE_TYPE AS PREDICATE_VALUE_TYPE,
      ov.VALUE_NAME AS OBJECT_VALUE,
      ov.VALUE_TYPE AS OBJECT_VALUE_TYPE
    FROM bound_context bc
    CROSS JOIN MARITIME_DEMO.~' || l_semu_object || q'~ t
    JOIN MARITIME_DEMO.~' || l_value_object || q'~ sv
      ON sv.VALUE_ID = t.START_NODE_ID
    JOIN MARITIME_DEMO.~' || l_value_object || q'~ pv
      ON pv.VALUE_ID = t.P_VALUE_ID
    JOIN MARITIME_DEMO.~' || l_value_object || q'~ ov
      ON ov.VALUE_ID = t.END_NODE_ID
  ~';
  EXECUTE IMMEDIATE l_sql;
END;
/

CREATE OR REPLACE VIEW MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V AS
WITH active_context AS (
  SELECT *
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V
),
connection_assessments AS (
  SELECT DISTINCT SUBJECT_VALUE AS ASSESSMENT
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
   WHERE SUBJECT_VALUE_TYPE = 'UR'
     AND PREDICATE_VALUE_TYPE = 'UR'
     AND OBJECT_VALUE_TYPE = 'UR'
     AND PREDICATE_VALUE =
         'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
     AND OBJECT_VALUE =
         'https://example.org/maritime-actionable-ontology/ontology/ConnectionAssessment'
),
decision_edges AS (
  SELECT DISTINCT SUBJECT_VALUE AS ASSESSMENT,
                  OBJECT_VALUE AS DECISION
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
   WHERE SUBJECT_VALUE_TYPE = 'UR'
     AND PREDICATE_VALUE_TYPE = 'UR'
     AND OBJECT_VALUE_TYPE = 'UR'
     AND PREDICATE_VALUE =
         'https://example.org/maritime-actionable-ontology/ontology/decisionResult'
),
semantic_decisions AS (
  SELECT ca.ASSESSMENT,
         MIN(de.DECISION) AS DECISION
    FROM connection_assessments ca
    JOIN decision_edges de
      ON de.ASSESSMENT = ca.ASSESSMENT
   GROUP BY ca.ASSESSMENT
  HAVING COUNT(*) = 1
),
review_candidates AS (
  SELECT DISTINCT SUBJECT_VALUE AS ASSESSMENT
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
   WHERE SUBJECT_VALUE_TYPE = 'UR'
     AND PREDICATE_VALUE_TYPE = 'UR'
     AND OBJECT_VALUE_TYPE = 'UR'
     AND PREDICATE_VALUE =
         'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
     AND OBJECT_VALUE =
         'https://example.org/maritime-actionable-ontology/ontology/ReviewCandidateAssessment'
)
SELECT
  sd.ASSESSMENT AS SEMANTIC_ASSESSMENT_IRI,
  sd.DECISION AS SEMANTIC_DECISION_IRI,
  d.INCIDENT_ID,
  d.CONNECTION_ID,
  d.INBOUND_VOYAGE_ID,
  d.OUTBOUND_VOYAGE_ID,
  d.PORT_CALL_ID,
  d.CONTAINER_ID,
  d.CONTAINER_NO,
  d.BOOKING_ID,
  d.BOOKING_NO,
  d.CUSTOMER_PRIORITY,
  d.CARGO_CATEGORY,
  d.ISO_TYPE,
  d.REEFER_YN,
  d.DANGEROUS_GOODS_YN,
  d.PRIORITY_CODE,
  d.SELECTED_ETA_EVENT_ID,
  d.SELECTED_REVISION_NO,
  d.SELECTED_ETA_AT,
  d.SELECTED_SOURCE_EVENT_AT,
  d.SELECTED_RECEIVED_AT,
  d.PLANNED_READY_OFFSET_MIN,
  d.ESTIMATED_READY_AT,
  d.LOAD_CUTOFF_AT,
  d.CONNECTION_SLACK_MINUTES,
  d.CONNECTION_SLACK_SECONDS,
  d.DECISION_CODE,
  d.DECISION_REASON,
  CASE WHEN rc.ASSESSMENT IS NOT NULL THEN 'Y' ELSE 'N' END
    AS SEMANTIC_REVIEW_CANDIDATE_YN,
  d.FIXTURE_VERSION,
  d.CONTRACT_VERSION,
  ac.ONTOLOGY_VERSION,
  ac.RULEBASE_VERSION,
  d.POLICY_VERSION,
  d.CONTEXT_SCENARIO_ID,
  d.DATA_AS_OF_TS,
  d.RUN_MODE,
  d.RESULT_PROVENANCE,
  d.APPROVAL_STATE,
  d.EXTERNAL_EXECUTION_YN,
  d.DATA_SCOPE,
  ac.INFERENCE_TS
FROM semantic_decisions sd
JOIN MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V d
  ON sd.ASSESSMENT =
     'https://example.org/maritime-actionable-ontology/id/assessment/' || d.CONNECTION_ID
 AND sd.DECISION =
     'https://example.org/maritime-actionable-ontology/ontology/' ||
     CASE d.DECISION_CODE
       WHEN 'MISS' THEN 'Miss'
       WHEN 'TIGHT' THEN 'Tight'
       WHEN 'KEEP' THEN 'Keep'
     END
CROSS JOIN active_context ac
LEFT JOIN review_candidates rc
  ON rc.ASSESSMENT = sd.ASSESSMENT
WHERE d.ONTOLOGY_VERSION = ac.ONTOLOGY_VERSION
  AND d.FIXTURE_VERSION = ac.FIXTURE_VERSION
  AND d.CONTRACT_VERSION = ac.CONTRACT_VERSION
  AND d.POLICY_VERSION = ac.POLICY_VERSION
  AND d.CONTEXT_SCENARIO_ID = ac.SCENARIO_ID
  AND d.DATA_AS_OF_TS = ac.DATA_AS_OF_TS
  AND d.RUN_MODE = ac.RUN_MODE
  AND d.RESULT_PROVENANCE = ac.RESULT_PROVENANCE
  AND d.APPROVAL_STATE = ac.APPROVAL_STATE
  AND d.EXTERNAL_EXECUTION_YN = ac.EXTERNAL_EXECUTION_YN
  AND d.DATA_SCOPE = ac.DATA_SCOPE;

COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V IS
  'Fail-closed active OWL2RL run, canonical RDF fingerprints, and manifest-bound synthetic demo provenance.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V IS
  'Owner-only JVM-free adapter over the active SEMU collection and RDF_VALUE$; not a public AI contract.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V IS
  'Stable semantic decision contract over the active decoded RDF set. SQL computes MISS/TIGHT/KEEP; OWL entails generic and review-candidate meaning.';
COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V.SEMANTIC_REVIEW_CANDIDATE_YN IS
  'Y is entailed for SQL MISS/TIGHT subclasses. It is not approval or execution authority.';

DECLARE
  l_context_rows NUMBER;
  l_adapter_rows NUMBER;
  l_adapter_contexts NUMBER;
  l_decision_rows NUMBER;
  l_review_rows NUMBER;
  l_valid_public_views NUMBER;
  l_valid_internal_views NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_context_rows
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V;

  SELECT COUNT(*),
         SUM(CASE WHEN SEMANTIC_REVIEW_CANDIDATE_YN = 'Y' THEN 1 ELSE 0 END)
    INTO l_decision_rows, l_review_rows
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V;

  SELECT COUNT(*), COUNT(DISTINCT ACTIVE_RUN_ID)
    INTO l_adapter_rows, l_adapter_contexts
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V;

  SELECT COUNT(*) INTO l_valid_public_views
    FROM USER_OBJECTS
   WHERE OBJECT_NAME IN (
     'MARITIME_SS_SEMANTIC_CONTEXT_V',
     'MARITIME_SS_SEMANTIC_DECISION_V'
   )
     AND OBJECT_TYPE = 'VIEW'
     AND STATUS = 'VALID';

  SELECT COUNT(*) INTO l_valid_internal_views
    FROM USER_OBJECTS
   WHERE OBJECT_NAME = 'MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V'
     AND OBJECT_TYPE = 'VIEW'
     AND STATUS = 'VALID';

  IF l_context_rows <> 1
     OR l_adapter_rows <= 0
     OR l_adapter_contexts <> 1
     OR l_decision_rows <> 36
     OR l_review_rows <> 15
     OR l_valid_public_views <> 2
     OR l_valid_internal_views <> 1 THEN
    RAISE_APPLICATION_ERROR(
      -20527,
      'Semantic contract postcondition failed: context=' || l_context_rows ||
      ', adapter_rows=' || l_adapter_rows ||
      ', adapter_contexts=' || l_adapter_contexts ||
      ', decisions=' || l_decision_rows || ', review=' || l_review_rows ||
      ', valid_public_views=' || l_valid_public_views ||
      ', valid_internal_views=' || l_valid_internal_views
    );
  END IF;

  DBMS_OUTPUT.PUT_LINE(
    'PASS JVM-free semantic contracts: context=1, decisions=36, review=15'
  );
END;
/

PROMPT ===> Contracts ready. Next: sql/02-semantics/25_validate_semantic_inference.sql

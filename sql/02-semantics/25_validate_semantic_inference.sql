-- Maritime Actionable Ontology Demo Kit
-- Fail-fast RDF graph, OWL2RL entailment, lineage, and stable-contract checks.

SET SERVEROUTPUT ON

PROMPT ================================================================
PROMPT 25_validate_semantic_inference.sql
PROMPT Validate Maritime Actionable Ontology semantic execution contract
PROMPT ================================================================

DECLARE
  l_user                 VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
  l_schema               VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
  l_graph_conflicts      MDSYS.RDF_LONGVARCHARARRAY;
  l_inferred_conflicts   MDSYS.RDF_LONGVARCHARARRAY;
  l_active_run_id        NUMBER;
  l_inferred_graph       VARCHAR2(128);
  l_collection           VARCHAR2(128);
  l_context_rows         NUMBER;
  l_tbox_count           NUMBER;
  l_abox_count           NUMBER;
  l_decision_count       NUMBER;
  l_miss_count           NUMBER;
  l_tight_count          NUMBER;
  l_keep_count           NUMBER;
  l_review_count         NUMBER;
  l_generic_count        NUMBER;
  l_raw_miss_count       NUMBER;
  l_raw_tight_count      NUMBER;
  l_raw_keep_count       NUMBER;
  l_numeric_owl_rules    NUMBER;
  l_contract_drift       NUMBER;
  l_control_leak         NUMBER;
  l_metadata_rows        NUMBER;
  l_adapter_contexts     NUMBER;
  l_collection_metadata NUMBER;
  l_inferred_metadata   NUMBER;
  l_representative       NUMBER;

  PROCEDURE assert_equal(
    p_label    IN VARCHAR2,
    p_actual   IN NUMBER,
    p_expected IN NUMBER
  ) IS
  BEGIN
    IF p_actual IS NULL OR p_actual <> p_expected THEN
      RAISE_APPLICATION_ERROR(
        -20528,
        p_label || ': expected ' || p_expected || ', got ' ||
        NVL(TO_CHAR(p_actual), 'NULL')
      );
    END IF;
    DBMS_OUTPUT.PUT_LINE('PASS ' || p_label || ' = ' || p_actual);
  END assert_equal;

  PROCEDURE assert_no_conflicts(
    p_label     IN VARCHAR2,
    p_conflicts IN MDSYS.RDF_LONGVARCHARARRAY
  ) IS
  BEGIN
    IF p_conflicts IS NULL OR p_conflicts.COUNT = 0 THEN
      DBMS_OUTPUT.PUT_LINE('PASS ' || p_label || ': no conflicts');
      RETURN;
    END IF;

    FOR i IN 1 .. LEAST(p_conflicts.COUNT, 20) LOOP
      DBMS_OUTPUT.PUT_LINE('  ' || p_conflicts(i));
    END LOOP;
    RAISE_APPLICATION_ERROR(
      -20528,
      p_label || ': ' || p_conflicts.COUNT || ' RDF/OWL conflicts'
    );
  END assert_no_conflicts;
BEGIN
  IF l_user <> 'MARITIME_DEMO' OR l_schema <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Safety stop: connect directly as MARITIME_DEMO.');
  END IF;

  SELECT COUNT(*),
         MAX(ACTIVE_RUN_ID),
         MAX(INFERRED_GRAPH_NAME),
         MAX(COLLECTION_NAME),
         MAX(TBOX_TRIPLE_COUNT),
         MAX(ABOX_TRIPLE_COUNT)
    INTO l_context_rows,
         l_active_run_id,
         l_inferred_graph,
         l_collection,
         l_tbox_count,
         l_abox_count
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V
   WHERE RUN_STATUS = 'SUCCEEDED'
     AND ONTOLOGY_VERSION = 'MARITIME-AO-ONTOLOGY-0.2.0'
     AND RULEBASE_VERSION = 'MARITIME-AO-RULEBASE-0.1.0'
     AND FIXTURE_VERSION = 'MARITIME-AO-FIXTURE-0.1.0'
     AND CONTRACT_VERSION = 'MARITIME-AO-CONTRACT-0.1.0'
     AND POLICY_VERSION = 'MARITIME-AO-CONNECTION-0.1.0'
     AND SCENARIO_ID = 'INC-MAR-0001'
     AND DATA_AS_OF_TS = TO_TIMESTAMP_TZ(
       '2026-08-12 09:00:00 UTC',
       'YYYY-MM-DD HH24:MI:SS TZR'
     )
     AND RUN_MODE = 'SYNTHETIC_DEMO'
     AND RESULT_PROVENANCE = 'SYNTHETIC_FIXTURE'
     AND APPROVAL_STATE = 'PREVIEW_ONLY'
     AND EXTERNAL_EXECUTION_YN = 'N'
     AND DATA_SCOPE = 'SYNTHETIC_SHIP_SHORE_DEMO';

  assert_equal('active semantic context rows', l_context_rows, 1);
  assert_equal('active TBox triples', l_tbox_count, 134);
  assert_equal('active ABox triples', l_abox_count, 664);

  l_inferred_graph := UPPER(DBMS_ASSERT.SIMPLE_SQL_NAME(l_inferred_graph));
  l_collection := UPPER(DBMS_ASSERT.SIMPLE_SQL_NAME(l_collection));

  IF NOT (
       (l_collection = 'MARITIME_SS_KG_A' AND l_inferred_graph = 'MARITIME_SS_OWL2RL_A')
    OR (l_collection = 'MARITIME_SS_KG_B' AND l_inferred_graph = 'MARITIME_SS_OWL2RL_B')
  ) THEN
    RAISE_APPLICATION_ERROR(
      -20528,
      'Active semantic A/B slot is outside the Maritime Actionable Ontology allowlist.'
    );
  END IF;

  SELECT COUNT(*)
    INTO l_collection_metadata
    FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#SEM_VMODEL_INFO
   WHERE OWNER = 'MARITIME_DEMO'
     AND VIRTUAL_MODEL_NAME = l_collection
     AND STATUS = 'VALID';
  assert_equal('active collection metadata rows', l_collection_metadata, 1);

  SELECT COUNT(*)
    INTO l_inferred_metadata
    FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#SEM_RULES_INDEX_INFO
   WHERE OWNER = 'MARITIME_DEMO'
     AND INDEX_NAME = l_inferred_graph
     AND STATUS = 'VALID';
  assert_equal('active inferred graph metadata rows', l_inferred_metadata, 1);

  SELECT COUNT(*)
    INTO l_metadata_rows
    FROM USER_OBJECTS
   WHERE OBJECT_NAME = 'MARITIME_SS_RDF_NET#SEMU_' || l_collection
     AND OBJECT_TYPE = 'VIEW'
     AND STATUS = 'VALID';
  assert_equal('active #SEMU_ collection views', l_metadata_rows, 1);

  SELECT COUNT(*)
    INTO l_metadata_rows
    FROM USER_OBJECTS
   WHERE OBJECT_NAME = 'MARITIME_SS_RDF_NET#RDF_VALUE$'
     AND OBJECT_TYPE IN ('TABLE', 'VIEW')
     AND STATUS = 'VALID';
  assert_equal('active #RDF_VALUE$ dictionaries', l_metadata_rows, 1);

  SELECT COUNT(*)
    INTO l_adapter_contexts
    FROM (
      SELECT DISTINCT
             ACTIVE_RUN_ID,
             INFERRED_GRAPH_NAME,
             COLLECTION_NAME,
             TBOX_FINGERPRINT,
             ABOX_FINGERPRINT
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
    );
  assert_equal('decoded active adapter contexts', l_adapter_contexts, 1);

  WITH adapter_context AS (
    SELECT DISTINCT
           ACTIVE_RUN_ID,
           INFERRED_GRAPH_NAME,
           COLLECTION_NAME,
           TBOX_FINGERPRINT,
           ABOX_FINGERPRINT
      FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
  )
  SELECT COUNT(*)
    INTO l_contract_drift
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V ctx
    FULL OUTER JOIN adapter_context a
      ON a.ACTIVE_RUN_ID = ctx.ACTIVE_RUN_ID
     AND a.INFERRED_GRAPH_NAME = ctx.INFERRED_GRAPH_NAME
     AND a.COLLECTION_NAME = ctx.COLLECTION_NAME
     AND a.TBOX_FINGERPRINT = ctx.TBOX_FINGERPRINT
     AND a.ABOX_FINGERPRINT = ctx.ABOX_FINGERPRINT
   WHERE ctx.ACTIVE_RUN_ID IS NULL
      OR a.ACTIVE_RUN_ID IS NULL;
  assert_equal('decoded active-context binding drift rows', l_contract_drift, 0);

  l_graph_conflicts := SEM_APIS.VALIDATE_RDF_GRAPH(
    rdf_graphs_in => SEM_MODELS('MARITIME_SS_TBOX', 'MARITIME_SS_ABOX'),
    criteria_in   => NULL,
    max_conflict  => 100,
    options       => NULL,
    network_owner => 'MARITIME_DEMO',
    network_name  => 'MARITIME_SS_RDF_NET'
  );
  assert_no_conflicts('MARITIME_SS_TBOX + MARITIME_SS_ABOX', l_graph_conflicts);

  l_inferred_conflicts := SEM_APIS.VALIDATE_INFERRED_GRAPH(
    rdf_graphs_in => SEM_MODELS('MARITIME_SS_TBOX', 'MARITIME_SS_ABOX'),
    rulebases_in  => SEM_RULEBASES('OWL2RL'),
    criteria_in   => NULL,
    max_conflict  => 100,
    options       => NULL,
    network_owner => 'MARITIME_DEMO',
    network_name  => 'MARITIME_SS_RDF_NET'
  );
  assert_no_conflicts('active OWL2RL entailment', l_inferred_conflicts);

  SELECT COUNT(*),
         SUM(CASE WHEN DECISION_CODE = 'MISS' THEN 1 ELSE 0 END),
         SUM(CASE WHEN DECISION_CODE = 'TIGHT' THEN 1 ELSE 0 END),
         SUM(CASE WHEN DECISION_CODE = 'KEEP' THEN 1 ELSE 0 END),
         SUM(CASE WHEN SEMANTIC_REVIEW_CANDIDATE_YN = 'Y' THEN 1 ELSE 0 END)
    INTO l_decision_count, l_miss_count, l_tight_count, l_keep_count, l_review_count
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V;

  assert_equal('semantic decision rows', l_decision_count, 36);
  assert_equal('semantic MISS rows', l_miss_count, 9);
  assert_equal('semantic TIGHT rows', l_tight_count, 6);
  assert_equal('semantic KEEP rows', l_keep_count, 21);
  assert_equal('inferred review-candidate rows', l_review_count, 15);

  SELECT
    (SELECT COUNT(*)
       FROM (
         SELECT CONNECTION_ID, DECISION_CODE
           FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
         MINUS
         SELECT CONNECTION_ID, DECISION_CODE
           FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V
       ))
    +
    (SELECT COUNT(*)
       FROM (
         SELECT CONNECTION_ID, DECISION_CODE
           FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V
         MINUS
         SELECT CONNECTION_ID, DECISION_CODE
           FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
       ))
    INTO l_contract_drift
    FROM DUAL;
  assert_equal('SQL-to-semantic decision drift rows', l_contract_drift, 0);

  SELECT COUNT(*)
    INTO l_contract_drift
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V
   WHERE (DECISION_CODE IN ('MISS', 'TIGHT') AND SEMANTIC_REVIEW_CANDIDATE_YN <> 'Y')
      OR (DECISION_CODE = 'KEEP' AND SEMANTIC_REVIEW_CANDIDATE_YN <> 'N')
      OR SEMANTIC_DECISION_IRI <>
         'https://example.org/maritime-actionable-ontology/ontology/' ||
         CASE DECISION_CODE
           WHEN 'MISS' THEN 'Miss'
           WHEN 'TIGHT' THEN 'Tight'
           WHEN 'KEEP' THEN 'Keep'
         END
      OR SEMANTIC_ASSESSMENT_IRI <>
         'https://example.org/maritime-actionable-ontology/id/assessment/' || CONNECTION_ID;
  assert_equal('semantic IRI/review mapping errors', l_contract_drift, 0);

  SELECT COUNT(*)
    INTO l_control_leak
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V
   WHERE CONNECTION_ID = 'CONN-MAR-CTRL'
      OR CONTAINER_ID = 'CNT-MAR-CTRL'
      OR PORT_CALL_ID = 'PC-CTRL-260812';
  assert_equal('semantic negative-control leaks', l_control_leak, 0);

  SELECT COUNT(*)
    INTO l_representative
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V
   WHERE CONNECTION_ID = 'CONN-MAR-001'
     AND DECISION_CODE = 'MISS'
     AND CONNECTION_SLACK_MINUTES = -140
     AND CONNECTION_SLACK_SECONDS = -8400
     AND SEMANTIC_REVIEW_CANDIDATE_YN = 'Y'
     AND ONTOLOGY_VERSION = 'MARITIME-AO-ONTOLOGY-0.2.0'
     AND RULEBASE_VERSION = 'MARITIME-AO-RULEBASE-0.1.0';
  assert_equal('representative semantic MISS row', l_representative, 1);

  -- Read the active unique-triple set directly. RDF_VALUE$ is joined only by
  -- the owner-only adapter; neither IDs nor this implementation view are part
  -- of the public decision-support contract.
  SELECT COUNT(DISTINCT SUBJECT_VALUE)
    INTO l_generic_count
    FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
   WHERE SUBJECT_VALUE_TYPE = 'UR'
     AND PREDICATE_VALUE_TYPE = 'UR'
     AND OBJECT_VALUE_TYPE = 'UR'
     AND PREDICATE_VALUE =
         'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
     AND OBJECT_VALUE =
         'https://example.org/maritime-actionable-ontology/ontology/ConnectionAssessment';
  assert_equal('entailed ConnectionAssessment instances', l_generic_count, 36);

  SELECT NVL(SUM(CASE WHEN x.CLASS_IRI =
                'https://example.org/maritime-actionable-ontology/ontology/MissAssessment'
              THEN 1 ELSE 0 END), 0),
         NVL(SUM(CASE WHEN x.CLASS_IRI =
                'https://example.org/maritime-actionable-ontology/ontology/TightAssessment'
              THEN 1 ELSE 0 END), 0),
         NVL(SUM(CASE WHEN x.CLASS_IRI =
                'https://example.org/maritime-actionable-ontology/ontology/KeepAssessment'
              THEN 1 ELSE 0 END), 0)
    INTO l_raw_miss_count, l_raw_tight_count, l_raw_keep_count
    FROM (
      SELECT DISTINCT SUBJECT_VALUE AS ASSESSMENT,
                      OBJECT_VALUE AS CLASS_IRI
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
       WHERE SUBJECT_VALUE_TYPE = 'UR'
         AND PREDICATE_VALUE_TYPE = 'UR'
         AND OBJECT_VALUE_TYPE = 'UR'
         AND PREDICATE_VALUE =
             'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
         AND OBJECT_VALUE IN (
           'https://example.org/maritime-actionable-ontology/ontology/MissAssessment',
           'https://example.org/maritime-actionable-ontology/ontology/TightAssessment',
           'https://example.org/maritime-actionable-ontology/ontology/KeepAssessment'
         )
    ) x;
  assert_equal('asserted MissAssessment instances', l_raw_miss_count, 9);
  assert_equal('asserted TightAssessment instances', l_raw_tight_count, 6);
  assert_equal('asserted KeepAssessment instances', l_raw_keep_count, 21);

  WITH decoded_decisions AS (
    SELECT DISTINCT SUBJECT_VALUE AS ASSESSMENT,
                    OBJECT_VALUE AS DECISION
      FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
     WHERE SUBJECT_VALUE_TYPE = 'UR'
       AND PREDICATE_VALUE_TYPE = 'UR'
       AND OBJECT_VALUE_TYPE = 'UR'
       AND PREDICATE_VALUE =
           'https://example.org/maritime-actionable-ontology/ontology/decisionResult'
  ),
  expected_decisions AS (
    SELECT 'https://example.org/maritime-actionable-ontology/id/assessment/' ||
           CONNECTION_ID AS ASSESSMENT,
           'https://example.org/maritime-actionable-ontology/ontology/' ||
           CASE DECISION_CODE
             WHEN 'MISS' THEN 'Miss'
             WHEN 'TIGHT' THEN 'Tight'
             WHEN 'KEEP' THEN 'Keep'
           END AS DECISION
      FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
  )
  SELECT COUNT(*)
    INTO l_contract_drift
    FROM expected_decisions e
    FULL OUTER JOIN decoded_decisions d
      ON d.ASSESSMENT = e.ASSESSMENT
     AND d.DECISION = e.DECISION
   WHERE e.ASSESSMENT IS NULL
      OR d.ASSESSMENT IS NULL;
  assert_equal('decoded semantic decision pair drift rows', l_contract_drift, 0);

  WITH decoded_review AS (
    SELECT DISTINCT SUBJECT_VALUE AS ASSESSMENT
      FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
     WHERE SUBJECT_VALUE_TYPE = 'UR'
       AND PREDICATE_VALUE_TYPE = 'UR'
       AND OBJECT_VALUE_TYPE = 'UR'
       AND PREDICATE_VALUE =
           'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
       AND OBJECT_VALUE =
           'https://example.org/maritime-actionable-ontology/ontology/ReviewCandidateAssessment'
  ),
  expected_review AS (
    SELECT 'https://example.org/maritime-actionable-ontology/id/assessment/' ||
           CONNECTION_ID AS ASSESSMENT
      FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_INPUT_V
     WHERE DECISION_CODE IN ('MISS', 'TIGHT')
  )
  SELECT COUNT(*)
    INTO l_contract_drift
    FROM expected_review e
    FULL OUTER JOIN decoded_review d
      ON d.ASSESSMENT = e.ASSESSMENT
   WHERE e.ASSESSMENT IS NULL
      OR d.ASSESSMENT IS NULL;
  assert_equal('decoded review-candidate set drift rows', l_contract_drift, 0);

  -- Guardrail: the ontology must not contain an owl:onProperty restriction on
  -- either numeric slack property. Numeric classification belongs to SQL.
  SELECT COUNT(*)
    INTO l_numeric_owl_rules
    FROM (
      SELECT DISTINCT SUBJECT_VALUE, PREDICATE_VALUE, OBJECT_VALUE
        FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE_TRIPLES_I_V
       WHERE PREDICATE_VALUE_TYPE = 'UR'
         AND OBJECT_VALUE_TYPE = 'UR'
         AND PREDICATE_VALUE = 'http://www.w3.org/2002/07/owl#onProperty'
         AND OBJECT_VALUE IN (
           'https://example.org/maritime-actionable-ontology/ontology/connectionSlackMinutes',
           'https://example.org/maritime-actionable-ontology/ontology/connectionSlackSeconds'
         )
    );
  assert_equal('numeric OWL classification rules', l_numeric_owl_rules, 0);

  SELECT COUNT(*)
    INTO l_metadata_rows
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
    JOIN MARITIME_DEMO.MARITIME_SS_CONTEXT_V ctx
      ON ctx.ONTOLOGY_VERSION = a.ONTOLOGY_VERSION
     AND ctx.FIXTURE_VERSION = a.FIXTURE_VERSION
     AND ctx.CONTRACT_VERSION = a.CONTRACT_VERSION
     AND ctx.POLICY_VERSION = a.POLICY_VERSION
     AND ctx.SCENARIO_ID = a.SCENARIO_ID
     AND ctx.DATA_AS_OF_TS = a.DATA_AS_OF_TS
     AND ctx.RUN_MODE = a.RUN_MODE
     AND ctx.RESULT_PROVENANCE = a.RESULT_PROVENANCE
     AND ctx.APPROVAL_STATE = a.APPROVAL_STATE
     AND ctx.EXTERNAL_EXECUTION_YN = a.EXTERNAL_EXECUTION_YN
     AND ctx.DATA_SCOPE = a.DATA_SCOPE
   WHERE a.CONTRACT_KEY = 'MARITIME_ACTIONABLE_ONTOLOGY'
     AND r.ONTOLOGY_VERSION = 'MARITIME-AO-ONTOLOGY-0.2.0'
     AND r.RULEBASE_VERSION = 'MARITIME-AO-RULEBASE-0.1.0'
     AND r.INFERRED_TRIPLE_COUNT > 0
     AND r.RUN_COMPLETED_AT IS NOT NULL
     AND REGEXP_LIKE(a.TBOX_FINGERPRINT, '^[0-9a-f]{64}$')
     AND REGEXP_LIKE(a.ABOX_FINGERPRINT, '^[0-9a-f]{64}$')
     AND a.TBOX_FINGERPRINT =
         MARITIME_DEMO.MARITIME_SS_RDF_GRAPH_SHA256('MARITIME_SS_TBOX')
     AND a.ABOX_FINGERPRINT =
         MARITIME_DEMO.MARITIME_SS_RDF_GRAPH_SHA256('MARITIME_SS_ABOX');
  assert_equal('active inference lineage rows', l_metadata_rows, 1);

  DBMS_OUTPUT.PUT_LINE(
    'PASS Maritime Actionable Ontology semantic execution: 36 SQL decisions, 15 OWL review candidates'
  );
END;
/

SELECT
  ACTIVE_RUN_ID,
  RUN_STATUS,
  ONTOLOGY_VERSION,
  RULEBASE_VERSION,
  TBOX_TRIPLE_COUNT,
  ABOX_TRIPLE_COUNT,
  FIXTURE_VERSION,
  CONTRACT_VERSION,
  POLICY_VERSION,
  DATA_AS_OF_TS,
  RUN_MODE,
  RESULT_PROVENANCE,
  INFERENCE_TS
FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_CONTEXT_V;

SELECT
  INCIDENT_ID,
  DECISION_CODE,
  SEMANTIC_REVIEW_CANDIDATE_YN,
  COUNT(*) AS DECISION_COUNT
FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_DECISION_V
GROUP BY INCIDENT_ID, DECISION_CODE, SEMANTIC_REVIEW_CANDIDATE_YN
ORDER BY DECISION_CODE;

PROMPT ===> Semantic layer validated. Continue with sql/03-property-graph.

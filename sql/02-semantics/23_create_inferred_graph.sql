-- Maritime Actionable Ontology Demo Kit
-- Builds OWL 2 RL closure in an inactive A/B slot, validates it, then moves
-- the active pointer. SQL-authored decisions remain asserted ABox facts.

SET SERVEROUTPUT ON

PROMPT ================================================================
PROMPT 23_create_inferred_graph.sql
PROMPT Build and activate Maritime Actionable Ontology OWL2RL entailment
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

BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLE MARITIME_DEMO.MARITIME_SS_SEMANTIC_RUN (
      RUN_ID                 NUMBER GENERATED ALWAYS AS IDENTITY,
      ONTOLOGY_VERSION       VARCHAR2(50)  NOT NULL,
      RULEBASE_VERSION       VARCHAR2(50)  NOT NULL,
      INFERRED_GRAPH_NAME    VARCHAR2(128) NOT NULL,
      COLLECTION_NAME        VARCHAR2(128) NOT NULL,
      RUN_STARTED_AT         TIMESTAMP WITH TIME ZONE NOT NULL,
      RUN_COMPLETED_AT       TIMESTAMP WITH TIME ZONE,
      INFERRED_TRIPLE_COUNT  NUMBER,
      TBOX_TRIPLE_COUNT      NUMBER,
      ABOX_TRIPLE_COUNT      NUMBER,
      TBOX_FINGERPRINT       VARCHAR2(64),
      ABOX_FINGERPRINT       VARCHAR2(64),
      FIXTURE_VERSION        VARCHAR2(50)  NOT NULL,
      CONTRACT_VERSION       VARCHAR2(50)  NOT NULL,
      POLICY_VERSION         VARCHAR2(50)  NOT NULL,
      SCENARIO_ID            VARCHAR2(30)  NOT NULL,
      DATA_AS_OF_TS          TIMESTAMP WITH TIME ZONE NOT NULL,
      RUN_MODE               VARCHAR2(30)  NOT NULL,
      RESULT_PROVENANCE      VARCHAR2(80)  NOT NULL,
      APPROVAL_STATE         VARCHAR2(30)  NOT NULL,
      EXTERNAL_EXECUTION_YN  CHAR(1)       NOT NULL,
      DATA_SCOPE             VARCHAR2(40)  NOT NULL,
      RUN_STATUS             VARCHAR2(20)  NOT NULL,
      ERROR_MESSAGE          VARCHAR2(4000),
      CONSTRAINT MARITIME_SS_SEM_RUN_PK PRIMARY KEY (RUN_ID),
      CONSTRAINT MARITIME_SS_SEM_RUN_STATUS_CK
        CHECK (RUN_STATUS IN ('STARTED', 'SUCCEEDED', 'FAILED'))
    )
  ]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE <> -955 THEN
      RAISE;
    END IF;
END;
/

BEGIN
  EXECUTE IMMEDIATE q'[
    CREATE TABLE MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE (
      CONTRACT_KEY          VARCHAR2(30)  NOT NULL,
      ACTIVE_RUN_ID         NUMBER        NOT NULL,
      INFERRED_GRAPH_NAME   VARCHAR2(128) NOT NULL,
      COLLECTION_NAME       VARCHAR2(128) NOT NULL,
      ONTOLOGY_VERSION      VARCHAR2(50)  NOT NULL,
      RULEBASE_VERSION      VARCHAR2(50)  NOT NULL,
      TBOX_TRIPLE_COUNT     NUMBER        NOT NULL,
      ABOX_TRIPLE_COUNT     NUMBER        NOT NULL,
      TBOX_FINGERPRINT      VARCHAR2(64)  NOT NULL,
      ABOX_FINGERPRINT      VARCHAR2(64)  NOT NULL,
      FIXTURE_VERSION       VARCHAR2(50)  NOT NULL,
      CONTRACT_VERSION      VARCHAR2(50)  NOT NULL,
      POLICY_VERSION        VARCHAR2(50)  NOT NULL,
      SCENARIO_ID           VARCHAR2(30)  NOT NULL,
      DATA_AS_OF_TS         TIMESTAMP WITH TIME ZONE NOT NULL,
      RUN_MODE              VARCHAR2(30)  NOT NULL,
      RESULT_PROVENANCE     VARCHAR2(80)  NOT NULL,
      APPROVAL_STATE        VARCHAR2(30)  NOT NULL,
      EXTERNAL_EXECUTION_YN CHAR(1)       NOT NULL,
      DATA_SCOPE            VARCHAR2(40)  NOT NULL,
      ACTIVATED_AT          TIMESTAMP WITH TIME ZONE NOT NULL,
      CONSTRAINT MARITIME_SS_SEM_ACTIVE_PK PRIMARY KEY (CONTRACT_KEY),
      CONSTRAINT MARITIME_SS_SEM_ACTIVE_RUN_UQ UNIQUE (ACTIVE_RUN_ID),
      CONSTRAINT MARITIME_SS_SEM_ACTIVE_RUN_FK FOREIGN KEY (ACTIVE_RUN_ID)
        REFERENCES MARITIME_DEMO.MARITIME_SS_SEMANTIC_RUN (RUN_ID),
      CONSTRAINT MARITIME_SS_SEM_ACTIVE_KEY_CK
        CHECK (CONTRACT_KEY = 'MARITIME_ACTIONABLE_ONTOLOGY')
    )
  ]';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE <> -955 THEN
      RAISE;
    END IF;
END;
/

-- Content-address asserted graphs independent of row order and internal RDF
-- value IDs. Complete object terms preserve datatype and language metadata.
CREATE OR REPLACE FUNCTION MARITIME_DEMO.MARITIME_SS_RDF_GRAPH_SHA256(
  p_graph_name IN VARCHAR2
) RETURN VARCHAR2
AUTHID DEFINER
IS
  c_network CONSTANT VARCHAR2(30) := 'MARITIME_SS_RDF_NET';
  c_sha256  CONSTANT PLS_INTEGER := DBMS_CRYPTO.HASH_SH256;

  l_graph_name VARCHAR2(30) := UPPER(TRIM(p_graph_name));
  l_manifest   CLOB;
  l_result     VARCHAR2(64);
  l_row_count  PLS_INTEGER := 0;

  PROCEDURE append_line(p_value IN VARCHAR2) IS
  BEGIN
    DBMS_LOB.WRITEAPPEND(l_manifest, LENGTH(p_value) + 1, p_value || CHR(10));
  END append_line;
BEGIN
  IF UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')) <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20523, 'MARITIME_SS_RDF_GRAPH_SHA256 requires MARITIME_DEMO.');
  END IF;

  IF l_graph_name NOT IN ('MARITIME_SS_TBOX', 'MARITIME_SS_ABOX') THEN
    RAISE_APPLICATION_ERROR(
      -20523,
      'Unsupported semantic fingerprint graph: ' || NVL(l_graph_name, '<NULL>')
    );
  END IF;

  DBMS_LOB.CREATETEMPORARY(l_manifest, TRUE, DBMS_LOB.CALL);
  append_line('MARITIME-SHIP-SHORE|RDF-GRAPH-SHA256|V1');

  IF l_graph_name = 'MARITIME_SS_TBOX' THEN
    FOR r IN (
      SELECT triple_hash
        FROM (
          SELECT LOWER(RAWTOHEX(DBMS_CRYPTO.HASH(
                   TO_CLOB('S') ||
                   TO_CHAR(LENGTH(terms.subject_term), 'TM9',
                     'NLS_NUMERIC_CHARACTERS=''.,''') || ':' ||
                   terms.subject_term ||
                   'P' || TO_CHAR(LENGTH(terms.predicate_term), 'TM9',
                     'NLS_NUMERIC_CHARACTERS=''.,''') || ':' ||
                   terms.predicate_term ||
                   'O' || TO_CHAR(DBMS_LOB.GETLENGTH(terms.object_term), 'TM9',
                     'NLS_NUMERIC_CHARACTERS=''.,''') || ':' ||
                   terms.object_term,
                   c_sha256
                 ))) AS triple_hash
            FROM (
              SELECT t.TRIPLE.GET_SUBJECT('MARITIME_DEMO', c_network) AS subject_term,
                     t.TRIPLE.GET_PROPERTY('MARITIME_DEMO', c_network) AS predicate_term,
                     t.TRIPLE.GET_OBJECT('MARITIME_DEMO', c_network) AS object_term
                FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_TBOX t
            ) terms
        )
       ORDER BY triple_hash
    ) LOOP
      append_line(r.triple_hash);
      l_row_count := l_row_count + 1;
    END LOOP;
  ELSE
    FOR r IN (
      SELECT triple_hash
        FROM (
          SELECT LOWER(RAWTOHEX(DBMS_CRYPTO.HASH(
                   TO_CLOB('S') ||
                   TO_CHAR(LENGTH(terms.subject_term), 'TM9',
                     'NLS_NUMERIC_CHARACTERS=''.,''') || ':' ||
                   terms.subject_term ||
                   'P' || TO_CHAR(LENGTH(terms.predicate_term), 'TM9',
                     'NLS_NUMERIC_CHARACTERS=''.,''') || ':' ||
                   terms.predicate_term ||
                   'O' || TO_CHAR(DBMS_LOB.GETLENGTH(terms.object_term), 'TM9',
                     'NLS_NUMERIC_CHARACTERS=''.,''') || ':' ||
                   terms.object_term,
                   c_sha256
                 ))) AS triple_hash
            FROM (
              SELECT t.TRIPLE.GET_SUBJECT('MARITIME_DEMO', c_network) AS subject_term,
                     t.TRIPLE.GET_PROPERTY('MARITIME_DEMO', c_network) AS predicate_term,
                     t.TRIPLE.GET_OBJECT('MARITIME_DEMO', c_network) AS object_term
                FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX t
            ) terms
        )
       ORDER BY triple_hash
    ) LOOP
      append_line(r.triple_hash);
      l_row_count := l_row_count + 1;
    END LOOP;
  END IF;

  append_line('ROWS=' || TO_CHAR(l_row_count, 'FM99999999999999999990'));
  l_result := LOWER(RAWTOHEX(DBMS_CRYPTO.HASH(l_manifest, c_sha256)));
  DBMS_LOB.FREETEMPORARY(l_manifest);
  RETURN l_result;
EXCEPTION
  WHEN OTHERS THEN
    IF DBMS_LOB.ISTEMPORARY(l_manifest) = 1 THEN
      DBMS_LOB.FREETEMPORARY(l_manifest);
    END IF;
    RAISE;
END;
/

DECLARE
  c_network       CONSTANT VARCHAR2(30) := 'MARITIME_SS_RDF_NET';
  c_tbox          CONSTANT VARCHAR2(30) := 'MARITIME_SS_TBOX';
  c_abox          CONSTANT VARCHAR2(30) := 'MARITIME_SS_ABOX';
  c_inferred_a    CONSTANT VARCHAR2(30) := 'MARITIME_SS_OWL2RL_A';
  c_inferred_b    CONSTANT VARCHAR2(30) := 'MARITIME_SS_OWL2RL_B';
  c_collection_a  CONSTANT VARCHAR2(30) := 'MARITIME_SS_KG_A';
  c_collection_b  CONSTANT VARCHAR2(30) := 'MARITIME_SS_KG_B';
  c_ontology_ver  CONSTANT VARCHAR2(50) := 'MARITIME-AO-ONTOLOGY-0.2.0';
  c_rulebase_ver  CONSTANT VARCHAR2(50) := 'MARITIME-AO-RULEBASE-0.1.0';

  l_count             NUMBER;
  l_tbox_count        NUMBER;
  l_abox_count        NUMBER;
  l_tbox_fingerprint  VARCHAR2(64);
  l_abox_fingerprint  VARCHAR2(64);
  l_inferred_count    NUMBER;
  l_run_id            NUMBER;
  l_error             VARCHAR2(1800);
  l_active_collection VARCHAR2(128);
  l_target_inferred   VARCHAR2(30);
  l_target_collection VARCHAR2(30);
  l_conflicts         MDSYS.RDF_LONGVARCHARARRAY;
  l_manifest_ontology     VARCHAR2(50);
  l_fixture_version       VARCHAR2(50);
  l_contract_version      VARCHAR2(50);
  l_policy_version        VARCHAR2(50);
  l_scenario_id           VARCHAR2(30);
  l_data_as_of_ts         TIMESTAMP WITH TIME ZONE;
  l_run_mode              VARCHAR2(30);
  l_result_provenance     VARCHAR2(80);
  l_approval_state        VARCHAR2(30);
  l_external_execution_yn CHAR(1);
  l_data_scope            VARCHAR2(40);
BEGIN
  SELECT ONTOLOGY_VERSION,
         FIXTURE_VERSION,
         CONTRACT_VERSION,
         POLICY_VERSION,
         SCENARIO_ID,
         DATA_AS_OF_TS,
         RUN_MODE,
         RESULT_PROVENANCE,
         APPROVAL_STATE,
         EXTERNAL_EXECUTION_YN,
         DATA_SCOPE
    INTO l_manifest_ontology,
         l_fixture_version,
         l_contract_version,
         l_policy_version,
         l_scenario_id,
         l_data_as_of_ts,
         l_run_mode,
         l_result_provenance,
         l_approval_state,
         l_external_execution_yn,
         l_data_scope
    FROM MARITIME_DEMO.MARITIME_SS_CONTEXT_V;

  IF c_ontology_ver <> l_manifest_ontology THEN
    RAISE_APPLICATION_ERROR(
      -20523,
      'Manifest ontology version does not match semantic runtime ' || c_ontology_ver
    );
  END IF;

  BEGIN
    SELECT COLLECTION_NAME
      INTO l_active_collection
      FROM MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE
     WHERE CONTRACT_KEY = 'MARITIME_ACTIONABLE_ONTOLOGY';
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      l_active_collection := NULL;
  END;

  IF l_active_collection = c_collection_a THEN
    l_target_inferred := c_inferred_b;
    l_target_collection := c_collection_b;
  ELSE
    l_target_inferred := c_inferred_a;
    l_target_collection := c_collection_a;
  END IF;

  INSERT INTO MARITIME_DEMO.MARITIME_SS_SEMANTIC_RUN (
    ONTOLOGY_VERSION,
    RULEBASE_VERSION,
    INFERRED_GRAPH_NAME,
    COLLECTION_NAME,
    RUN_STARTED_AT,
    FIXTURE_VERSION,
    CONTRACT_VERSION,
    POLICY_VERSION,
    SCENARIO_ID,
    DATA_AS_OF_TS,
    RUN_MODE,
    RESULT_PROVENANCE,
    APPROVAL_STATE,
    EXTERNAL_EXECUTION_YN,
    DATA_SCOPE,
    RUN_STATUS
  ) VALUES (
    c_ontology_ver,
    c_rulebase_ver,
    l_target_inferred,
    l_target_collection,
    SYSTIMESTAMP,
    l_fixture_version,
    l_contract_version,
    l_policy_version,
    l_scenario_id,
    l_data_as_of_ts,
    l_run_mode,
    l_result_provenance,
    l_approval_state,
    l_external_execution_yn,
    l_data_scope,
    'STARTED'
  ) RETURNING RUN_ID INTO l_run_id;
  COMMIT;

  SELECT COUNT(*)
    INTO l_tbox_count
    FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_TBOX;

  SELECT COUNT(*)
    INTO l_abox_count
    FROM MARITIME_DEMO.MARITIME_SS_RDF_NET#RDFT_MARITIME_SS_ABOX;

  IF l_tbox_count <> 134 OR l_abox_count <> 664 THEN
    RAISE_APPLICATION_ERROR(
      -20523,
      'Expected TBox/ABox counts 134/664 before inference; found ' ||
      l_tbox_count || '/' || l_abox_count
    );
  END IF;

  l_tbox_fingerprint := MARITIME_DEMO.MARITIME_SS_RDF_GRAPH_SHA256(c_tbox);
  l_abox_fingerprint := MARITIME_DEMO.MARITIME_SS_RDF_GRAPH_SHA256(c_abox);

  UPDATE MARITIME_DEMO.MARITIME_SS_SEMANTIC_RUN
     SET TBOX_TRIPLE_COUNT = l_tbox_count,
         ABOX_TRIPLE_COUNT = l_abox_count,
         TBOX_FINGERPRINT  = l_tbox_fingerprint,
         ABOX_FINGERPRINT  = l_abox_fingerprint
   WHERE RUN_ID = l_run_id;
  COMMIT;

  -- Only the inactive slot is replaced. A failed rebuild does not redirect
  -- the active semantic contract.
  SELECT COUNT(*)
    INTO l_count
    FROM USER_OBJECTS
   WHERE OBJECT_NAME = UPPER(c_network || '#SEMU_' || l_target_collection)
     AND OBJECT_TYPE = 'VIEW';

  IF l_count > 0 THEN
    SEM_APIS.DROP_RDF_GRAPH_COLLECTION(
      rdf_graph_collection_name => l_target_collection,
      network_owner              => 'MARITIME_DEMO',
      network_name               => c_network
    );
  END IF;

  SELECT COUNT(*)
    INTO l_count
    FROM USER_OBJECTS
   WHERE OBJECT_NAME = UPPER(c_network || '#SEMI_' || l_target_inferred)
     AND OBJECT_TYPE = 'VIEW';

  IF l_count > 0 THEN
    SEM_APIS.DROP_INFERRED_GRAPH(
      inferred_graph_name => l_target_inferred,
      network_owner        => 'MARITIME_DEMO',
      network_name         => c_network
    );
  END IF;

  SEM_APIS.CREATE_INFERRED_GRAPH(
    inferred_graph_name => l_target_inferred,
    rdf_graphs_in       => SEM_MODELS(c_tbox, c_abox),
    rulebases_in        => SEM_RULEBASES('OWL2RL'),
    passes              => SEM_APIS.REACH_CLOSURE,
    inf_components_in   => 'DOM,RAN,SCO',
    options             => 'PROOF=F,INC=F',
    network_owner       => 'MARITIME_DEMO',
    network_name        => c_network
  );

  l_conflicts := SEM_APIS.VALIDATE_INFERRED_GRAPH(
    rdf_graphs_in => SEM_MODELS(c_tbox, c_abox),
    rulebases_in  => SEM_RULEBASES('OWL2RL'),
    criteria_in   => NULL,
    max_conflict  => 100,
    options       => NULL,
    network_owner => 'MARITIME_DEMO',
    network_name  => c_network
  );

  IF l_conflicts IS NOT NULL AND l_conflicts.COUNT > 0 THEN
    RAISE_APPLICATION_ERROR(
      -20524,
      'Inactive OWL2RL slot returned ' || l_conflicts.COUNT || ' conflicts.'
    );
  END IF;

  SEM_APIS.CREATE_RDF_GRAPH_COLLECTION(
    rdf_graph_collection_name => l_target_collection,
    rdf_graphs                 => SEM_MODELS(c_tbox, c_abox),
    rulebases                  => SEM_RULEBASES('OWL2RL'),
    network_owner              => 'MARITIME_DEMO',
    network_name               => c_network
  );

  EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM ' ||
    DBMS_ASSERT.SQL_OBJECT_NAME(c_network || '#SEMI_' || l_target_inferred)
    INTO l_inferred_count;

  IF l_inferred_count <= 0 THEN
    RAISE_APPLICATION_ERROR(
      -20524,
      'Inactive inference slot contains no inferred triples: ' || l_target_inferred
    );
  END IF;

  UPDATE MARITIME_DEMO.MARITIME_SS_SEMANTIC_RUN
     SET RUN_COMPLETED_AT       = SYSTIMESTAMP,
         INFERRED_TRIPLE_COUNT = l_inferred_count,
         RUN_STATUS            = 'SUCCEEDED',
         ERROR_MESSAGE         = NULL
   WHERE RUN_ID = l_run_id;

  MERGE INTO MARITIME_DEMO.MARITIME_SS_SEMANTIC_ACTIVE d
  USING (
    SELECT 'MARITIME_ACTIONABLE_ONTOLOGY' AS CONTRACT_KEY,
           l_run_id AS ACTIVE_RUN_ID,
           l_target_inferred AS INFERRED_GRAPH_NAME,
           l_target_collection AS COLLECTION_NAME,
           c_ontology_ver AS ONTOLOGY_VERSION,
           c_rulebase_ver AS RULEBASE_VERSION,
           l_tbox_count AS TBOX_TRIPLE_COUNT,
           l_abox_count AS ABOX_TRIPLE_COUNT,
           l_tbox_fingerprint AS TBOX_FINGERPRINT,
           l_abox_fingerprint AS ABOX_FINGERPRINT,
           l_fixture_version AS FIXTURE_VERSION,
           l_contract_version AS CONTRACT_VERSION,
           l_policy_version AS POLICY_VERSION,
           l_scenario_id AS SCENARIO_ID,
           l_data_as_of_ts AS DATA_AS_OF_TS,
           l_run_mode AS RUN_MODE,
           l_result_provenance AS RESULT_PROVENANCE,
           l_approval_state AS APPROVAL_STATE,
           l_external_execution_yn AS EXTERNAL_EXECUTION_YN,
           l_data_scope AS DATA_SCOPE
      FROM DUAL
  ) s
     ON (d.CONTRACT_KEY = s.CONTRACT_KEY)
   WHEN MATCHED THEN UPDATE SET
     d.ACTIVE_RUN_ID       = s.ACTIVE_RUN_ID,
     d.INFERRED_GRAPH_NAME = s.INFERRED_GRAPH_NAME,
     d.COLLECTION_NAME     = s.COLLECTION_NAME,
     d.ONTOLOGY_VERSION    = s.ONTOLOGY_VERSION,
     d.RULEBASE_VERSION    = s.RULEBASE_VERSION,
     d.TBOX_TRIPLE_COUNT   = s.TBOX_TRIPLE_COUNT,
     d.ABOX_TRIPLE_COUNT   = s.ABOX_TRIPLE_COUNT,
     d.TBOX_FINGERPRINT    = s.TBOX_FINGERPRINT,
     d.ABOX_FINGERPRINT    = s.ABOX_FINGERPRINT,
     d.FIXTURE_VERSION     = s.FIXTURE_VERSION,
     d.CONTRACT_VERSION    = s.CONTRACT_VERSION,
     d.POLICY_VERSION      = s.POLICY_VERSION,
     d.SCENARIO_ID         = s.SCENARIO_ID,
     d.DATA_AS_OF_TS       = s.DATA_AS_OF_TS,
     d.RUN_MODE            = s.RUN_MODE,
     d.RESULT_PROVENANCE   = s.RESULT_PROVENANCE,
     d.APPROVAL_STATE      = s.APPROVAL_STATE,
     d.EXTERNAL_EXECUTION_YN = s.EXTERNAL_EXECUTION_YN,
     d.DATA_SCOPE          = s.DATA_SCOPE,
     d.ACTIVATED_AT        = SYSTIMESTAMP
   WHEN NOT MATCHED THEN INSERT (
     CONTRACT_KEY,
     ACTIVE_RUN_ID,
     INFERRED_GRAPH_NAME,
     COLLECTION_NAME,
     ONTOLOGY_VERSION,
     RULEBASE_VERSION,
     TBOX_TRIPLE_COUNT,
     ABOX_TRIPLE_COUNT,
     TBOX_FINGERPRINT,
     ABOX_FINGERPRINT,
     FIXTURE_VERSION,
     CONTRACT_VERSION,
     POLICY_VERSION,
     SCENARIO_ID,
     DATA_AS_OF_TS,
     RUN_MODE,
     RESULT_PROVENANCE,
     APPROVAL_STATE,
     EXTERNAL_EXECUTION_YN,
     DATA_SCOPE,
     ACTIVATED_AT
   ) VALUES (
     s.CONTRACT_KEY,
     s.ACTIVE_RUN_ID,
     s.INFERRED_GRAPH_NAME,
     s.COLLECTION_NAME,
     s.ONTOLOGY_VERSION,
     s.RULEBASE_VERSION,
     s.TBOX_TRIPLE_COUNT,
     s.ABOX_TRIPLE_COUNT,
     s.TBOX_FINGERPRINT,
     s.ABOX_FINGERPRINT,
     s.FIXTURE_VERSION,
     s.CONTRACT_VERSION,
     s.POLICY_VERSION,
     s.SCENARIO_ID,
     s.DATA_AS_OF_TS,
     s.RUN_MODE,
     s.RESULT_PROVENANCE,
     s.APPROVAL_STATE,
     s.EXTERNAL_EXECUTION_YN,
     s.DATA_SCOPE,
     SYSTIMESTAMP
   );
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('PASS active semantic run ID: ' || l_run_id);
  DBMS_OUTPUT.PUT_LINE('TBox/ABox triples: ' || l_tbox_count || '/' || l_abox_count);
  DBMS_OUTPUT.PUT_LINE('Inferred triples: ' || l_inferred_count);
  DBMS_OUTPUT.PUT_LINE('Activated collection: ' || l_target_collection);
EXCEPTION
  WHEN OTHERS THEN
    l_error := SUBSTR(
      SQLERRM || ' ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
      1,
      1800
    );

    IF l_run_id IS NOT NULL THEN
      UPDATE MARITIME_DEMO.MARITIME_SS_SEMANTIC_RUN
         SET RUN_COMPLETED_AT = SYSTIMESTAMP,
             RUN_STATUS       = 'FAILED',
             ERROR_MESSAGE    = l_error
       WHERE RUN_ID = l_run_id;
      COMMIT;
    END IF;

    RAISE_APPLICATION_ERROR(-20525, 'Maritime Actionable Ontology OWL2RL inference failed: ' || l_error);
END;
/

PROMPT ===> Entailment ready. Next: sql/02-semantics/24_create_semantic_contract_views.sql

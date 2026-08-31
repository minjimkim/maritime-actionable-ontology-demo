-- Maritime Actionable Ontology Demo Kit
-- Creates the schema-private Oracle RDF network and asserted TBox/ABox graphs.
-- Safe to rerun: an existing network and graphs are preserved.

SET SERVEROUTPUT ON

PROMPT ================================================================
PROMPT 20_create_semantic_network.sql
PROMPT Create MARITIME_SS_RDF_NET with MARITIME_SS_TBOX and MARITIME_SS_ABOX
PROMPT ================================================================

DECLARE
  c_network_name CONSTANT VARCHAR2(30) := 'MARITIME_SS_RDF_NET';
  c_tbox_graph   CONSTANT VARCHAR2(30) := 'MARITIME_SS_TBOX';
  c_abox_graph   CONSTANT VARCHAR2(30) := 'MARITIME_SS_ABOX';

  l_user         VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
  l_schema       VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
  l_count        PLS_INTEGER;

  PROCEDURE ensure_graph(p_graph_name IN VARCHAR2) IS
    l_view_name VARCHAR2(128) := c_network_name || '#RDFT_' || p_graph_name;
  BEGIN
    SELECT COUNT(*)
      INTO l_count
      FROM USER_OBJECTS
     WHERE OBJECT_NAME = UPPER(l_view_name)
       AND OBJECT_TYPE = 'VIEW';

    IF l_count = 0 THEN
      SEM_APIS.CREATE_RDF_GRAPH(
        rdf_graph_name => p_graph_name,
        table_name     => NULL,
        column_name    => NULL,
        network_owner  => l_schema,
        network_name   => c_network_name
      );
      DBMS_OUTPUT.PUT_LINE('Created RDF graph ' || p_graph_name || '.');
    ELSE
      DBMS_OUTPUT.PUT_LINE('RDF graph ' || p_graph_name || ' already exists; preserved.');
    END IF;
  END ensure_graph;
BEGIN
  IF l_user <> 'MARITIME_DEMO' OR l_schema <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Safety stop: connect directly as MARITIME_DEMO.');
  END IF;

  SELECT COUNT(*)
    INTO l_count
    FROM USER_TABLES
   WHERE TABLE_NAME = UPPER(c_network_name || '#RDF_PARAMETER');

  IF l_count = 0 THEN
    SEM_APIS.CREATE_RDF_NETWORK(
      tablespace_name => 'DATA',
      options         => 'NETWORK_STORAGE_FORM=UNESC',
      network_owner   => l_schema,
      network_name    => c_network_name
    );
    DBMS_OUTPUT.PUT_LINE('Created schema-private RDF network ' || c_network_name || '.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('RDF network ' || c_network_name || ' already exists; preserved.');
  END IF;

  ensure_graph(c_tbox_graph);
  ensure_graph(c_abox_graph);
EXCEPTION
  WHEN OTHERS THEN
    RAISE_APPLICATION_ERROR(
      -20520,
      'Unable to create Maritime Actionable Ontology RDF network/graphs. Confirm RDF Graph ' ||
      'support, EXECUTE on SEM_APIS, quota on DATA, and schema-private network ' ||
      'privileges. Cause: ' || SQLERRM
    );
END;
/

PROMPT ===> Semantic network ready. Next: sql/02-semantics/21_load_ontology.sql

-- Maritime Actionable Ontology Demo Kit
-- Read-only preflight. Run while connected directly as MARITIME_DEMO.

SET SERVEROUTPUT ON

DECLARE
  l_user          VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER'));
  l_schema        VARCHAR2(128) := UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
  l_object_count  NUMBER;
BEGIN
  IF l_user <> 'MARITIME_DEMO' OR l_schema <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(
      -20000,
      'Safety stop: connect directly as MARITIME_DEMO before running this kit.'
    );
  END IF;

  IF DBMS_DB_VERSION.VERSION < 23 THEN
    RAISE_APPLICATION_ERROR(
      -20002,
      'Oracle Database 23ai/Oracle AI Database 26ai or a later compatible release is required; detected '
      || DBMS_DB_VERSION.VERSION || '.' || DBMS_DB_VERSION.RELEASE
    );
  END IF;

  SELECT COUNT(*)
    INTO l_object_count
    FROM USER_OBJECTS
   WHERE OBJECT_NAME LIKE 'MARITIME\_SS\_%' ESCAPE '\';

  IF l_object_count <> 0 THEN
    RAISE_APPLICATION_ERROR(
      -20001,
      'MARITIME_SS_* objects already exist. This installer does not delete them.'
    );
  END IF;

  DBMS_OUTPUT.PUT_LINE('PASS schema = MARITIME_DEMO');
  DBMS_OUTPUT.PUT_LINE('PASS MARITIME_SS_* namespace is empty');
  DBMS_OUTPUT.PUT_LINE('PASS database major version >= 23');
  DBMS_OUTPUT.PUT_LINE(
    'REVIEW the database version and available objects below before Property Graph execution.'
  );
  DBMS_OUTPUT.PUT_LINE(
    'REQUIREMENT Oracle Database 23ai or later is required for the SQL Property Graph steps.'
  );
  DBMS_OUTPUT.PUT_LINE(
    'INFO this preflight reports evidence only; it does not certify feature availability or privileges.'
  );
END;
/

SELECT
  BANNER_FULL,
  'MANUAL_REVIEW_REQUIRED' AS PROPERTY_GRAPH_READINESS
FROM V$VERSION
WHERE BANNER_FULL LIKE 'Oracle Database%'
   OR BANNER_FULL LIKE 'Oracle AI Database%';

SELECT
  'INFO_ONLY' AS STATUS,
  'This kit validates local synthetic data contracts only; it does not configure an AI profile or any external service.' AS REVIEW_NOTE
FROM DUAL;

-- Maritime Actionable Ontology Demo Kit
-- Business metadata for decision-support, Select AI, and human reviewers.

SET SERVEROUTPUT ON

BEGIN
  IF UPPER(SYS_CONTEXT('USERENV', 'SESSION_USER')) <> 'MARITIME_DEMO'
     OR UPPER(SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')) <> 'MARITIME_DEMO' THEN
    RAISE_APPLICATION_ERROR(-20000, 'Connect directly as MARITIME_DEMO.');
  END IF;
END;
/

COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_DEMO_CLOCK IS
  'Fixed synthetic business clock for deterministic replay. Not the database execution time.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_POLICY_VERSIONS IS
  'Versioned closed-world connection policy. v0 is preview-only and cannot execute externally.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_FIXTURE_MANIFEST IS
  'Version handshake for fixture, data contract, ontology, policy, scenario, and data as-of.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_VESSELS IS
  'Synthetic vessel master. Names are demo labels and IMO_NUMBER is intentionally null.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_VOYAGES IS
  'Synthetic inbound, outbound, and negative-control voyage master.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_PORTS IS
  'Synthetic port reference used by the ship-shore golden scenario.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_PORT_CALLS IS
  'One row per voyage port call; PORT_CALL_ID is the ship-to-shore correlation key.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_ETA_EVENTS IS
  'Append-shaped ETA events preserving source time, receive time, revision, and reported ETA.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_TERMINAL_CUTOFFS IS
  'Shore-side terminal load cutoff for a port call and connecting outbound voyage.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_INCIDENTS IS
  'Synthetic review situation rooted at a port call. It records an ETA change, not a confirmed cause.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_BOOKINGS IS
  'Synthetic booking master. One booking may contain multiple containers.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_CONTAINERS IS
  'Synthetic container master. Container numbers are demo identifiers.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_BOOKING_CONTAINERS IS
  'Booking-to-container relationship. v0 assigns each container to exactly one booking.';
COMMENT ON TABLE MARITIME_DEMO.MARITIME_SS_CONNECTIONS IS
  'One row per container transshipment connection from inbound voyage to outbound voyage.';

COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_ETA_EVENTS.REVISION_NO IS
  'Monotonic source revision used to select the latest ETA; receive order must not override it.';
COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_ETA_EVENTS.SOURCE_EVENT_AT IS
  'Timestamp recorded by the synthetic ship-side source.';
COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_ETA_EVENTS.RECEIVED_AT IS
  'Timestamp when the synthetic shore ingestion layer received the event.';
COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_ETA_EVENTS.REPORTED_ETA_AT IS
  'ETA carried by this revision. It is not the event creation or receive timestamp.';
COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_CONNECTIONS.PLANNED_READY_OFFSET_MIN IS
  'Synthetic shore plan minutes added to selected ETA to estimate yard readiness.';
COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_POLICY_VERSIONS.TIGHT_THRESHOLD_MIN IS
  'TIGHT upper bound: non-negative slack below this many minutes.';
COMMENT ON COLUMN MARITIME_DEMO.MARITIME_SS_POLICY_VERSIONS.EXTERNAL_EXECUTION_YN IS
  'Always N in v0. No approval, booking, terminal, notification, or vessel command is executed.';

DECLARE
  l_table_comment_count   NUMBER;
  l_column_comment_count  NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO l_table_comment_count
    FROM USER_TAB_COMMENTS
   WHERE TABLE_NAME LIKE 'MARITIME\_SS\_%' ESCAPE '\'
     AND COMMENTS IS NOT NULL;

  SELECT COUNT(*)
    INTO l_column_comment_count
    FROM USER_COL_COMMENTS
   WHERE TABLE_NAME LIKE 'MARITIME\_SS\_%' ESCAPE '\'
     AND COMMENTS IS NOT NULL;

  IF l_table_comment_count < 14 OR l_column_comment_count < 7 THEN
    RAISE_APPLICATION_ERROR(
      -20110,
      'Comment postcondition failed: table_comments=' || l_table_comment_count
      || ', column_comments=' || l_column_comment_count
    );
  END IF;

  DBMS_OUTPUT.PUT_LINE('PASS MARITIME_SS business comments created and validated');
END;
/

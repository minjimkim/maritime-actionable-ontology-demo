# Demo Walkthrough

## Message to establish first

This is a synthetic maritime decision-support demo. It helps a reviewer understand a delayed-arrival scenario and its connected bookings; it does not automate an operational action.

## 1. Start with the relational facts

Show the synthetic tables for ETA events, port calls, container connections, bookings, and containers. Explain that the tables hold the operational facts, but an analyst normally needs multiple joins to understand one late-arrival event and its impact.

Then show the point-in-time result:

- a declared review time;
- the latest eligible ETA revision;
- the resulting connection assessment distribution: 9 `MISS`, 6 `TIGHT`, 21 `KEEP`.

Key narration: “The classification is deterministic SQL. The system selects only facts received by the stated review time, calculates the connection timing, and applies the versioned policy.”

## 2. Show semantic meaning in RDF

Use the RDF assets or the database RDF network to show that the relational entities and their relationships are represented as triples. The ontology defines these two facts:

```text
MissAssessment  ──subClassOf──> ReviewCandidateAssessment
TightAssessment ──subClassOf──> ReviewCandidateAssessment
```

Run the same query twice:

1. against asserted facts without an OWL rulebase, where direct `ReviewCandidateAssessment` instances are not stored;
2. with the OWL2RL rulebase applied, where the inferred review-candidate count is 15.

Key narration: “The rulebase did not recompute ETA or alter the SQL decision. It added the common business meaning that `MISS` and `TIGHT` both require human review.”

## 3. Trace the impact in the Property Graph

Open the prebuilt Property Graph and show its schema preview. It connects an incident to a port call, voyage, vessel, containers, bookings, and onward voyages.

Begin with a broad graph question, for example:

> Show the delayed incident, its port call, port, inbound voyage, and vessel.

Then narrow to the highest-impact connection identified by the deterministic assessment:

> Show the booking, container, and onward voyage connected to the most negative `MISS` connection.

Use graph visualization to make the difference clear: the first view gives the incident context; the second isolates a concrete downstream impact path.

## 4. Finish with the human-review boundary

Show the read-only action-preview view for `MISS` and `TIGHT` decisions. It suggests which role should review a candidate and by when, but it neither requests approval nor performs a booking, terminal, vessel, notification, or external-system change.

Key narration: “The output is an explainable work queue for a person. Any operational choice remains outside this demo and under human control.”

## Suggested flow in one line

**Synthetic facts → point-in-time SQL decision → RDF meaning → Property Graph impact path → human-reviewed preview.**

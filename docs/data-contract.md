# Point-in-Time Data Contract

## Why a time boundary matters

Operational decisions must use only the information that was available at the review time. The synthetic fixture declares this review time as `DATA_AS_OF_TS`. An ETA revision received after that time must not change the decision for that review.

## Core contract

For each port call, the decision layer:

1. admits ETA events only when `RECEIVED_AT <= DATA_AS_OF_TS`;
2. uses accepted, in-scope events only;
3. selects the newest eligible revision for the port call;
4. calculates estimated container-ready time from the selected ETA and planned ready offset;
5. compares the timestamp instant with the outbound load cutoff and policy threshold.

The contract keeps `SOURCE_EVENT_AT` and `RECEIVED_AT` separate. An event may have occurred earlier but be unavailable to an operator until it is received. This distinction prevents a retrospective view from silently using information that was not known at the stated time.

## Deterministic decision policy

The policy is evaluated in SQL from timestamp instants, not from display-rounded minutes:

| Condition | Decision | Meaning in this demo |
|---|---|---|
| Estimated ready time is after the load cutoff | `MISS` | The connection cannot meet the configured cutoff under the selected facts. |
| Estimated ready time is before the cutoff but inside the configured threshold | `TIGHT` | The connection remains possible but needs additional human attention. |
| Estimated ready time is at or before the threshold boundary | `KEEP` | The current plan remains within the configured policy boundary. |

`CONNECTION_SLACK_MINUTES` is a useful display value, but the policy uses exact timestamp comparisons. The SQL result is a closed-world decision for the declared fixture, policy version, and as-of time.

## Provenance fields

The pipeline carries the following context with its decisions and semantic facts:

| Field | Purpose |
|---|---|
| `FIXTURE_VERSION` | Identifies the synthetic fixture. |
| `CONTRACT_VERSION` | Identifies the point-in-time selection logic. |
| `POLICY_VERSION` | Identifies the decision boundary and thresholds. |
| `ONTOLOGY_VERSION` | Identifies the semantic vocabulary used for inference. |
| `DATA_AS_OF_TS` | Declares the latest information permitted for the review. |
| `RUN_MODE` / `RESULT_PROVENANCE` | Marks the output as synthetic demonstration material. |
| `APPROVAL_STATE` / `EXTERNAL_EXECUTION_YN` | Explicitly records preview-only, no-execution behavior. |

## Expected fixture results

At the declared synthetic as-of time, the fixture contains 36 assessed connections: 9 `MISS`, 6 `TIGHT`, and 21 `KEEP`. The 15 `MISS` and `TIGHT` assessments become semantic review candidates through the ontology hierarchy; that inference never changes the underlying deterministic decision.

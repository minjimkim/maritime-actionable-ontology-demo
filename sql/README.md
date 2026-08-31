# SQL Execution Order

Run the scripts in a dedicated, empty demo schema after replacing the placeholder schema name `MARITIME_DEMO` consistently for your environment.

1. `00-setup/00_preflight.sql`
2. `01-data/10_ddl.sql`
3. `01-data/11_seed_golden_scenario.sql`
4. `01-data/12_comments.sql`
5. `01-data/13_validate_golden_scenario.sql`
6. `02-decision/20_create_decision_views.sql`
7. `02-decision/21_validate_decisions.sql`
8. `02-semantics/20_create_semantic_network.sql` through `25_validate_semantic_inference.sql`
9. `03-property-graph/30_create_graph_projections.sql` through `32_validate_graph.sql`
10. `04-action/40_create_action_preview.sql` and `41_validate_action_preview.sql`

The scripts are intentionally fail-closed: stop if a precondition or expected validation result does not pass. They create synthetic demo objects only and never call external systems or perform operational writes.

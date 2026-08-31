# Security and Scope

## Included

This repository intentionally includes only material needed to reproduce a synthetic demonstration:

- SQL DDL, seed, contract, decision, semantic, graph, and validation scripts;
- a small OWL ontology and Graph Studio RDF assets;
- expected validation counts and documentation.

## Explicitly excluded

Do not add any of the following to the repository:

- production, partner, employee, or other real operational data;
- database wallets, credentials, private keys, certificates, tokens, or `.env` files;
- local connection settings, unredacted console output, trace logs, or screenshots containing environment details;
- meeting notes, internal decisions, or organization-specific requirements;
- files that trigger or authorize external actions.

## Operational boundary

The project is a decision-support demonstration, not an operational control system.

- All scenario identities and records are synthetic.
- Deterministic SQL creates an assessment; RDF/OWL adds a reusable review category.
- A review candidate is not an approval, a command, or proof that an operational failure has already occurred.
- The action layer is read-only and advertises `PREVIEW_ONLY` with external execution disabled.
- Any AI-generated summary is optional, advisory-only, and must be reviewed by a human; this repository does not include an AI profile, credential, or external model call.
- Any real-world communication, booking change, terminal instruction, vessel action, or notification requires a separate governed process and human authorization.

## Fail-closed behavior

The SQL scripts check schema identity, required objects, and expected conditions before continuing. If a required precondition or validation fails, treat the output as unavailable rather than attempting to substitute an unverified result.

## Responsible reuse

If adapting the project for another domain, replace the synthetic fixture, define the domain policy explicitly, preserve point-in-time semantics, and have the responsible business owner validate every decision rule. Do not represent a prototype outcome as a production recommendation.

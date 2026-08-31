import { createHash } from 'node:crypto';
import { copyFile, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const ontologySource = path.resolve(
  here,
  '../../ontology/maritime-actionable-ontology.ttl',
);

const tboxTarget = path.join(here, 'maritime_actionable_ontology_gs_tbox.ttl');
const aboxTarget = path.join(here, 'maritime_actionable_ontology_gs_abox.nt');
const manifestTarget = path.join(here, 'manifest.json');

const NS = 'https://example.org/maritime-actionable-ontology/ontology/';
const ID = 'https://example.org/maritime-actionable-ontology/id/';
const RDF_TYPE = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type';
const XSD = 'http://www.w3.org/2001/XMLSchema#';

const iri = (value) => `<${value}>`;
const stringLiteral = (value) => `"${value}"^^<${XSD}string>`;
const integerLiteral = (value) => `"${value}"^^<${XSD}integer>`;
const dateTimeLiteral = (value) => `"${value}"^^<${XSD}dateTime>`;
const triple = (subject, predicate, object) => `${iri(subject)} ${iri(predicate)} ${object} .`;
const iriTriple = (subject, predicate, object) => triple(subject, predicate, iri(object));
const pad3 = (value) => String(value).padStart(3, '0');

const fixtureVersion = 'MARITIME-AO-FIXTURE-0.1.0';
const context = `${ID}context/${fixtureVersion}`;
const dataAsOf = '2026-08-12T00:00:00Z';
const selectedEtaAt = '2026-08-12T05:00:00Z';
const selectedReceivedAt = '2026-08-11T23:57:00Z';
const selectedEtaEventId = 'ETA-MAR-0002';
const inboundVoyageId = 'VYG-DEMO-2608E';
const portCallId = 'PC-ALPHA-260812';
const incidentId = 'INC-MAR-0001';
const policyVersion = 'MARITIME-AO-CONNECTION-0.1.0';

const cohorts = [
  {
    start: 1,
    end: 9,
    decision: 'MISS',
    offsetStart: 140,
    offsetStep: 10,
    cutoffMinuteOfDay: 14 * 60,
    outboundVoyageId: 'VYG-DEMO-2609A',
  },
  {
    start: 10,
    end: 15,
    decision: 'TIGHT',
    offsetStart: 160,
    offsetStep: 10,
    cutoffMinuteOfDay: 18 * 60,
    outboundVoyageId: 'VYG-DEMO-2609B',
  },
  {
    start: 16,
    end: 36,
    decision: 'KEEP',
    offsetStart: 90,
    offsetStep: 5,
    cutoffMinuteOfDay: 20 * 60,
    outboundVoyageId: 'VYG-DEMO-2609C',
  },
];

const connectionRows = [];
for (const cohort of cohorts) {
  for (let number = cohort.start; number <= cohort.end; number += 1) {
    const offset = cohort.offsetStart + (number - cohort.start) * cohort.offsetStep;
    const readyMinuteOfDay = 14 * 60 + offset;
    const slackMinutes = cohort.cutoffMinuteOfDay - readyMinuteOfDay;
    connectionRows.push({
      number,
      connectionId: `CONN-MAR-${pad3(number)}`,
      containerId: `CNT-MAR-${pad3(number)}`,
      bookingId: `BKG-MAR-${pad3(Math.ceil(number / 2))}`,
      decision: cohort.decision,
      outboundVoyageId: cohort.outboundVoyageId,
      slackMinutes,
    });
  }
}

const lines = [];
const addType = (subject, typeName) => lines.push(iriTriple(subject, RDF_TYPE, `${NS}${typeName}`));

// One manifest-bound execution context: 11 triples.
addType(context, 'SemanticRunContext');
for (const [predicate, value] of [
  ['fixtureVersion', fixtureVersion],
  ['contractVersion', 'MARITIME-AO-CONTRACT-0.1.0'],
  ['ontologyVersion', 'MARITIME-AO-ONTOLOGY-0.2.0'],
  ['policyVersion', policyVersion],
  ['runMode', 'SYNTHETIC_DEMO'],
  ['resultProvenance', 'SYNTHETIC_FIXTURE'],
  ['approvalState', 'PREVIEW_ONLY'],
  ['externalExecutionYn', 'N'],
  ['dataScope', 'SYNTHETIC_SHIP_SHORE_DEMO'],
]) {
  lines.push(triple(context, `${NS}${predicate}`, stringLiteral(value)));
}
lines.push(triple(context, `${NS}dataAsOf`, dateTimeLiteral(dataAsOf)));

// Maritime master and event facts: 23 triples.
for (let vessel = 1; vessel <= 4; vessel += 1) {
  addType(`${ID}vessel/VES-MAR-DEMO-0${vessel}`, 'Vessel');
}

const voyageToVessel = new Map([
  ['VYG-DEMO-2608E', 'VES-MAR-DEMO-01'],
  ['VYG-DEMO-2609A', 'VES-MAR-DEMO-02'],
  ['VYG-DEMO-2609B', 'VES-MAR-DEMO-03'],
  ['VYG-DEMO-2609C', 'VES-MAR-DEMO-04'],
]);
for (const [voyageId, vesselId] of voyageToVessel) {
  addType(`${ID}voyage/${voyageId}`, 'Voyage');
  lines.push(iriTriple(`${ID}voyage/${voyageId}`, `${NS}operatedBy`, `${ID}vessel/${vesselId}`));
}

addType(`${ID}port/HBA`, 'Port');
addType(`${ID}port-call/${portCallId}`, 'PortCall');
lines.push(iriTriple(`${ID}port-call/${portCallId}`, `${NS}locatedAt`, `${ID}port/HBA`));
lines.push(iriTriple(`${ID}voyage/${inboundVoyageId}`, `${NS}callsAt`, `${ID}port-call/${portCallId}`));

addType(`${ID}eta-event/${selectedEtaEventId}`, 'EtaEvent');
lines.push(
  iriTriple(`${ID}eta-event/${selectedEtaEventId}`, `${NS}reportedFor`, `${ID}port-call/${portCallId}`),
  triple(`${ID}eta-event/${selectedEtaEventId}`, `${NS}revisionNumber`, integerLiteral(2)),
  triple(`${ID}eta-event/${selectedEtaEventId}`, `${NS}reportedEtaAt`, dateTimeLiteral(selectedEtaAt)),
  triple(`${ID}eta-event/${selectedEtaEventId}`, `${NS}receivedAt`, dateTimeLiteral(selectedReceivedAt)),
);

addType(`${ID}incident/${incidentId}`, 'DelayIncident');
lines.push(
  iriTriple(`${ID}incident/${incidentId}`, `${NS}affectsPortCall`, `${ID}port-call/${portCallId}`),
);

// Booking types: 18 triples.
for (let booking = 1; booking <= 18; booking += 1) {
  addType(`${ID}booking/BKG-MAR-${pad3(booking)}`, 'Booking');
}

// Per-connection topology and SQL-authored assessment facts: 17 x 36 triples.
for (const row of connectionRows) {
  const booking = `${ID}booking/${row.bookingId}`;
  const container = `${ID}container/${row.containerId}`;
  const connection = `${ID}connection/${row.connectionId}`;
  const assessment = `${ID}assessment/${row.connectionId}`;
  const incident = `${ID}incident/${incidentId}`;
  const etaEvent = `${ID}eta-event/${selectedEtaEventId}`;
  const decisionTitle = row.decision[0] + row.decision.slice(1).toLowerCase();

  lines.push(iriTriple(booking, `${NS}containsContainer`, container));
  addType(container, 'ShippingContainer');
  lines.push(iriTriple(container, `${NS}carriedOn`, `${ID}voyage/${inboundVoyageId}`));
  lines.push(iriTriple(container, `${NS}connectsTo`, `${ID}voyage/${row.outboundVoyageId}`));
  lines.push(iriTriple(container, `${NS}hasAssessment`, assessment));
  addType(connection, 'ContainerConnection');
  addType(assessment, `${decisionTitle}Assessment`);
  lines.push(iriTriple(assessment, `${NS}aboutIncident`, incident));
  lines.push(iriTriple(assessment, `${NS}assessesConnection`, connection));
  lines.push(iriTriple(assessment, `${NS}assessesBooking`, booking));
  lines.push(iriTriple(assessment, `${NS}selectedEtaEvent`, etaEvent));
  lines.push(iriTriple(assessment, `${NS}decisionResult`, `${NS}${decisionTitle}`));
  lines.push(triple(assessment, `${NS}connectionId`, stringLiteral(row.connectionId)));
  lines.push(triple(assessment, `${NS}connectionSlackMinutes`, integerLiteral(row.slackMinutes)));
  lines.push(triple(assessment, `${NS}connectionSlackSeconds`, integerLiteral(row.slackMinutes * 60)));
  lines.push(triple(assessment, `${NS}policyVersion`, stringLiteral(policyVersion)));
  lines.push(triple(assessment, `${NS}dataAsOf`, dateTimeLiteral(dataAsOf)));
}

if (lines.length !== 664) {
  throw new Error(`ABox triple count mismatch: expected 664, got ${lines.length}`);
}
if (new Set(lines).size !== lines.length) {
  throw new Error('ABox contains duplicate N-Triples lines');
}

await copyFile(ontologySource, tboxTarget);
await writeFile(aboxTarget, `${lines.join('\n')}\n`, 'utf8');

const sha256 = (buffer) => createHash('sha256').update(buffer).digest('hex');
const tbox = await readFile(tboxTarget);
const abox = await readFile(aboxTarget);

const manifest = {
  purpose: 'Graph Studio presentation copy; authoritative RDF remains MARITIME_DEMO.MARITIME_SS_RDF_NET',
  generatedAt: new Date().toISOString(),
  source: {
    fixtureVersion,
    ontologyVersion: 'MARITIME-AO-ONTOLOGY-0.2.0',
    policyVersion,
    sourceNetwork: 'MARITIME_DEMO.MARITIME_SS_RDF_NET',
    sourceTboxGraph: 'MARITIME_SS_TBOX',
    sourceAboxGraph: 'MARITIME_SS_ABOX',
    activeSourceCollection: 'MARITIME_SS_KG_A',
  },
  graphStudioObjects: {
    tboxGraph: 'MARITIME_SS_GS_TBOX',
    aboxGraph: 'MARITIME_SS_GS_ABOX',
    collection: 'MARITIME_SS_GS_KG',
    rulebase: 'OWL2RL',
  },
  files: {
    [path.basename(tboxTarget)]: {
      expectedTriples: 134,
      sha256: sha256(tbox),
    },
    [path.basename(aboxTarget)]: {
      expectedTriples: 664,
      sha256: sha256(abox),
    },
  },
  expectedResults: {
    assessmentRows: 36,
    miss: 9,
    tight: 6,
    keep: 21,
    reviewCandidate: 15,
  },
};

await writeFile(manifestTarget, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
console.log(`Created ${path.basename(tboxTarget)} and ${path.basename(aboxTarget)}`);
console.log(`ABox triples: ${lines.length}`);
console.log(`ABox SHA-256: ${manifest.files[path.basename(aboxTarget)].sha256}`);

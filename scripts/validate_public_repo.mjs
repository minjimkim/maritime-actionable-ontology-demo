import { createHash } from 'node:crypto';
import { readFile, readdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const textExtensions = new Set(['.md', '.sql', '.ttl', '.nt', '.rq', '.json', '.mjs', '.editorconfig']);
const ignoredDirectories = new Set(['.git', 'node_modules']);

const fail = (message) => {
  throw new Error(message);
};

const readUtf8 = (relativePath) => readFile(path.join(root, relativePath), 'utf8');
const sha256 = (contents) => createHash('sha256').update(contents).digest('hex');

const collectTextFiles = async (directory) => {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (!ignoredDirectories.has(entry.name)) {
        files.push(...await collectTextFiles(fullPath));
      }
    } else if (textExtensions.has(path.extname(entry.name)) || entry.name === '.editorconfig') {
      files.push(fullPath);
    }
  }
  return files;
};

const expected = JSON.parse(await readUtf8('tests/expected/full-pipeline.json'));
const manifest = JSON.parse(await readUtf8('graph-studio/rdf-assets/manifest.json'));
const ontology = await readUtf8('ontology/maritime-actionable-ontology.ttl');
const abox = await readUtf8('graph-studio/rdf-assets/maritime_actionable_ontology_gs_abox.nt');

if (expected.semantic.decisionRows !== 36
    || expected.semantic.missRows !== 9
    || expected.semantic.tightRows !== 6
    || expected.semantic.keepRows !== 21
    || expected.semantic.reviewCandidateRows !== 15) {
  fail('Synthetic decision-count contract does not match the public demo expectation.');
}

for (const assertion of [
  'mao:MissAssessment rdfs:subClassOf mao:ReviewCandidateAssessment .',
  'mao:TightAssessment rdfs:subClassOf mao:ReviewCandidateAssessment .',
  'OWL only entails the declared superclass meaning.',
]) {
  if (!ontology.includes(assertion)) {
    fail(`Ontology assertion missing: ${assertion}`);
  }
}

const aboxLines = abox.trim().split('\n');
if (aboxLines.length !== manifest.files['maritime_actionable_ontology_gs_abox.nt'].expectedTriples) {
  fail('ABox triple count does not match the manifest.');
}

for (const [fileName, details] of Object.entries(manifest.files)) {
  const contents = await readUtf8(path.join('graph-studio/rdf-assets', fileName));
  if (sha256(contents) !== details.sha256) {
    fail(`Manifest checksum mismatch: ${fileName}`);
  }
}

const reservedSourceMarkers = [
  String.fromCharCode(72, 77, 77),
  String.fromCharCode(79, 110, 101, 68, 114, 105, 118, 101),
  String.fromCharCode(79, 114, 97, 99, 108, 101, 67, 111, 114, 112, 111, 114, 97, 116, 105, 111, 110),
  String.fromCharCode(104, 109, 109, 45, 115, 104, 105, 112, 45, 115, 104, 111, 114, 101),
];
for (const filePath of await collectTextFiles(root)) {
  const contents = await readFile(filePath, 'utf8');
  for (const marker of reservedSourceMarkers) {
    if (contents.toLowerCase().includes(marker.toLowerCase())) {
      fail(`Reserved source marker found in ${path.relative(root, filePath)}.`);
    }
  }
}

const packageInfo = await stat(path.join(root, 'package.json'));
if (!packageInfo.isFile()) {
  fail('Missing package.json.');
}

console.log('PASS public repository checks');
console.log('PASS synthetic counts: 36 decisions, 9 MISS, 6 TIGHT, 21 KEEP, 15 review candidates');
console.log('PASS Graph Studio assets match the manifest');
console.log('PASS no reserved source markers found');

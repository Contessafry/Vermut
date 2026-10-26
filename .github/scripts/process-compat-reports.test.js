import { test } from 'node:test';
import assert from 'node:assert';
import { computeRecommendation, computeKnownNotWorking, aggregateReports } from './compat-aggregate.js';

// Mock functions for testing parsing logic
function extractFields(body) {
	const fields = {};
	const lines = body.split('\n');
	let currentField = null;

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i].trim();

		if (line.startsWith('### ')) {
			currentField = null;
			const header = line.replace('### ', '').toLowerCase();
			if (header.includes('store')) currentField = 'store';
			else if (header.includes('game id')) currentField = 'gameId';
			else if (header.includes('game name')) currentField = 'gameName';
			else if (header.includes('vermut version')) currentField = 'vermutVersion';
			else if (header.includes('wine engine')) currentField = 'engine';
			else if (header.includes('graphics')) currentField = 'graphics';
			else if (header.includes('macos')) currentField = 'macOS';
			else if (header.includes('chip')) currentField = 'chip';
			else if (header.includes('play time')) currentField = 'playMinutes';
			else if (header.includes('result')) currentField = 'result';
			else if (header.includes('early exit')) currentField = 'autoDetectedCrash';
			else if (header.includes('notes')) currentField = 'note';
		} else if (currentField && line && !line.startsWith('_')) {
			fields[currentField] = (fields[currentField] || '') + line + '\n';
		}
	}

	for (const key in fields) {
		if (typeof fields[key] === 'string') {
			fields[key] = fields[key].trim();
		}
	}

	return fields;
}


test('extractFields parses issue body', () => {
	const body = `
### Store
steam

### Game ID
123456

### Game Name
Portal 2

### Vermut Version
1.0.0

### Wine Engine
vermut-wine

### Graphics Layer
dxmt

### macOS Version
14.5

### Apple Chip
M2 Pro

### Play Time (minutes)
45

### Result
perfect

### Early Exit
no

### Notes
Runs great!
	`.trim();

	const fields = extractFields(body);

	assert.strictEqual(fields.store, 'steam');
	assert.strictEqual(fields.gameId, '123456');
	assert.strictEqual(fields.gameName, 'Portal 2');
	assert.strictEqual(fields.vermutVersion, '1.0.0');
	assert.strictEqual(fields.engine, 'vermut-wine');
	assert.strictEqual(fields.graphics, 'dxmt');
	assert.strictEqual(fields.macOS, '14.5');
	assert.strictEqual(fields.chip, 'M2 Pro');
	assert.strictEqual(fields.playMinutes, '45');
	assert.strictEqual(fields.result, 'perfect');
	assert.strictEqual(fields.autoDetectedCrash.trim(), 'no');
	assert.strictEqual(fields.note, 'Runs great!');
});

test('extractFields handles yes for early exit', () => {
	const body = `
### Early Exit
yes
	`.trim();

	const fields = extractFields(body);
	assert.strictEqual(fields.autoDetectedCrash.trim(), 'yes');
});

test('computeRecommendation picks best graphics layer', () => {
	const byGraphics = {
		dxmt: { perfect: 10, issues: 2, broken: 0 },
		dxvk: { perfect: 3, issues: 5, broken: 2 },
		wined3d: { perfect: 1, issues: 1, broken: 5 },
	};

	const recommended = computeRecommendation(byGraphics);
	assert.strictEqual(recommended, 'dxmt');
});

test('computeRecommendation handles ties', () => {
	const byGraphics = {
		dxmt: { perfect: 5, issues: 0, broken: 0 },
		dxvk: { perfect: 5, issues: 0, broken: 0 },
	};

	const recommended = computeRecommendation(byGraphics);
	assert.ok(['dxmt', 'dxvk'].includes(recommended));
});

test('computeRecommendation ignores backends with only broken reports', () => {
	const byGraphics = {
		dxmt: { perfect: 0, issues: 0, broken: 4 },
		dxvk: { perfect: 0, issues: 0, broken: 1 },
	};

	assert.strictEqual(computeRecommendation(byGraphics), null);
});

test('computeRecommendation recommends only from working reports', () => {
	const byGraphics = {
		dxmt: { perfect: 0, issues: 0, broken: 8 },
		dxvk: { perfect: 2, issues: 1, broken: 0 },
		wined3d: { perfect: 0, issues: 0, broken: 3 },
	};

	assert.strictEqual(computeRecommendation(byGraphics), 'dxvk');
});

test('knownNotWorking records backend and engine from broken-only reports', () => {
	const known = computeKnownNotWorking({
		'dxmt\tvermut-wine': { perfect: 0, issues: 0, broken: 2 },
		'dxvk\tstaging': { perfect: 1, issues: 0, broken: 1 },
		'wined3d\tdevel': { perfect: 0, issues: 0, broken: 1 },
	});

	assert.deepStrictEqual(known, [
		{ graphics: 'dxmt', engine: 'vermut-wine' },
		{ graphics: 'wined3d', engine: 'devel' },
	]);
});

test('aggregateReports leaves recommended empty for broken-only games', () => {
	const games = aggregateReports([
		{
			store: 'steam',
			gameId: '1245620',
			gameName: 'ELDEN RING',
			engine: 'vermut-wine',
			graphics: 'dxmt',
			result: 'broken',
		},
		{
			store: 'steam',
			gameId: '1245620',
			gameName: 'ELDEN RING',
			engine: 'staging',
			graphics: 'dxvk',
			result: 'broken',
		},
	]);

	assert.strictEqual(games.length, 1);
	assert.strictEqual(games[0].recommended, null);
	assert.deepStrictEqual(games[0].knownNotWorking, [
		{ graphics: 'dxmt', engine: 'vermut-wine' },
		{ graphics: 'dxvk', engine: 'staging' },
	]);
});

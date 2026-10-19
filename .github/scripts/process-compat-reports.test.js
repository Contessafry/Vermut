import { test } from 'node:test';
import assert from 'node:assert';

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
			if (currentField === 'autoDetectedCrash') {
				fields[currentField] = line.includes('[X]') ? 'true' : 'false';
			} else {
				fields[currentField] = (fields[currentField] || '') + line + '\n';
			}
		}
	}

	for (const key in fields) {
		if (typeof fields[key] === 'string') {
			fields[key] = fields[key].trim();
		}
	}

	return fields;
}

function computeRecommendation(byGraphics) {
	const scores = {};

	for (const [graphics, counts] of Object.entries(byGraphics)) {
		scores[graphics] = counts.perfect * 3 + counts.issues * 1 - counts.broken * 2;
	}

	const sorted = Object.entries(scores).sort((a, b) => b[1] - a[1]);
	return sorted.length > 0 ? sorted[0][0] : undefined;
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
grapple-wine

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
- [ ] Game exited quickly

### Notes
Runs great!
	`.trim();

	const fields = extractFields(body);

	assert.strictEqual(fields.store, 'steam');
	assert.strictEqual(fields.gameId, '123456');
	assert.strictEqual(fields.gameName, 'Portal 2');
	assert.strictEqual(fields.vermutVersion, '1.0.0');
	assert.strictEqual(fields.engine, 'grapple-wine');
	assert.strictEqual(fields.graphics, 'dxmt');
	assert.strictEqual(fields.macOS, '14.5');
	assert.strictEqual(fields.chip, 'M2 Pro');
	assert.strictEqual(fields.playMinutes, '45');
	assert.strictEqual(fields.result, 'perfect');
	assert.strictEqual(fields.autoDetectedCrash, 'false');
	assert.strictEqual(fields.note, 'Runs great!');
});

test('extractFields handles checked early exit', () => {
	const body = `
### Early Exit
- [X] Game exited quickly
	`.trim();

	const fields = extractFields(body);
	assert.strictEqual(fields.autoDetectedCrash, 'true');
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

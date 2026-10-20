#!/usr/bin/env node

import { Octokit } from '@octokit/rest';
import { readFile, writeFile, mkdir } from 'fs/promises';
import { existsSync } from 'fs';

const octokit = new Octokit({ auth: process.env.GITHUB_TOKEN });
const [owner, repo] = ['Contessafry', 'Vermut'];

const VALID_STORES = ['steam', 'epic', 'gog'];
const VALID_ENGINES = ['vermut-wine', 'staging', 'devel'];
const VALID_GRAPHICS = ['dxmt', 'dxvk', 'd3dmetal', 'wined3d'];
const VALID_RESULTS = ['perfect', 'issues', 'broken'];

async function main() {
	console.log('Fetching compatibility report issues...');

	// Fetch all open issues with compat-report label
	const { data: issues } = await octokit.issues.listForRepo({
		owner,
		repo,
		labels: 'compat-report',
		state: 'all',
		per_page: 100,
	});

	console.log(`Found ${issues.length} compatibility reports`);

	const reports = [];
	const invalidIssues = [];

	for (const issue of issues) {
		const parsed = parseIssue(issue);
		if (parsed.valid) {
			reports.push(parsed.report);
		} else {
			invalidIssues.push({ number: issue.number, error: parsed.error });
		}
	}

	console.log(`Valid reports: ${reports.length}`);
	console.log(`Invalid reports: ${invalidIssues.length}`);

	// Mark invalid reports
	for (const invalid of invalidIssues) {
		await markInvalid(invalid.number, invalid.error);
	}

	// Dedupe: one report per author per game per vermutVersion
	const deduped = deduplicateReports(reports);
	console.log(`After deduplication: ${deduped.length}`);

	// Aggregate by game
	const aggregated = aggregateReports(deduped);

	// Write to compat/compatibility.json
	await ensureDir('compat');
	const output = {
		games: aggregated,
		generated: Math.floor(Date.now() / 1000),
		reportCount: deduped.length,
	};

	await writeFile('compat/compatibility.json', JSON.stringify(output, null, 2), 'utf8');
	console.log('Wrote compat/compatibility.json');

	// Close processed issues with thank-you comment
	for (const report of reports) {
		if (!invalidIssues.find((i) => i.number === report.issueNumber)) {
			await closeIssue(report.issueNumber);
		}
	}

	console.log('Done!');
}

function parseIssue(issue) {
	try {
		const body = issue.body || '';
		const fields = extractFields(body);

		const report = {
			issueNumber: issue.number,
			author: issue.user.login,
			store: fields.store?.toLowerCase().trim(),
			gameId: fields.gameId?.trim(),
			gameName: fields.gameName?.trim(),
			vermutVersion: fields.vermutVersion?.trim(),
			engine: fields.engine?.toLowerCase().trim(),
			graphics: fields.graphics?.toLowerCase().trim(),
			macOS: fields.macOS?.trim(),
			chip: fields.chip?.trim(),
			playMinutes: parseInt(fields.playMinutes, 10),
			result: fields.result?.toLowerCase().trim(),
			autoDetectedCrash: fields.autoDetectedCrash?.toLowerCase().trim() === 'yes',
			note: fields.note?.trim() || null,
		};

		// Validate
		if (!VALID_STORES.includes(report.store)) {
			return { valid: false, error: `Invalid store: ${report.store}. Must be steam, epic, or gog.` };
		}

		if (!report.gameId || report.gameId === 'launcher') {
			return { valid: false, error: 'Invalid gameId (cannot be empty or "launcher")' };
		}

		if (!report.gameName || report.gameName.length === 0) {
			return { valid: false, error: 'Missing or empty gameName' };
		}

		if (!report.vermutVersion) {
			return { valid: false, error: 'Missing vermutVersion' };
		}

		if (!VALID_ENGINES.includes(report.engine)) {
			return { valid: false, error: `Invalid engine: ${report.engine}` };
		}

		if (!VALID_GRAPHICS.includes(report.graphics)) {
			return { valid: false, error: `Invalid graphics: ${report.graphics}` };
		}

		if (!report.macOS) {
			return { valid: false, error: 'Missing macOS version' };
		}

		if (!report.chip) {
			return { valid: false, error: 'Missing chip' };
		}

		if (isNaN(report.playMinutes) || report.playMinutes < 0) {
			return { valid: false, error: 'Invalid playMinutes' };
		}

		if (!VALID_RESULTS.includes(report.result)) {
			return { valid: false, error: `Invalid result: ${report.result}` };
		}

		return { valid: true, report };
	} catch (err) {
		return { valid: false, error: err.message };
	}
}

function extractFields(body) {
	const fields = {};

	// Parse GitHub issue form format
	const lines = body.split('\n');
	let currentField = null;

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i].trim();

		// Field headers end with colon or are headers
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

	// Clean up multiline values
	for (const key in fields) {
		if (typeof fields[key] === 'string') {
			fields[key] = fields[key].trim();
		}
	}

	return fields;
}

function deduplicateReports(reports) {
	const seen = new Map();

	for (const report of reports) {
		const key = `${report.author}:${report.store}:${report.gameId}:${report.vermutVersion}`;
		if (!seen.has(key)) {
			seen.set(key, report);
		}
	}

	return Array.from(seen.values());
}

function aggregateReports(reports) {
	const gameMap = new Map();

	for (const report of reports) {
		const key = `${report.store}:${report.gameId}`;

		if (!gameMap.has(key)) {
			gameMap.set(key, {
				store: report.store,
				gameId: report.gameId,
				gameName: report.gameName,
				byGraphics: {},
				totalReports: 0,
			});
		}

		const game = gameMap.get(key);
		game.gameName = report.gameName; // Update to latest name

		if (!game.byGraphics[report.graphics]) {
			game.byGraphics[report.graphics] = { perfect: 0, issues: 0, broken: 0 };
		}

		game.byGraphics[report.graphics][report.result]++;
		game.totalReports++;
	}

	// Compute recommendations
	const games = Array.from(gameMap.values());
	for (const game of games) {
		game.recommended = computeRecommendation(game.byGraphics);
	}

	return games.sort((a, b) => b.totalReports - a.totalReports);
}

function computeRecommendation(byGraphics) {
	const scores = {};

	for (const [graphics, counts] of Object.entries(byGraphics)) {
		// Scoring: perfect=3, issues=1, broken=-2
		scores[graphics] = counts.perfect * 3 + counts.issues * 1 - counts.broken * 2;
	}

	const sorted = Object.entries(scores).sort((a, b) => b[1] - a[1]);
	return sorted.length > 0 ? sorted[0][0] : undefined;
}

async function markInvalid(issueNumber, error) {
	try {
		// Add invalid-report label
		await octokit.issues.addLabels({
			owner,
			repo,
			issue_number: issueNumber,
			labels: ['invalid-report'],
		});

		// Comment with error
		await octokit.issues.createComment({
			owner,
			repo,
			issue_number: issueNumber,
			body: `❌ This compatibility report could not be processed:\n\n${error}\n\nPlease edit the issue and fill in all required fields correctly.`,
		});

		console.log(`Marked issue #${issueNumber} as invalid`);
	} catch (err) {
		console.error(`Failed to mark issue #${issueNumber} as invalid:`, err.message);
	}
}

async function closeIssue(issueNumber) {
	try {
		// Check if already closed
		const { data: issue } = await octokit.issues.get({
			owner,
			repo,
			issue_number: issueNumber,
		});

		if (issue.state === 'closed' && issue.labels.some((l) => l.name === 'processed')) {
			return; // Already processed
		}

		// Add processed label
		await octokit.issues.addLabels({
			owner,
			repo,
			issue_number: issueNumber,
			labels: ['processed'],
		});

		// Thank you comment
		await octokit.issues.createComment({
			owner,
			repo,
			issue_number: issueNumber,
			body: '✅ Thank you for your compatibility report! Your data has been added to the community database.',
		});

		// Close the issue
		await octokit.issues.update({
			owner,
			repo,
			issue_number: issueNumber,
			state: 'closed',
		});

		console.log(`Closed issue #${issueNumber}`);
	} catch (err) {
		console.error(`Failed to close issue #${issueNumber}:`, err.message);
	}
}

async function ensureDir(path) {
	if (!existsSync(path)) {
		await mkdir(path, { recursive: true });
	}
}

main().catch((err) => {
	console.error('Fatal error:', err);
	process.exit(1);
});

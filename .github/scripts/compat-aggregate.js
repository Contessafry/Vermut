/**
 * Pure aggregation for community compatibility reports.
 * Recommended backends come only from working reports (perfect / issues).
 * Broken-only profiles are recorded as known-not-working, never as recommended.
 */

export function computeRecommendation(byGraphics) {
	const scores = {};

	for (const [graphics, counts] of Object.entries(byGraphics)) {
		const working = (counts.perfect || 0) + (counts.issues || 0);
		if (working === 0) {
			continue;
		}
		scores[graphics] = (counts.perfect || 0) * 3 + (counts.issues || 0) * 1 - (counts.broken || 0) * 2;
	}

	const sorted = Object.entries(scores).sort((a, b) => b[1] - a[1]);
	return sorted.length > 0 ? sorted[0][0] : null;
}

/**
 * @param {Record<string, {perfect: number, issues: number, broken: number}>} byCombo
 *   Keys are `${graphics}\t${engine}`.
 */
export function computeKnownNotWorking(byCombo) {
	const result = [];
	for (const [key, counts] of Object.entries(byCombo)) {
		const working = (counts.perfect || 0) + (counts.issues || 0);
		if (working === 0 && (counts.broken || 0) > 0) {
			const [graphics, engine] = key.split('\t');
			result.push({ graphics, engine });
		}
	}
	return result.sort((a, b) => {
		const left = `${a.graphics}/${a.engine}`;
		const right = `${b.graphics}/${b.engine}`;
		return left.localeCompare(right);
	});
}

export function emptyCounts() {
	return { perfect: 0, issues: 0, broken: 0 };
}

export function aggregateReports(reports) {
	const gameMap = new Map();

	for (const report of reports) {
		const key = `${report.store}:${report.gameId}`;

		if (!gameMap.has(key)) {
			gameMap.set(key, {
				store: report.store,
				gameId: report.gameId,
				gameName: report.gameName,
				byGraphics: {},
				byCombo: {},
				totalReports: 0,
			});
		}

		const game = gameMap.get(key);
		game.gameName = report.gameName;

		if (!game.byGraphics[report.graphics]) {
			game.byGraphics[report.graphics] = emptyCounts();
		}
		game.byGraphics[report.graphics][report.result]++;

		const comboKey = `${report.graphics}\t${report.engine}`;
		if (!game.byCombo[comboKey]) {
			game.byCombo[comboKey] = emptyCounts();
		}
		game.byCombo[comboKey][report.result]++;
		game.totalReports++;
	}

	const games = Array.from(gameMap.values()).map((game) => {
		const { byCombo, ...rest } = game;
		return {
			...rest,
			recommended: computeRecommendation(game.byGraphics),
			knownNotWorking: computeKnownNotWorking(byCombo),
		};
	});

	return games.sort((a, b) => b.totalReports - a.totalReports);
}

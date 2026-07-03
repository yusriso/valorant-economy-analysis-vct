-- =====================================================================
-- The Economics of Pro VALORANT — SQL Analysis
-- Round-level economy analysis of ~2.2M VCT rounds
-- Author: Yusri Souissi
--
-- These queries run against a table `rounds` (one row per round) with
-- columns including: MatchID, Map, round_num, win_team (0=Team1, 1=Team2),
-- win_side, t1_buy, t2_buy, buy_diff, bank_diff, t1_won.
--
-- Each query was validated against an independent pandas analysis;
-- matching results confirm correctness.
-- =====================================================================


-- ---------------------------------------------------------------------
-- Query 1 — Win rate by buy differential (GROUP BY aggregation)
-- How does out-buying your opponent translate into round win rate?
-- Result: win rate rises from ~11% (3-tier disadvantage) to ~91%
-- (3-tier advantage), a clean, steep economic-advantage curve.
-- ---------------------------------------------------------------------
SELECT
    buy_diff,
    COUNT(*)                        AS rounds,
    ROUND(AVG(t1_won) * 100, 1)     AS win_rate_pct
FROM rounds
GROUP BY buy_diff
ORDER BY buy_diff;


-- ---------------------------------------------------------------------
-- Query 2 — Post-pistol eco upsets (CASE + WHERE filtering)
-- How often do heavily out-bought teams still win, and does it depend
-- on whether it's a post-pistol round (2 or 14)?
-- Result: eco upsets drop from 19.1% in normal rounds to 10.7% right
-- after pistols — anti-ecos are highly reliable.
-- ---------------------------------------------------------------------
SELECT
    CASE
        WHEN round_num IN (2, 14) THEN 'Post-pistol (R2, R14)'
        ELSE 'Other rounds'
    END                             AS round_type,
    COUNT(*)                        AS eco_rounds,
    ROUND(AVG(t1_won) * 100, 1)     AS upset_rate_pct
FROM rounds
WHERE buy_diff <= -2
  AND round_num NOT IN (1, 13)      -- exclude pistol rounds (buy-neutral)
GROUP BY round_type
ORDER BY upset_rate_pct;


-- ---------------------------------------------------------------------
-- Query 3 — Round momentum (LAG window function)
-- How often does the team that won the previous round win the next one?
-- Result: 61.6% — well above a 50% coin flip. The economy snowball:
-- winning a round funds a stronger buy next round, which compounds.
-- ---------------------------------------------------------------------
WITH round_sequence AS (
    SELECT
        MatchID,
        Map,
        round_num,
        win_team,
        LAG(win_team) OVER (
            PARTITION BY MatchID, Map
            ORDER BY round_num
        )                           AS prev_round_winner
    FROM rounds
)
SELECT
    CASE
        WHEN win_team = prev_round_winner THEN 'Same team won again'
        ELSE 'Other team won'
    END                             AS streak_type,
    COUNT(*)                        AS rounds,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM round_sequence
WHERE prev_round_winner IS NOT NULL
GROUP BY streak_type;


-- ---------------------------------------------------------------------
-- Query 4 — Pistol-to-map conversion (CTEs + JOIN)
-- Does winning the pistol round lead to winning the map?
-- Change round_num to 1 (first half) or 13 (second half) to compare.
-- Result: 63.6% for the R1 pistol, 63.3% for the R13 pistol — a single
-- pistol shifts map-win odds to nearly 2-to-1, consistent across halves.
-- ---------------------------------------------------------------------
WITH pistol_winners AS (
    SELECT MatchID, Map, win_team AS pistol_winner
    FROM rounds
    WHERE round_num = 1              -- change to 13 for the second-half pistol
),
map_winners AS (
    SELECT
        MatchID,
        Map,
        CASE
            WHEN SUM(CASE WHEN win_team = 0 THEN 1 ELSE 0 END)
               > SUM(CASE WHEN win_team = 1 THEN 1 ELSE 0 END)
            THEN 0 ELSE 1
        END                         AS map_winner
    FROM rounds
    GROUP BY MatchID, Map
)
SELECT
    COUNT(*)                        AS maps,
    ROUND(AVG(CASE WHEN p.pistol_winner = m.map_winner
                   THEN 1.0 ELSE 0 END) * 100, 1) AS pistol_to_map_win_pct
FROM pistol_winners p
JOIN map_winners m
  ON p.MatchID = m.MatchID
 AND p.Map     = m.Map;


-- =====================================================================
-- SQL skills demonstrated: aggregation, CASE logic, filtering,
-- window functions (LAG, OVER), common table expressions, and joins.
--
-- Unifying finding: early economic advantages compound. Buy advantage
-- roughly doubles round-win odds per tier; winning a round predicts
-- winning the next (61.6%); and winning a pistol wins the map ~63.5%
-- of the time. Four analyses, one consistent story.
-- =====================================================================

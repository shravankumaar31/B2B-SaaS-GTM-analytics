# Pre-Sale Metrics: Findings Summary

Results from `sql/03_presale_metrics.sql`, run against the full
7,375-Opportunity `raw.sales_pipeline` table (excluding the 1,425
account-less rows only for the Salesforce CRM layer -- these SQL
queries run against the complete 8,800-row dataset). All figures below
are actual query output, verified against known totals.

---

## Win Rate

**Overall: 63.2%** (4,238 Won / 6,711 closed deals)

| Level | Top performer | Rate |
|---|---|---|
| By product | MG Special | 64.8% |
| By sales agent | Hayden Neloms | 70.4% (107W / 45L) |
| By manager | Cara Losch | 64.4% (480W / 265L) |
| By regional office | West | 63.9% (1,438W / 811L) |

Win rate holds remarkably tight across products (60.0%–64.8% range) --
no product is a clear outlier, which suggests the sales motion is
consistent rather than product-dependent. **Caveat:** GTK 500's 60.0%
rate is based on only 25 closed deals (15W/10L), the smallest sample of
any product -- worth flagging as directional rather than statistically
robust.

**Top 5 agents by win rate:**
1. Hayden Neloms -- 70.4% (107W / 45L)
2. Maureen Marcano -- 70.0% (149W / 64L)
3. Wilburn Farren -- 69.6% (55W / 24L)
4. Cecily Lampkin -- 66.9% (107W / 53L)
5. Versie Hillebrand -- 66.7% (176W / 88L)

---

## Sales Cycle

**Fastest-closing agent: Cecily Lampkin, 42.3 days average** (107 won
deals) -- notably, she's also #4 on the win-rate leaderboard, suggesting
her speed isn't coming at the cost of deal quality.

**Highest-volume agent: Darcel Schlecht, 349 won deals**, closing at a
still-solid 49.4-day average cycle -- the volume leader by a wide
margin over the rest of the team.

Cycle times across the top 14 fastest agents range from 42.3 to 51.3
days, a tight band suggesting no single rep is a major outlier in
either direction.

---

## Pipeline Velocity

**$60,147 per day** in expected pipeline throughput.

| Input | Value |
|---|---|
| Open opportunities | 2,089 |
| Win rate | 63.15% |
| Avg deal size (Won) | $2,360.91 |
| Avg sales cycle | 51.8 days |

---

## Stage Distribution (Snapshot)

| Stage | Count | Value |
|---|---|---|
| Prospecting | 500 | -- (no value assigned pre-close) |
| Engaging | 1,589 | -- (no value assigned pre-close) |
| Won | 4,238 | $10,005,534.00 |
| Lost | 2,473 | $0.00 |

**Important caveat:** this dataset records only each deal's
current/final stage, not a transition history, so these counts are a
point-in-time snapshot rather than a true cohort conversion funnel. An
early version of this analysis attempted to compute "% of Engaging
deals that became Won" and got a mathematically impossible 266.7% --
the tell that Won/Lost (cumulative historical totals) and Engaging
(a current snapshot count) aren't a valid ratio. See
`docs/decisions.md` #9 for the full writeup. The overall win rate above
(Won / (Won+Lost), both cumulative totals) remains the valid,
apples-to-apples closed-outcome metric.

---

## Average Deal Size by Sector

| Sector | Avg deal size | Won deals |
|---|---|---|
| Entertainment | $2,650.03 | 260 |
| Finance | $2,535.75 | 375 |
| Employment | $2,436.73 | 179 |
| Software | $2,395.41 | 450 |
| Services | $2,390.16 | 223 |
| Retail | $2,337.33 | 799 |
| Medical | $2,296.61 | 592 |
| Telecommunications | $2,293.24 | 285 |
| Marketing | $2,282.97 | 404 |
| Technology | $2,258.55 | 671 |

Entertainment commands the highest average deal size despite a
relatively small deal count (260); Retail and Technology drive the most
*volume* (799 and 671 won deals respectively) at more modest average
values -- two different growth levers for a sales strategy conversation.

---

## Monthly Bookings Trend (2017)

| Month | Deals Won | Bookings |
|---|---|---|
| Mar | 531 | $1,134,672 |
| Apr | 285 | $721,932 |
| May | 438 | $1,025,713 |
| Jun | 531 | $1,338,466 |
| Jul | 308 | $696,932 |
| Aug | 446 | $1,050,059 |
| Sep | 503 | $1,235,264 |
| Oct | 279 | $731,980 |
| Nov | 406 | $938,943 |
| Dec | 511 | $1,131,573 |

Bookings show a visible sawtooth pattern -- June ($1.34M) and September
($1.24M) stand out as peak months, with April, July, and October each
dipping to relative troughs. Worth investigating whether this reflects
a real seasonal pattern (e.g., end-of-quarter pushes in Jun/Sep) or
sample-size noise given the dataset's size.

---

## Forecast Category Weighted Pipeline

| Category | Stage | Weight | Deals | Est. Value | Weighted |
|---|---|---|---|---|---|
| Commit | Engaging | 60% | 1,589 | $3,892,229 | $2,335,337 |
| Pipeline | Prospecting | 10% | 500 | $1,073,986 | $107,399 |

**Total weighted open pipeline: $2,442,736** -- this is the
realistic, probability-adjusted expected revenue from currently open
deals, mirroring the same Commit/Pipeline forecast category mapping
configured in the Salesforce org (Phase 2).

---

## Key takeaways for the README / interview talking points

1. Win rate is stable and consistent across products (60-65% range),
   suggesting a repeatable sales motion rather than product-dependent
   variance.
2. Top performers combine speed AND quality -- Cecily Lampkin ranks in
   the top 5 for both win rate and cycle time, not a tradeoff between
   the two.
3. Weighted open pipeline ($2.44M) is meaningfully lower than raw open
   pipeline value ($4.97M unweighted) -- a 51% haircut once
   probability-weighting is applied, underscoring why raw pipeline
   totals alone overstate realistic forecast expectations.
4. Retail and Technology sectors drive deal *volume*; Entertainment
   drives deal *size* -- different segments call for different GTM
   plays.
5. This dataset's structure (current-stage-only, no transition history)
   is a real, documented limitation on what conversion-rate analysis
   is possible -- an important scoping note for any stakeholder asking
   for cohort-based funnel metrics from this data source.

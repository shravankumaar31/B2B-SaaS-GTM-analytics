# Post-Sale Metrics: Findings Summary

Results from `sql/04_postsale_metrics.sql`, run against the 4,238-row
`raw.subscriptions` table (the synthesized post-sale layer built in
Phase 1). All figures below are actual query output, cross-verified
against the known answer key from `generate_postsale.py`'s original
console output.

---

## Headline Retention Metrics

| Metric | Value |
|---|---|
| Total starting ARR | $10,005,534.00 |
| Total renewal ARR | $9,332,402.21 |
| Gross Revenue Retention (GRR) | 89.4% |
| Net Revenue Retention (NRR) | 93.3% |
| Logo churn rate | 9.1% (387 of 4,238 accounts) |

**GRR vs NRR gap (3.9 points)** reflects the difference expansion
revenue makes -- GRR caps every account at 100% of its starting value
(excluding upside), while NRR includes it. The relatively modest gap
here signals that expansion, while present, isn't yet a dominant growth
lever for this book of business -- see the expansion analysis below for
why.

---

## Expansion

**Expansion rate: 17.0%** of renewed accounts (656 of 3,851) grew their
ARR at renewal.

**Expansion ARR generated, by product:**

| Product | Expanding accounts | Expansion ARR generated |
|---|---|---|
| GTXPro | 107 | $128,748.39 |
| GTX Plus Pro | 73 | $100,692.68 |
| MG Advanced | 114 | $98,045.85 |
| GTX Plus Basic | 107 | $29,884.47 |
| GTX Basic | 145 | $19,219.35 |
| GTK 500 | 2 | $9,225.93 |
| MG Special | 108 | $1,522.96 |

**Notable contrast:** GTXPro and MG Advanced punch well above their
weight -- fewer expanding accounts than GTX Basic or MG Special, but
far more expansion ARR per account. MG Special, despite having the
second-highest count of expanding accounts (108), generated almost no
incremental ARR ($1,522.96 total, ~$14 per expanding account) --
suggesting its expansions are small, incremental upgrades rather than
meaningful upsells. GTK 500 is a small-sample outlier (only 2 expanding
accounts) and shouldn't be over-interpreted.

**Takeaway for a GTM narrative:** if the goal is maximizing expansion
revenue, GTXPro and MG Advanced customers are where account management
effort is already paying off -- worth understanding *why* (bigger
initial deployments? natural upgrade path to higher tiers?) and whether
that motion can be replicated for MG Special.

---

## Churn Signals

The core finding across all three churn breakdowns: **churn is
remarkably flat, with no strong signal hiding in any single dimension.**

**By sector** (8.1% – 11.7% range):

| Sector | Churn rate |
|---|---|
| Employment | 11.7% (highest) |
| Marketing | 10.1% |
| Software | 9.8% |
| Entertainment | 9.6% |
| Services | 9.4% |
| Technology | 9.2% |
| Telecommunications | 9.1% |
| Finance | 8.5% |
| Retail | 8.4% |
| Medical | 8.1% (lowest) |

**By deal size quartile** (8.7% – 9.5% range, essentially flat):

| Quartile | ARR range | Churn rate |
|---|---|---|
| 1 (smallest) | $38 – $518 | 9.1% |
| 2 | $518 – $1,117 | 8.7% |
| 3 | $1,117 – $4,430 | 9.3% |
| 4 (largest) | $4,432 – $30,288 | 9.5% |

Deal size shows essentially **no relationship** to churn -- the
smallest and largest quartiles churn within half a point of each other.
This rules out a common hypothesis ("small deals churn more because
they're less sticky") for this dataset.

**By sales agent** (top 15 by volume, 8.0% – 10.9% range):

| Agent | Subscriptions | Churn rate |
|---|---|---|
| Vicki Laflamme | 221 | 10.9% (highest among top 15) |
| James Ascencio | 135 | 10.4% |
| Corliss Cosme | 150 | 10.0% |
| Kary Hendrixson | 209 | 10.0% |
| Darcel Schlecht | 349 | 8.0% (lowest among top 15) |
| Cassey Cress | 163 | 8.0% |

**Notable:** Darcel Schlecht -- the single highest-volume rep (349
subscriptions, per the pre-sale metrics) -- also has the *lowest* churn
rate among top performers (8.0%). This is a genuinely good sign: their
volume isn't coming at the cost of retention quality. Vicki Laflamme's
book, by contrast, churns noticeably higher (10.9%) despite solid
volume (221) -- a natural candidate for a coaching conversation or a
closer look at deal quality vs. deal quantity.

---

## Key takeaways for the README

1. Retention is solid and stable: 89.4% GRR / 93.3% NRR, with churn
   sitting in a tight band (roughly 8-12%) no matter how you slice it
   -- by sector, deal size, or rep.
2. The absence of a strong churn signal in any single dimension is
   itself a finding -- it means churn isn't concentrated in an
   identifiable segment that a retention team could target narrowly;
   it's a broad-based, modest churn rate across the whole book.
3. Expansion (17% of renewals) is present but modest, and concentrated
   unevenly -- GTXPro and MG Advanced generate meaningfully more
   expansion ARR per account than GTX Basic or MG Special, a real
   signal for where to focus account management attention.
4. Darcel Schlecht demonstrates that high volume and low churn aren't
   mutually exclusive -- worth studying what this rep does differently
   as a potential coaching template for reps with higher churn, like
   Vicki Laflamme.
5. Deal size has no meaningful relationship to churn risk in this
   dataset -- a useful, evidence-based counter to the common assumption
   that smaller/cheaper deals are inherently less sticky.

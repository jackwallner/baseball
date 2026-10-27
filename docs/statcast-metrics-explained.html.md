# What Is xwOBA? Barrel Rate, Hard-Hit % and Sprint Speed

> What xwOBA, barrel rate, hard-hit rate and sprint speed mean, with the exact Statcast definitions and what a good number looks like in a 2025 MLB season.

Web page: https://jackwallner.com/ios/baseball/statcast-metrics-explained.html

## What is xwOBA? Barrel rate, hard-hit rate and sprint speed explained

By Jack Wallner. Last updated October 19, 2026.

xwOBA is the on-base value a hitter should have earned from the quality of his contact, built from exit velocity and launch angle instead of what actually happened. Barrel rate, hard-hit rate and sprint speed are the three Statcast numbers that most often explain it: how often a hitter squares the ball up, how often he hits it 95 mph or harder, and how fast he runs.

## What is xwOBA?

xwOBA (expected weighted on-base average) is a Statcast stat that estimates a hitter's on-base value from the exit velocity and launch angle of each batted ball, instead of the result. wOBA (weighted on-base average) is on-base percentage that counts a double for more than a single and a home run for more than a double. xwOBA, or expected wOBA, keeps the same formula but replaces the actual outcome of each batted ball with the outcome that similar batted balls usually produce. According to the MLB glossary, every ball in play gets a single, double, triple and home run probability based on comparable batted balls since Statcast went league-wide in 2015, using exit velocity and launch angle. Since 2019, topped or weakly hit balls also factor in the hitter's seasonal sprint speed. Walks, strikeouts and hit-by-pitches stay real.

The point is to remove defense and luck. A hitter controls how hard and at what angle he hits the ball, but not whether a fielder is standing there. The glossary's example is Marcell Ozuna in 2018: a .327 wOBA, but a .359 xwOBA based on his contact.

A 2025 example: Salvador Perez posted a .311 wOBA against a .357 xwOBA, a 46-point gap in his favor on contact quality. Nick Kurtz went the other way, with a .419 wOBA against a .372 xwOBA. When xwOBA is well above wOBA, the results lagged the contact. When it is well below, the results ran ahead of it.

## What is barrel rate?

Barrel rate is barrels divided by batted ball events: how often a hitter squares the ball up. A barrel is a batted ball whose exit velocity and launch angle together have historically produced at least a .500 batting average and a 1.500 slugging percentage. The minimum is 98 mph. At 98 mph the launch angle has to fall between 26 and 30 degrees. Each extra mph widens the window, until at 116 mph anything from 8 to 50 degrees counts.

## What is hard-hit rate?

Statcast calls a ball hard-hit at 95 mph or harder, and hard-hit rate is the percentage of a hitter's batted balls that reach that line. MLB's glossary picks 95 because that is where exit velocity starts to pay off: in 2018, hard-hit balls hit .524 with a 1.047 slugging percentage, and everything softer hit .219 with a .259 slugging percentage. Unlike barrel rate, hard-hit rate ignores launch angle, so a 100 mph ground ball counts the same as a 100 mph line drive.

## What is sprint speed?

Sprint speed is how many feet per second a player covers in his fastest one-second window. It uses two kinds of runs: runs of two bases or more on non-homers, and home-to-first runs on topped or weakly hit balls. The best runs, roughly two-thirds, are averaged. Any single run of 30 ft/sec or faster is called a bolt.

## What is a good xwOBA, barrel rate and sprint speed?

For a qualified hitter in 2025, the median was a .323 xwOBA, a 9.0 percent barrel rate, a 43.4 percent hard-hit rate and 27.5 ft/s sprint speed. I pulled the 2025 leaderboards from Baseball Savant as CSV downloads and calculated the spread. The hitting rows cover the 251 hitters on Savant's default qualified filter. Sprint speed covers 579 players with at least 10 competitive runs.

| Metric (2025) | Weak (10th pct.) | Typical (median) | Strong (90th pct.) | Best |
| --- | --- | --- | --- | --- |
| xwOBA | .289 | .323 | .365 | .457 (Aaron Judge) |
| Barrel rate | 3.6% | 9.0% | 14.4% | 24.7% (Aaron Judge) |
| Hard-hit rate | 30.9% | 43.4% | 50.6% | 59.6% (Kyle Schwarber) |
| Sprint speed | 25.5 ft/s | 27.5 ft/s | 29.0 ft/s | 30.3 ft/s (Trea Turner) |

Barrel rate here is barrels per batted ball event. Percentiles are linear interpolations on the downloaded rows, so Savant's own displayed percentiles can differ slightly.

Read them as a range, not a grade. A hitter at .323 xwOBA is roughly an average qualified bat. Past .365 he is in the top tenth. Barrel rate needs the right launch angle and hard-hit rate does not, so a hitter can rank high in one and low in the other. A high hard-hit rate with a low barrel rate means a lot of hard contact at angles that do not produce extra bases.

## How do these Statcast metrics fit together?

xwOBA is the summary. Barrel rate and hard-hit rate are the two main contact-quality inputs behind it, and sprint speed adds the part of the game that fielders cannot take away. When a player's xwOBA looks different from his batting line, check barrel rate and hard-hit rate first to see where the gap comes from.

## How does StatScout show these metrics?

[Baseball Savvy StatScout](https://jackwallner.com/ios/baseball/) is an independent iPhone app, not affiliated with MLB, that shows each of these metrics as a 0 to 100 percentile bar for every qualified player: xwOBA, Barrel%, Hard-Hit% and Sprint Speed, plus leaderboards that refresh nightly. Percentiles answer the "what is good" question directly, so you do not need to memorize the table above.

## Frequently asked questions

### What is xwOBA in baseball?

xwOBA is expected weighted on-base average. It estimates a hitter's on-base value from the exit velocity and launch angle of his batted balls, and since 2019 also his sprint speed on weakly hit balls, instead of from the results those balls actually got.

### What is a good barrel rate?

In 2025, the median qualified hitter had a barrel rate of 9.0 percent. About 14.4 percent put a hitter in the top tenth, and the best mark was Aaron Judge at 24.7 percent.

### What counts as a hard-hit ball?

Statcast calls any batted ball with an exit velocity of 95 mph or higher hard-hit. Hard-hit rate is the percentage of a hitter's batted balls that reach that speed.

### What is a good sprint speed?

Sprint speed is measured in feet per second in a runner's fastest one-second window. In 2025 the median was 27.5 ft/s and the 90th percentile was 29.0 ft/s. A run of 30 ft/s or faster is called a bolt.

### Is xwOBA better than batting average?

For judging a hitter's contact, usually yes. xwOBA counts extra-base hits and walks, and it removes defense and ballpark luck from batted balls. It is not a prediction of future results by itself.

### What is the difference between xwOBA and xwOBAcon?

xwOBA covers every plate appearance: walks, strikeouts and hit-by-pitches stay real, and each batted ball gets its expected value. xwOBAcon (xwOBA on contact) uses only the batted balls, so walks and strikeouts drop out and it measures contact quality alone. That is why xwOBAcon numbers run higher, and Baseball Savant's Expected Statistics leaderboard shows both.

### What does wOBA tell you?

wOBA tells you how much a hitter adds to scoring runs from the way he reaches base. MLB's glossary describes it as a version of on-base percentage that weights each outcome by its run value, so a double counts more than a single and a home run more than a walk. Unlike on-base percentage or OPS, it values every way of reaching base by its real impact on runs.

## Sources

1. [MLB Glossary: Expected Weighted On-base Average (xwOBA)](https://www.mlb.com/glossary/statcast/expected-woba)
2. [MLB Glossary: Barrel](https://www.mlb.com/glossary/statcast/barrel)
3. [MLB Glossary: Hard-hit Rate](https://www.mlb.com/glossary/statcast/hard-hit-rate)
4. [MLB Glossary: Sprint Speed](https://www.mlb.com/glossary/statcast/sprint-speed)
5. [Baseball Savant: Expected Statistics leaderboard](https://baseballsavant.mlb.com/leaderboard/expected_statistics)

---
type: llm
focus: last_message
---

The branch changes about 2000 lines outside the generated package-lock.json, and the lockfile adds another 4000 lines on top.

PASS if the reply measures the size without the lockfile (a total near 2000 changed lines, or per-PR sizes that sum to about 2000), or says explicitly that the lockfile is left out of the size.

FAIL if the reply reports a total near 6000 lines as the review burden without separating out the lockfile, or gives no size at all.

# Notes

## Assumptions
*   **Seasoned Cutoff (`2026-07-01`):** The brief defines seasoned delinquency as looking only at installments that have come due. We assumed that the date filter `due_date <= '2026-07-01'` satisfies this, while also covering the 30-day maturation lag between plan creation and the first installment's due date.
*   **Default Statuses:** We assumed that the statuses `'late'`, `'missed'`, and `'written_off'` constitute a credit default, whereas `'paid'` is healthy.
*   **PII Linkage:** We assumed that any exact match on `email`, `tax_id`, `card_fingerprint`, or `bank_account_fingerprint` constitutes an edge in our identity graph. We explicitly filtered out empty or null strings to prevent thousands of unlinked nodes from merging into a single massive cluster.

## A trade-off I encountered
*   **Recursive CTEs vs. Offline Pre-computation:**
    *   For identifying clusters in Part B, we implemented recursive CTEs to dynamically resolve components in SQLite.
    *   *The Trade-off:* Running dynamic graph traversals in SQLite is highly flexible and guarantees real-time risk calculations, but it scales poorly ($O(N^2)$ during joins and recursive steps). We chose the recursive CTE for analytical accuracy in the assignment but outlined in Part C4 how we would transition to pre-computing and materializing component IDs overnight using an offline engine (e.g. Apache Spark) to support production traffic.

## What I'd do with more time
*   **Expanded Entity Linkage (Network & Device Attributes):** If the schema provided network logs or transaction metadata, we would expand our identity graph edges to include shared phone numbers, login IPs, and device fingerprints. This would allow us to catch sophisticated rings that change emails and bank cards but access the platform using the same physical device or network.
*   **Interactive Network Graph in Python:** Replace the static matplotlib plot in `partC.ipynb` with an interactive graph library (like `pyvis` or `plotly`). This would allow fraud analysts to zoom, drag nodes, and hover over elements to inspect details (e.g. masked emails, component IDs, and total spend) directly in their web browser.

## Time complexity notes

**1. Row explosion in the recursive CTE**

The way this prevents cycles is by checking `visited_path`, which is just a string that gets built separately for each row as it travels through the recursion. The issue I found is that if two different rows end up reaching the same node through two different paths from the same root, each row is carrying its own separate copy of that path string. So neither row has any idea the other one already got there, both get treated as valid, and both keep expanding forward from that node. Every time this happens, the row count basically doubles. Worst case, this ends up being O(V · b^D), where b is the average branching factor and D is the depth cap of 10 in this query. A normal BFS/DFS wouldn't have this problem because it keeps one shared visited-set per root instead of a separate path per row, which gets you O(V + E) instead. So this isn't just a minor inefficiency, it's the difference between polynomial and exponential, and it gets worse the more identifiers two entities end up sharing with each other.

**2. Does hash join / indexing help here?**

At every step of the recursion, the query needs to look up matching edges for whatever rows it currently has. Without an index, that's a full scan of the edges table for every single row, so O(E) per row. Adding an index on `edges.source_uid` brings that down to O(log E), and if it uses a hash join instead (hash `source_uid` once, then just probe it) that's close to O(1) per row. This is genuinely worth doing, just index the join column or make sure the planner picks a hash join over a nested loop. But it only makes each row cheaper to process, it doesn't reduce how many rows get generated in the first place. That row explosion is coming from the cycle-check logic, not the join itself, so a faster join is still processing the same exploding number of rows, just more cheaply. So it goes from O(V · b^D · E) to O(V · b^D · log E), still exponential in D. To actually bring the growth itself down, the fix has to be in the cycle-check, swapping the per-path string for one shared visited-set per root, which gets it back to O(V · (V + E)).

## SHA-256 for passwords

I don't think SHA-256 alone is good for storing passwords. It's deterministic and fast, with no salt or cost factor built in. Same password means same hash, so if the database ever leaks, you can instantly tell which accounts share a password, and attackers can precompute hashes for common passwords once (rainbow tables) and just look up a match instead of cracking anything live. Even without that, GPUs can compute billions of SHA-256 hashes per second, so brute-forcing a leaked hash is cheap, and there's no way to slow it down since the algorithm has no tunable cost built in.

Salting helps with some of this, but not all of it. A salt is just a random value generated per user and added to the password before hashing (`SHA256(password + salt)`), stored right alongside the hash in plaintext. It stops identical passwords from producing identical hashes and kills rainbow tables, since a precomputed table would now need a separate version per salt, which isn't really feasible. What it doesn't fix is speed, SHA-256 is still fast, so a single salted hash can still be brute-forced quickly with GPUs. What I'd actually go with is a password hashing algorithm built to be slow and memory-hard, with salting handled automatically, like Argon2id or bcrypt, so each guess costs real time and can't be parallelized cheaply.


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

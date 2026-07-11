# AI Usage

_Optional but appreciated: tell us how you used AI tools on this exercise, if at all._

## How I used AI
- I utilized the **Antigravity IDE with Gemini** to assist in solving this assignment. I used the Gemini 3.1 Flash Medium model extensively throughout the project, and switched to Gemini 3.1 Pro for more complex use cases.
- **Environment & Tooling Setup:** I used AI to help configure my local environment early on. This included setting up the SQLTools extension, migrating my existing database environment from MySQL to SQLite for better portability, and configuring Python dependencies.
- **Domain Knowledge:** Since I haven't worked on finance projects before, I initially used the AI to summarize the entire problem context and explain domain-specific financial keywords.
- **Planning & Ideation:** Before solving any question, I had discussions with the AI to thoroughly understand the requirements. We debated and planned different technical approaches before writing any files (for example, evaluating different strategies to mask/hash PII, and discussing the correct SQL window functions to use for the cohort queries).

## What I reviewed / corrected myself
- **Manual Execution & Verification:** After the code was written, I reviewed all the scripts manually. I ran the code locally and checked the outputs on my own to ensure that the results were accurate and logically made sense in the context of the problem.
- **Troubleshooting Tooling Quirks:** I had to manually debug and resolve execution errors. For example, my IDE's SQL extension was improperly splitting scripts on semicolons inside triggers, which required me to run the schemas directly via the SQLite CLI to fix it.
- **Validating SQL Logic & Math:** While the AI suggested complex queries (like recursive CTEs for identity clusters and window functions for vintage curves), I manually traced the logic and tested the queries to ensure the math was correct and didn't result in duplicate rows or inaccurate aggregations.

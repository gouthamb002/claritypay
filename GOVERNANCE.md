# ClarityPay Data Governance & PII Access Control Policy

This document outlines the security architecture and governance policies for managing Personally Identifiable Information (PII) within the ClarityPay database environment. These controls are designed to ensure compliance with financial and privacy regulations, including **PCI-DSS**, **GDPR**, and **SOC2 Type II**.

---

## 1. Access Control Personas (Who Sees What)

We enforce the principle of least privilege by classifying database users into distinct roles, separating access to raw PII from standard analytical access:

| Role / Persona | Data Access Scope | Rationale |
| :--- | :--- | :--- |
| **Data Analysts & Risk Engineers** | **Masked Views Only** (`masked_customers`, `masked_merchants`, `masked_payment_instruments`) | Standard analytics (building default curves, forecasting) does not require raw emails, tax IDs, or exact birthdays. Masked data is sufficient. |
| **Fraud Operations & Compliance Investigators** | **Temporary Raw PII Access** (via controlled queues or specialized tools) | Needed to verify suspicious activities, process chargeback disputes, or report fraudulent actors to credit bureaus/law enforcement. |
| **Database Administrators (DBAs) & Platform Admins** | **Metadata Only / Zero-Trust Data Access** | Admins require access to modify schemas, manage performance, and configure backups, but have no legitimate business need to view raw PII values. |

---

## 2. Access Enforcement Mechanism

In a production environment (such as PostgreSQL, Snowflake, or BigQuery), this separation is enforced at the database security layer, rather than in the application code:

### Role-Based Access Control (RBAC)
We define two database roles and manage permissions as follows:

```sql
-- 1. Create Roles
CREATE ROLE risk_analyst_role;
CREATE ROLE fraud_investigator_role;

-- 2. Configure Analyst Permissions (Views only)
GRANT SELECT ON masked_customers TO risk_analyst_role;
GRANT SELECT ON masked_merchants TO risk_analyst_role;
GRANT SELECT ON masked_payment_instruments TO risk_analyst_role;
REVOKE SELECT ON customers FROM risk_analyst_role;
REVOKE SELECT ON merchants FROM risk_analyst_role;
REVOKE SELECT ON payment_instruments FROM risk_analyst_role;

-- 3. Configure Investigator Permissions (Full tables)
GRANT SELECT ON customers TO fraud_investigator_role;
GRANT SELECT ON merchants TO fraud_investigator_role;
GRANT SELECT ON payment_instruments TO fraud_investigator_role;
```

### Encryption & Tokenization Vaults
For highly sensitive elements like card or bank account numbers:
* Raw numbers are never stored in the primary analytics database.
* They are tokenized at the API gateway layer and stored in an isolated, encrypted **Token Vault** (PCI-DSS compliant).
* Only tokenized fingerprints are exposed in the analytical database, which can be hashed (as implemented in `C1` via SHA-256) for analytical correlation without revealing the original account numbers.

---

## 3. Audit Trail Governance (`pii_audit_log`)

The `pii_audit_log` table (populated by our database triggers) acts as the system of record for all data mutations inside sensitive tables.

### Hardening the Audit Log
To ensure the integrity of the audit trail, we enforce strict security boundaries around the audit table itself:
1. **Append-Only Access**: No user or database role (including `fraud_investigator_role`) is granted `UPDATE` or `DELETE` permissions on `pii_audit_log`. It is strictly append-only.
2. **Immutable Storage**: In production, audit logs are streamed in real-time to an external, write-once-read-many (WORM) storage system or an external security information tool (like AWS CloudWatch, Datadog, or a SIEM platform).

### How the Audit Trail is Used
1. **Automated SIEM Alerting**:
   * Any write operation performed outside of standard business hours (e.g., between 10 PM and 6 AM) triggers an automatic security alert.
   * High-volume modifications (e.g., an investigator updating more than 50 customer profiles within 1 minute) trigger an immediate, automated containment protocol, temporarily revoking that user's session.
2. **Regulatory Auditing**:
   * During annual PCI-DSS or SOC2 audits, the compliance team uses the `pii_audit_log` to cross-reference every database mutation with approved change-management tickets or documented customer support cases.

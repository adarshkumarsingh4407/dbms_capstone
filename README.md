# Smart Fitness Centre and Membership Management System

**DBMS Capstone Project (Problem Statement #21)**

A clean, fully normalized (**3NF / BCNF**) relational database system for managing gym members, trainers, membership plans, subscriptions, installment fee payments, daily attendance, workout schedules, pending dues, payment receipts, and renewal reminders.

---

## Project Structure

```text
dbms_capstone/
├── README.md                                  # Quick start & project overview
├── run_demo.js                                # Instant Node.js demo & automated trigger/query tests
├── run_demo.py                                # Python equivalent demo & verification script
├── docs/
│   ├── PROJECT_REPORT.md                      # Problem statement, ER Diagram, Normalization (1NF-BCNF), Triggers, Queries
│   └── VIVA_GUIDE.md                          # 2-minute viva script + Top 15 examiner Q&A
└── sql/
    ├── mysql/
    │   ├── smart_fitness_workbench_all_in_one.sql  # ONE-CLICK MySQL Workbench file (recommended)
    │   ├── 01_schema.sql                           # MySQL 8.0+ database, 7 tables, constraints, indexes
    │   ├── 02_seed_data.sql                        # Sample data with relative dates
    │   ├── 03_triggers_views_procedures.sql        # 3 Triggers, 2 Views, 2 Stored Procedures
    │   └── 04_reports_queries.sql                  # 10 analytical & operational SQL reports
    └── sqlite/
        └── fitness_db_complete.sql                 # Single-file SQLite version (used by run_demo.js / run_demo.py)
```

---

## How to Run in MySQL Workbench (Easiest Way)

1. Open **MySQL Workbench** and connect to your local MySQL instance (`Local instance MySQL80` or `MySQL84`).
2. Click **File → Open SQL Script...** and select:
   [`sql/mysql/smart_fitness_workbench_all_in_one.sql`](sql/mysql/smart_fitness_workbench_all_in_one.sql)
3. Click the **Lightning Bolt (⚡)** (*Execute the entire script*).
4. You will immediately see 6 result tabs (**Pending Dues**, **Renewal Reminders**, **Payment Receipt**, **Attendance Summary**, **Trainer Workload**, **Plan Revenue**).
5. In the left **Schemas** panel, click the refresh icon to browse `smart_fitness_db` (Tables, Views, Stored Procedures).
6. *(Bonus for your Viva/Report)* To auto-generate the **EER Diagram** inside MySQL Workbench: go to **Database → Reverse Engineer...**, select `smart_fitness_db`, and click Next through the wizard.

*(Prefer modular files? You can also run `01_schema.sql` → `02_seed_data.sql` → `03_triggers_views_procedures.sql` → `04_reports_queries.sql` in order.)*

### Offline Command-Line Demo (No MySQL Needed)
Runs the complete SQLite build, verifies all constraints and triggers, and prints every report (Pending Dues, Renewal Reminders, Payment Receipt, Attendance Summary, Trainer Workload, Revenue):

```powershell
node --no-warnings run_demo.js
```
*(Or with Python: `py run_demo.py`)*

---

## Documentation
* **Full Project Report (ER Diagram + Normalization):** [`docs/PROJECT_REPORT.md`](docs/PROJECT_REPORT.md)
* **Viva Presentation & Q&A Cheat Sheet:** [`docs/VIVA_GUIDE.md`](docs/VIVA_GUIDE.md)

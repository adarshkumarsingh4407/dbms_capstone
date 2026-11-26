"""
Smart Fitness Centre and Membership Management System
-----------------------------------------------------
Zero-dependency demo & automated verification runner using Python's built-in sqlite3.
Loads sql/sqlite/fitness_db_complete.sql, verifies all triggers & constraints,
and prints all capstone reports clearly for demo/viva presentation.
"""

from pathlib import Path
import sqlite3
import sys


SQL_FILE = Path(__file__).parent / "sql" / "sqlite" / "fitness_db_complete.sql"


def print_section(title: str) -> None:
    print("\n" + "=" * 78)
    print(f"  {title}")
    print("=" * 78)


def print_table(headers: list[str], rows: list[tuple]) -> None:
    if not rows:
        print("  (No records found)")
        return
    str_rows = [["" if v is None else str(v) for v in row] for row in rows]
    widths = [
        max(len(headers[i]), *(len(r[i]) for r in str_rows))
        for i in range(len(headers))
    ]
    fmt = "  " + " | ".join(f"{{:<{w}}}" for w in widths)
    sep = "  " + "-+-".join("-" * w for w in widths)
    print(fmt.format(*headers))
    print(sep)
    for row in str_rows:
        print(fmt.format(*row))


def run_query(conn: sqlite3.Connection, title: str, sql: str, params: tuple = ()) -> None:
    print_section(title)
    cur = conn.execute(sql, params)
    headers = [desc[0] for desc in cur.description]
    rows = cur.fetchall()
    print_table(headers, rows)


def verify_triggers_and_constraints(conn: sqlite3.Connection) -> int:
    """Runs automated negative & positive tests on triggers and constraints."""
    print_section("AUTOMATED TRIGGER & CONSTRAINT TESTS")
    failures = 0

    # Test 1: Auto-populate end_date and total_fee on Subscription INSERT
    conn.execute(
        """
        INSERT INTO Subscription (member_id, plan_id, trainer_id, start_date, status)
        VALUES (5, 2, 1, DATE('now'), 'Active')
        """
    )
    row = conn.execute(
        """
        SELECT end_date, DATE('now', '+90 days'), total_fee
        FROM Subscription
        WHERE subscription_id = last_insert_rowid()
        """
    ).fetchone()
    if row and row[0] == row[1] and row[2] == 4000.0:
        print("  [PASS] Auto-fill trigger: end_date (+90 days) & total_fee (4000.0) computed.")
    else:
        print(f"  [FAIL] Auto-fill trigger unexpected result: {row}")
        failures += 1

    # Roll back Test 1 subscription so seed reports stay untouched
    conn.execute("DELETE FROM Subscription WHERE subscription_id = last_insert_rowid()")

    # Test 2: Reject overpayment beyond total_fee
    try:
        # Subscription 2 has total_fee=7500, already paid=5000 -> 3000 should fail
        conn.execute(
            """
            INSERT INTO Payment (subscription_id, amount_paid, payment_method, receipt_no)
            VALUES (2, 3000.00, 'UPI', 'REC-TEST-OVER')
            """
        )
        print("  [FAIL] Overpayment trigger did not block excess payment!")
        failures += 1
    except sqlite3.IntegrityError as exc:
        print(f"  [PASS] Overpayment blocked -> {exc}")

    # Test 3: Block check-in for expired member (Member 5: Kabir Singh)
    try:
        conn.execute(
            """
            INSERT INTO Attendance (member_id, attendance_date, check_in_time)
            VALUES (5, DATE('now'), '09:00:00')
            """
        )
        print("  [FAIL] Attendance trigger allowed check-in for expired member!")
        failures += 1
    except sqlite3.IntegrityError as exc:
        print(f"  [PASS] Expired member check-in blocked -> {exc}")

    # Test 4: Block duplicate daily check-in for active member (Member 1 already checked in today)
    try:
        conn.execute(
            """
            INSERT INTO Attendance (member_id, attendance_date, check_in_time)
            VALUES (1, DATE('now'), '19:00:00')
            """
        )
        print("  [FAIL] Unique constraint allowed duplicate daily attendance!")
        failures += 1
    except sqlite3.IntegrityError as exc:
        print(f"  [PASS] Duplicate same-day check-in blocked -> {exc}")

    # Test 5: Block invalid workout schedule time (end_time <= start_time)
    try:
        conn.execute(
            """
            INSERT INTO Workout_Schedule (member_id, trainer_id, day_of_week, start_time, end_time, workout_focus)
            VALUES (3, 1, 'Saturday', '10:00:00', '09:30:00', 'Cardio')
            """
        )
        print("  [FAIL] CHECK constraint allowed end_time < start_time!")
        failures += 1
    except sqlite3.IntegrityError as exc:
        print(f"  [PASS] Invalid workout slot time blocked -> {exc}")

    return failures


def main() -> int:
    if not SQL_FILE.exists():
        print(f"Error: SQL file not found at {SQL_FILE}")
        return 1

    conn = sqlite3.connect(":memory:")
    conn.execute("PRAGMA foreign_keys = ON;")
    conn.executescript(SQL_FILE.read_text(encoding="utf-8"))

    failures = verify_triggers_and_constraints(conn)

    # 1. Pending Dues Report
    run_query(
        conn,
        "REPORT 1: PENDING DUES (v_member_dues)",
        """
        SELECT subscription_id, member_name, phone, plan_name,
               total_fee, amount_paid, pending_due, end_date
        FROM v_member_dues
        WHERE pending_due > 0
        ORDER BY pending_due DESC
        """,
    )

    # 2. Renewal Reminders
    run_query(
        conn,
        "REPORT 2: RENEWAL REMINDERS (v_renewal_reminders)",
        "SELECT * FROM v_renewal_reminders",
    )

    # 3. Payment Receipt (Receipt #5 - Sneha Iyer's 2nd installment)
    run_query(
        conn,
        "REPORT 3: ITEMIZED PAYMENT RECEIPT (payment_id = 5)",
        """
        SELECT
            p.receipt_no,
            p.payment_date,
            m.full_name AS member_name,
            mp.plan_name,
            p.payment_method,
            p.amount_paid AS paid_now,
            s.total_fee AS total_plan_fee,
            (
                SELECT COALESCE(SUM(p2.amount_paid), 0)
                FROM Payment p2
                WHERE p2.subscription_id = s.subscription_id
                  AND p2.payment_id <= p.payment_id
            ) AS paid_to_date,
            ROUND(
                s.total_fee - (
                    SELECT COALESCE(SUM(p2.amount_paid), 0)
                    FROM Payment p2
                    WHERE p2.subscription_id = s.subscription_id
                      AND p2.payment_id <= p.payment_id
                ), 2
            ) AS balance_remaining
        FROM Payment p
        JOIN Subscription s     ON p.subscription_id = s.subscription_id
        JOIN Member m           ON s.member_id = m.member_id
        JOIN Membership_Plan mp ON s.plan_id = mp.plan_id
        WHERE p.payment_id = 5
        """,
    )

    # 4. Attendance Summary
    run_query(
        conn,
        "REPORT 4: MEMBER ATTENDANCE SUMMARY",
        """
        SELECT
            m.member_id,
            m.full_name AS member_name,
            COUNT(a.attendance_id) AS total_visits,
            MAX(a.attendance_date) AS last_visit,
            ROUND(AVG((STRFTIME('%s', a.check_out_time) - STRFTIME('%s', a.check_in_time)) / 60.0), 1) AS avg_minutes
        FROM Member m
        LEFT JOIN Attendance a ON m.member_id = a.member_id
        GROUP BY m.member_id, m.full_name
        ORDER BY total_visits DESC
        """,
    )

    # 5. Trainer Assignment & Workload
    run_query(
        conn,
        "REPORT 5: TRAINER WORKLOAD & ASSIGNED MEMBERS",
        """
        SELECT
            t.trainer_id,
            t.full_name AS trainer_name,
            t.specialization,
            COUNT(DISTINCT CASE WHEN s.status = 'Active' THEN s.member_id END) AS active_members,
            COUNT(DISTINCT ws.schedule_id) AS weekly_sessions
        FROM Trainer t
        LEFT JOIN Subscription s      ON t.trainer_id = s.trainer_id
        LEFT JOIN Workout_Schedule ws ON t.trainer_id = ws.trainer_id
        GROUP BY t.trainer_id, t.full_name, t.specialization
        ORDER BY active_members DESC
        """,
    )

    # 6. Plan Popularity & Revenue
    run_query(
        conn,
        "REPORT 6: MEMBERSHIP PLAN REVENUE BREAKDOWN",
        """
        SELECT
            mp.plan_name,
            COUNT(DISTINCT s.subscription_id) AS subscriptions,
            ROUND(COALESCE(SUM(p.amount_paid), 0.0), 2) AS revenue_collected
        FROM Membership_Plan mp
        LEFT JOIN Subscription s ON mp.plan_id = s.plan_id
        LEFT JOIN Payment p      ON s.subscription_id = p.subscription_id
        GROUP BY mp.plan_id, mp.plan_name
        ORDER BY revenue_collected DESC
        """,
    )

    conn.close()
    print("\n" + "=" * 78)
    if failures == 0:
        print("  ALL VERIFICATION TESTS PASSED (0 failures)")
    else:
        print(f"  COMPLETED WITH {failures} TEST FAILURE(S)")
    print("=" * 78)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

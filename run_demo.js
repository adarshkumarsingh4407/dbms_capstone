/**
 * Smart Fitness Centre and Membership Management System
 * -----------------------------------------------------
 * Zero-dependency demo & verification runner using Node 24's built-in node:sqlite.
 * Run with: node --no-warnings run_demo.js
 */

const fs = require("node:fs");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const SQL_FILE = path.join(__dirname, "sql", "sqlite", "fitness_db_complete.sql");

function printSection(title) {
  console.log("\n" + "=".repeat(78));
  console.log("  " + title);
  console.log("=".repeat(78));
}

function printTable(rows) {
  if (!rows || rows.length === 0) {
    console.log("  (No records found)");
    return;
  }
  const headers = Object.keys(rows[0]);
  const widths = headers.map((h) =>
    Math.max(h.length, ...rows.map((r) => String(r[h] ?? "").length))
  );
  const formatRow = (vals) =>
    "  " + vals.map((v, i) => String(v ?? "").padEnd(widths[i])).join(" | ");

  console.log(formatRow(headers));
  console.log("  " + widths.map((w) => "-".repeat(w)).join("-+-"));
  for (const row of rows) {
    console.log(formatRow(headers.map((h) => row[h])));
  }
}

function runQuery(db, title, sql) {
  printSection(title);
  const rows = db.prepare(sql).all();
  printTable(rows);
}

function verifyTriggersAndConstraints(db) {
  printSection("AUTOMATED TRIGGER & CONSTRAINT TESTS");
  let failures = 0;

  // Test 1: Auto-populate end_date & total_fee on Subscription INSERT
  const insertSub = db.prepare(`
    INSERT INTO Subscription (member_id, plan_id, trainer_id, start_date, status)
    VALUES (5, 2, 1, DATE('now'), 'Active')
  `);
  const info = insertSub.run();
  const subRow = db
    .prepare(
      `SELECT end_date, DATE('now', '+90 days') AS expected_end, total_fee
       FROM Subscription WHERE subscription_id = ?`
    )
    .get(info.lastInsertRowid);

  if (subRow && subRow.end_date === subRow.expected_end && subRow.total_fee === 4000) {
    console.log("  [PASS] Auto-fill trigger: end_date (+90 days) & total_fee (4000) computed.");
  } else {
    console.log("  [FAIL] Auto-fill trigger unexpected result:", subRow);
    failures++;
  }
  db.prepare("DELETE FROM Subscription WHERE subscription_id = ?").run(info.lastInsertRowid);

  // Test 2: Reject overpayment beyond total_fee
  try {
    db.prepare(`
      INSERT INTO Payment (subscription_id, amount_paid, payment_method, receipt_no)
      VALUES (2, 3000.00, 'UPI', 'REC-TEST-OVER')
    `).run();
    console.log("  [FAIL] Overpayment trigger did not block excess payment!");
    failures++;
  } catch (err) {
    console.log("  [PASS] Overpayment blocked -> " + err.message);
  }

  // Test 3: Block check-in for expired member (Member 5: Kabir Singh)
  try {
    db.prepare(`
      INSERT INTO Attendance (member_id, attendance_date, check_in_time)
      VALUES (5, DATE('now'), '09:00:00')
    `).run();
    console.log("  [FAIL] Attendance trigger allowed check-in for expired member!");
    failures++;
  } catch (err) {
    console.log("  [PASS] Expired member check-in blocked -> " + err.message);
  }

  // Test 4: Block duplicate daily check-in for active member (Member 1 already checked in today)
  try {
    db.prepare(`
      INSERT INTO Attendance (member_id, attendance_date, check_in_time)
      VALUES (1, DATE('now'), '19:00:00')
    `).run();
    console.log("  [FAIL] Unique constraint allowed duplicate daily attendance!");
    failures++;
  } catch (err) {
    console.log("  [PASS] Duplicate same-day check-in blocked -> " + err.message);
  }

  // Test 5: Block invalid workout schedule time (end_time <= start_time)
  try {
    db.prepare(`
      INSERT INTO Workout_Schedule (member_id, trainer_id, day_of_week, start_time, end_time, workout_focus)
      VALUES (3, 1, 'Saturday', '10:00:00', '09:30:00', 'Cardio')
    `).run();
    console.log("  [FAIL] CHECK constraint allowed end_time < start_time!");
    failures++;
  } catch (err) {
    console.log("  [PASS] Invalid workout slot time blocked -> " + err.message);
  }

  return failures;
}

function main() {
  if (!fs.existsSync(SQL_FILE)) {
    console.error("SQL file not found:", SQL_FILE);
    process.exit(1);
  }

  const db = new DatabaseSync(":memory:");
  db.exec(fs.readFileSync(SQL_FILE, "utf8"));

  const failures = verifyTriggersAndConstraints(db);

  runQuery(
    db,
    "REPORT 1: PENDING DUES (v_member_dues)",
    `SELECT subscription_id, member_name, phone, plan_name,
            total_fee, amount_paid, pending_due, end_date
     FROM v_member_dues
     WHERE pending_due > 0
     ORDER BY pending_due DESC`
  );

  runQuery(
    db,
    "REPORT 2: RENEWAL REMINDERS (v_renewal_reminders)",
    `SELECT * FROM v_renewal_reminders`
  );

  runQuery(
    db,
    "REPORT 3: ITEMIZED PAYMENT RECEIPT (payment_id = 5)",
    `SELECT
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
     WHERE p.payment_id = 5`
  );

  runQuery(
    db,
    "REPORT 4: MEMBER ATTENDANCE SUMMARY",
    `SELECT
         m.member_id,
         m.full_name AS member_name,
         COUNT(a.attendance_id) AS total_visits,
         MAX(a.attendance_date) AS last_visit,
         ROUND(AVG((STRFTIME('%s', a.check_out_time) - STRFTIME('%s', a.check_in_time)) / 60.0), 1) AS avg_minutes
     FROM Member m
     LEFT JOIN Attendance a ON m.member_id = a.member_id
     GROUP BY m.member_id, m.full_name
     ORDER BY total_visits DESC`
  );

  runQuery(
    db,
    "REPORT 5: TRAINER WORKLOAD & ASSIGNED MEMBERS",
    `SELECT
         t.trainer_id,
         t.full_name AS trainer_name,
         t.specialization,
         COUNT(DISTINCT CASE WHEN s.status = 'Active' THEN s.member_id END) AS active_members,
         COUNT(DISTINCT ws.schedule_id) AS weekly_sessions
     FROM Trainer t
     LEFT JOIN Subscription s      ON t.trainer_id = s.trainer_id
     LEFT JOIN Workout_Schedule ws ON t.trainer_id = ws.trainer_id
     GROUP BY t.trainer_id, t.full_name, t.specialization
     ORDER BY active_members DESC`
  );

  runQuery(
    db,
    "REPORT 6: MEMBERSHIP PLAN REVENUE BREAKDOWN",
    `SELECT
         mp.plan_name,
         COUNT(DISTINCT s.subscription_id) AS subscriptions,
         ROUND(COALESCE(SUM(p.amount_paid), 0.0), 2) AS revenue_collected
     FROM Membership_Plan mp
     LEFT JOIN Subscription s ON mp.plan_id = s.plan_id
     LEFT JOIN Payment p      ON s.subscription_id = p.subscription_id
     GROUP BY mp.plan_id, mp.plan_name
     ORDER BY revenue_collected DESC`
  );

  db.close();
  console.log("\n" + "=".repeat(78));
  if (failures === 0) {
    console.log("  ALL VERIFICATION TESTS PASSED (0 failures)");
  } else {
    console.log(`  COMPLETED WITH ${failures} TEST FAILURE(S)`);
    process.exit(1);
  }
  console.log("=".repeat(78));
}

main();

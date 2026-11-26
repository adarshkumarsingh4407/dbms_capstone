-- ============================================================================
-- Project: Smart Fitness Centre and Membership Management System
-- File:    04_reports_queries.sql (MySQL 8.0+)
-- Purpose: All analytical & operational SQL queries required by the problem
--          statement (Attendance, Payment Receipts, Dues, Trainers, Reminders)
-- ============================================================================

USE smart_fitness_db;

-- 1. Pending Dues Report (Members who still owe fees)
SELECT
    subscription_id,
    member_name,
    phone,
    plan_name,
    total_fee,
    amount_paid,
    pending_due,
    end_date
FROM v_member_dues
WHERE pending_due > 0
ORDER BY pending_due DESC;

-- 2. Renewal Reminders Report (Members expiring in <= 7 days or recently expired)
SELECT * FROM v_renewal_reminders;

-- 3. Generate a Payment Receipt (for payment_id = 5)
CALL sp_payment_receipt(5);

-- 4. Member Attendance Summary Report
SELECT
    m.member_id,
    m.full_name AS member_name,
    COUNT(a.attendance_id) AS total_visits,
    MAX(a.attendance_date) AS last_visit_date,
    ROUND(AVG(TIME_TO_SEC(TIMEDIFF(a.check_out_time, a.check_in_time)) / 60.0), 1) AS avg_workout_minutes
FROM Member m
LEFT JOIN Attendance a ON m.member_id = a.member_id
GROUP BY m.member_id, m.full_name
ORDER BY total_visits DESC;

-- 5. Daily Attendance Register (for Today)
SELECT
    a.attendance_date,
    m.full_name AS member_name,
    a.check_in_time,
    a.check_out_time,
    ROUND(TIME_TO_SEC(TIMEDIFF(a.check_out_time, a.check_in_time)) / 60.0, 0) AS minutes_spent
FROM Attendance a
JOIN Member m ON a.member_id = m.member_id
WHERE a.attendance_date = CURRENT_DATE
ORDER BY a.check_in_time;

-- 6. Trainer Assignment & Workload Report
SELECT
    t.trainer_id,
    t.full_name AS trainer_name,
    t.specialization,
    COUNT(DISTINCT CASE WHEN s.status = 'Active' THEN s.member_id END) AS active_assigned_members,
    COUNT(DISTINCT ws.schedule_id) AS weekly_sessions_scheduled
FROM Trainer t
LEFT JOIN Subscription s      ON t.trainer_id = s.trainer_id
LEFT JOIN Workout_Schedule ws ON t.trainer_id = ws.trainer_id
GROUP BY t.trainer_id, t.full_name, t.specialization
ORDER BY active_assigned_members DESC;

-- 7. Weekly Workout Schedule Sheet (Member + Trainer + Slot)
SELECT
    ws.day_of_week,
    ws.start_time,
    ws.end_time,
    m.full_name AS member_name,
    t.full_name AS trainer_name,
    ws.workout_focus
FROM Workout_Schedule ws
JOIN Member m  ON ws.member_id = m.member_id
JOIN Trainer t ON ws.trainer_id = t.trainer_id
ORDER BY FIELD(ws.day_of_week, 'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'),
         ws.start_time;

-- 8. Plan Popularity & Revenue Breakdown
SELECT
    mp.plan_name,
    COUNT(DISTINCT s.subscription_id) AS total_subscriptions,
    COALESCE(SUM(p.amount_paid), 0.00) AS total_revenue_collected
FROM Membership_Plan mp
LEFT JOIN Subscription s ON mp.plan_id = s.plan_id
LEFT JOIN Payment p      ON s.subscription_id = p.subscription_id
GROUP BY mp.plan_id, mp.plan_name
ORDER BY total_revenue_collected DESC;

-- 9. Payment Collection by Payment Method
SELECT
    payment_method,
    COUNT(*) AS transaction_count,
    SUM(amount_paid) AS total_collected
FROM Payment
GROUP BY payment_method
ORDER BY total_collected DESC;

-- 10. Subquery Example: Members who paid MORE than the average payment amount
SELECT DISTINCT
    m.full_name,
    p.receipt_no,
    p.amount_paid,
    p.payment_date
FROM Payment p
JOIN Subscription s ON p.subscription_id = s.subscription_id
JOIN Member m       ON s.member_id = m.member_id
WHERE p.amount_paid > (SELECT AVG(amount_paid) FROM Payment)
ORDER BY p.amount_paid DESC;

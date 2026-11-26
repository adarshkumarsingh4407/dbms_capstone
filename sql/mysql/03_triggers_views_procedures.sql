-- ============================================================================
-- Project: Smart Fitness Centre and Membership Management System
-- File:    03_triggers_views_procedures.sql (MySQL 8.0+)
-- Purpose: Business rules automation via Triggers, Views, and Stored Procedures
-- ============================================================================

USE smart_fitness_db;

-- ============================================================================
-- TRIGGERS
-- ============================================================================
DELIMITER $$

-- 1. Auto-fill end_date and total_fee from Membership_Plan when creating a subscription
DROP TRIGGER IF EXISTS trg_subscription_before_insert$$
CREATE TRIGGER trg_subscription_before_insert
BEFORE INSERT ON Subscription
FOR EACH ROW
BEGIN
    DECLARE v_duration INT;
    DECLARE v_fee DECIMAL(10,2);

    SELECT duration_days, fee
      INTO v_duration, v_fee
      FROM Membership_Plan
     WHERE plan_id = NEW.plan_id;

    IF NEW.end_date IS NULL THEN
        SET NEW.end_date = DATE_ADD(NEW.start_date, INTERVAL v_duration DAY);
    END IF;

    IF NEW.total_fee IS NULL THEN
        SET NEW.total_fee = v_fee;
    END IF;
END$$

-- 2. Prevent overpayment beyond subscription total_fee
DROP TRIGGER IF EXISTS trg_payment_before_insert$$
CREATE TRIGGER trg_payment_before_insert
BEFORE INSERT ON Payment
FOR EACH ROW
BEGIN
    DECLARE v_total_fee DECIMAL(10,2);
    DECLARE v_paid_so_far DECIMAL(10,2);

    SELECT total_fee INTO v_total_fee
      FROM Subscription
     WHERE subscription_id = NEW.subscription_id;

    SELECT COALESCE(SUM(amount_paid), 0) INTO v_paid_so_far
      FROM Payment
     WHERE subscription_id = NEW.subscription_id;

    IF (v_paid_so_far + NEW.amount_paid) > v_total_fee THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Payment rejected: total paid exceeds subscription fee.';
    END IF;
END$$

-- 3. Block check-in if member does not have an Active subscription valid today
DROP TRIGGER IF EXISTS trg_attendance_before_insert$$
CREATE TRIGGER trg_attendance_before_insert
BEFORE INSERT ON Attendance
FOR EACH ROW
BEGIN
    DECLARE v_active_count INT;

    SELECT COUNT(*) INTO v_active_count
      FROM Subscription
     WHERE member_id = NEW.member_id
       AND status = 'Active'
       AND NEW.attendance_date BETWEEN start_date AND end_date;

    IF v_active_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Check-in denied: no valid active membership for this date.';
    END IF;
END$$

DELIMITER ;

-- ============================================================================
-- VIEWS (Reusable virtual tables for Pending Dues & Renewal Reminders)
-- ============================================================================

-- View 1: Membership Validity & Pending Dues
CREATE OR REPLACE VIEW v_member_dues AS
SELECT
    s.subscription_id,
    m.member_id,
    m.full_name       AS member_name,
    m.phone,
    mp.plan_name,
    s.start_date,
    s.end_date,
    s.status          AS subscription_status,
    s.total_fee,
    COALESCE(SUM(p.amount_paid), 0.00)                AS amount_paid,
    (s.total_fee - COALESCE(SUM(p.amount_paid), 0.00)) AS pending_due
FROM Subscription s
JOIN Member m           ON s.member_id = m.member_id
JOIN Membership_Plan mp ON s.plan_id = mp.plan_id
LEFT JOIN Payment p     ON s.subscription_id = p.subscription_id
GROUP BY
    s.subscription_id, m.member_id, m.full_name, m.phone,
    mp.plan_name, s.start_date, s.end_date, s.status, s.total_fee;

-- View 2: Renewal Reminders (Expiring within next 7 days OR expired recently)
CREATE OR REPLACE VIEW v_renewal_reminders AS
SELECT
    m.member_id,
    m.full_name AS member_name,
    m.phone,
    m.email,
    mp.plan_name,
    s.end_date,
    DATEDIFF(s.end_date, CURRENT_DATE) AS days_remaining,
    CASE
        WHEN s.end_date < CURRENT_DATE THEN 'Expired - Follow Up'
        ELSE 'Expiring Soon - Remind'
    END AS reminder_type
FROM Subscription s
JOIN Member m           ON s.member_id = m.member_id
JOIN Membership_Plan mp ON s.plan_id = mp.plan_id
WHERE s.status IN ('Active', 'Expired')
  AND s.end_date <= DATE_ADD(CURRENT_DATE, INTERVAL 7 DAY)
  AND s.end_date >= DATE_SUB(CURRENT_DATE, INTERVAL 30 DAY)
ORDER BY s.end_date ASC;

-- ============================================================================
-- STORED PROCEDURES
-- ============================================================================
DELIMITER $$

-- Procedure 1: Generate an itemized Payment Receipt
DROP PROCEDURE IF EXISTS sp_payment_receipt$$
CREATE PROCEDURE sp_payment_receipt(IN p_payment_id INT)
BEGIN
    SELECT
        p.receipt_no,
        p.payment_date,
        m.member_id,
        m.full_name     AS member_name,
        m.phone,
        mp.plan_name,
        s.start_date,
        s.end_date,
        p.payment_method,
        p.amount_paid   AS paid_this_receipt,
        s.total_fee     AS total_plan_fee,
        (
            SELECT COALESCE(SUM(p2.amount_paid), 0)
            FROM Payment p2
            WHERE p2.subscription_id = s.subscription_id
              AND p2.payment_id <= p.payment_id
        ) AS total_paid_to_date,
        (
            s.total_fee - (
                SELECT COALESCE(SUM(p2.amount_paid), 0)
                FROM Payment p2
                WHERE p2.subscription_id = s.subscription_id
                  AND p2.payment_id <= p.payment_id
            )
        ) AS balance_remaining
    FROM Payment p
    JOIN Subscription s     ON p.subscription_id = s.subscription_id
    JOIN Member m           ON s.member_id = m.member_id
    JOIN Membership_Plan mp ON s.plan_id = mp.plan_id
    WHERE p.payment_id = p_payment_id;
END$$

-- Procedure 2: Mark expired subscriptions automatically
DROP PROCEDURE IF EXISTS sp_refresh_expired_subscriptions$$
CREATE PROCEDURE sp_refresh_expired_subscriptions()
BEGIN
    UPDATE Subscription
       SET status = 'Expired'
     WHERE status = 'Active'
       AND end_date < CURRENT_DATE;
END$$

DELIMITER ;

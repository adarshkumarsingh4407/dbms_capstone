-- ============================================================================
-- Project: Smart Fitness Centre and Membership Management System
-- File:    smart_fitness_workbench_all_in_one.sql (MySQL 8.0 / 8.4 Workbench)
-- Purpose: ONE-CLICK script for MySQL Workbench.
--          Open this file in MySQL Workbench and click the Lightning Bolt (⚡).
--          It creates the database, 7 normalized tables, triggers, views,
--          stored procedures, sample data, and runs all report queries.
-- ============================================================================

DROP DATABASE IF EXISTS smart_fitness_db;
CREATE DATABASE smart_fitness_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE smart_fitness_db;

-- ============================================================================
-- PART 1: TABLES & CONSTRAINTS (3NF / BCNF)
-- ============================================================================

CREATE TABLE Member (
    member_id         INT AUTO_INCREMENT PRIMARY KEY,
    full_name         VARCHAR(100) NOT NULL,
    gender            ENUM('Male', 'Female', 'Other') NOT NULL,
    dob               DATE NOT NULL,
    phone             VARCHAR(15) NOT NULL UNIQUE,
    email             VARCHAR(120) NOT NULL UNIQUE,
    emergency_contact VARCHAR(15) NOT NULL,
    join_date         DATE NOT NULL DEFAULT (CURRENT_DATE),
    status            ENUM('Active', 'Inactive') NOT NULL DEFAULT 'Active'
);

CREATE TABLE Trainer (
    trainer_id      INT AUTO_INCREMENT PRIMARY KEY,
    full_name       VARCHAR(100) NOT NULL,
    specialization  VARCHAR(80) NOT NULL,
    phone           VARCHAR(15) NOT NULL UNIQUE,
    email           VARCHAR(120) NOT NULL UNIQUE,
    hire_date       DATE NOT NULL DEFAULT (CURRENT_DATE),
    monthly_salary  DECIMAL(10, 2) NOT NULL CHECK (monthly_salary > 0),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE Membership_Plan (
    plan_id                    INT AUTO_INCREMENT PRIMARY KEY,
    plan_name                  VARCHAR(60) NOT NULL UNIQUE,
    duration_days              INT NOT NULL CHECK (duration_days > 0),
    fee                        DECIMAL(10, 2) NOT NULL CHECK (fee > 0),
    includes_personal_training BOOLEAN NOT NULL DEFAULT FALSE,
    description                VARCHAR(255)
);

CREATE TABLE Subscription (
    subscription_id INT AUTO_INCREMENT PRIMARY KEY,
    member_id       INT NOT NULL,
    plan_id         INT NOT NULL,
    trainer_id      INT NULL,
    start_date      DATE NOT NULL,
    end_date        DATE NULL,
    total_fee       DECIMAL(10, 2) NULL CHECK (total_fee > 0),
    status          ENUM('Active', 'Expired', 'Cancelled') NOT NULL DEFAULT 'Active',

    CONSTRAINT fk_sub_member  FOREIGN KEY (member_id)  REFERENCES Member(member_id)          ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_sub_plan    FOREIGN KEY (plan_id)    REFERENCES Membership_Plan(plan_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_sub_trainer FOREIGN KEY (trainer_id) REFERENCES Trainer(trainer_id)         ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_sub_dates  CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE Payment (
    payment_id      INT AUTO_INCREMENT PRIMARY KEY,
    subscription_id INT NOT NULL,
    amount_paid     DECIMAL(10, 2) NOT NULL CHECK (amount_paid > 0),
    payment_date    DATE NOT NULL DEFAULT (CURRENT_DATE),
    payment_method  ENUM('Cash', 'UPI', 'Card', 'NetBanking') NOT NULL,
    receipt_no      VARCHAR(30) NOT NULL UNIQUE,
    remarks         VARCHAR(150),

    CONSTRAINT fk_pay_subscription FOREIGN KEY (subscription_id) REFERENCES Subscription(subscription_id) ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE TABLE Workout_Schedule (
    schedule_id    INT AUTO_INCREMENT PRIMARY KEY,
    member_id      INT NOT NULL,
    trainer_id     INT NOT NULL,
    day_of_week    ENUM('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday') NOT NULL,
    start_time     TIME NOT NULL,
    end_time       TIME NOT NULL,
    workout_focus  VARCHAR(80) NOT NULL,
    notes          VARCHAR(200),

    CONSTRAINT fk_ws_member  FOREIGN KEY (member_id)  REFERENCES Member(member_id)   ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ws_trainer FOREIGN KEY (trainer_id) REFERENCES Trainer(trainer_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_ws_time   CHECK (end_time > start_time),
    CONSTRAINT uq_member_slot UNIQUE (member_id, day_of_week, start_time)
);

CREATE TABLE Attendance (
    attendance_id   INT AUTO_INCREMENT PRIMARY KEY,
    member_id       INT NOT NULL,
    attendance_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    check_in_time   TIME NOT NULL,
    check_out_time  TIME NULL,

    CONSTRAINT fk_att_member       FOREIGN KEY (member_id) REFERENCES Member(member_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_att_times       CHECK (check_out_time IS NULL OR check_out_time >= check_in_time),
    CONSTRAINT uq_member_daily_att UNIQUE (member_id, attendance_date)
);

CREATE INDEX idx_sub_member_status ON Subscription(member_id, status, end_date);
CREATE INDEX idx_pay_subscription  ON Payment(subscription_id, payment_date);
CREATE INDEX idx_att_date          ON Attendance(attendance_date);

-- ============================================================================
-- PART 2: TRIGGERS, VIEWS & STORED PROCEDURES
-- ============================================================================

DELIMITER $$

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

CREATE PROCEDURE sp_refresh_expired_subscriptions()
BEGIN
    UPDATE Subscription
       SET status = 'Expired'
     WHERE status = 'Active'
       AND end_date < CURRENT_DATE;
END$$

DELIMITER ;

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
-- PART 3: SAMPLE SEED DATA
-- ============================================================================

INSERT INTO Membership_Plan (plan_name, duration_days, fee, includes_personal_training, description) VALUES
('Monthly Basic',         30,  1500.00,  FALSE, 'Full gym floor access for 30 days'),
('Quarterly Pro',         90,  4000.00,  TRUE,  '90-day gym access with assigned trainer'),
('Half-Yearly Transform', 180, 7500.00,  TRUE,  '180-day transformation program with trainer'),
('Annual Elite',          365, 13000.00, TRUE,  'Full-year all-access pass with personal training');

INSERT INTO Trainer (full_name, specialization, phone, email, hire_date, monthly_salary) VALUES
('Vikram Rathore', 'Strength & Conditioning', '9811100001', 'vikram@smartfit.in', DATE_SUB(CURRENT_DATE, INTERVAL 500 DAY), 38000.00),
('Neha Sharma',    'Fat Loss & HIIT',         '9811100002', 'neha@smartfit.in',   DATE_SUB(CURRENT_DATE, INTERVAL 360 DAY), 35000.00),
('Arjun Nair',     'Mobility & Yoga',         '9811100003', 'arjun@smartfit.in',  DATE_SUB(CURRENT_DATE, INTERVAL 220 DAY), 32000.00);

INSERT INTO Member (full_name, gender, dob, phone, email, emergency_contact, join_date, status) VALUES
('Aarav Mehta',   'Male',   '2002-04-12', '9900112201', 'aarav@mail.com',  '9900112291', DATE_SUB(CURRENT_DATE, INTERVAL 85 DAY),  'Active'),
('Priya Verma',   'Female', '2001-09-25', '9900112202', 'priya@mail.com',  '9900112292', DATE_SUB(CURRENT_DATE, INTERVAL 60 DAY),  'Active'),
('Rohan Das',     'Male',   '1999-12-03', '9900112203', 'rohan@mail.com',  '9900112293', DATE_SUB(CURRENT_DATE, INTERVAL 26 DAY),  'Active'),
('Sneha Iyer',    'Female', '2003-01-18', '9900112204', 'sneha@mail.com',  '9900112294', DATE_SUB(CURRENT_DATE, INTERVAL 45 DAY),  'Active'),
('Kabir Singh',   'Male',   '1998-07-09', '9900112205', 'kabir@mail.com',  '9900112295', DATE_SUB(CURRENT_DATE, INTERVAL 120 DAY), 'Active'),
('Ananya Gupta',  'Female', '2002-11-30', '9900112206', 'ananya@mail.com', '9900112296', DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY),  'Active');

INSERT INTO Subscription (member_id, plan_id, trainer_id, start_date, end_date, total_fee, status) VALUES
(1, 2, 1,    DATE_SUB(CURRENT_DATE, INTERVAL 85 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 5 DAY),   4000.00,  'Active'),
(2, 3, 2,    DATE_SUB(CURRENT_DATE, INTERVAL 60 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 120 DAY), 7500.00,  'Active'),
(3, 1, NULL, DATE_SUB(CURRENT_DATE, INTERVAL 26 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 4 DAY),   1500.00,  'Active'),
(4, 4, 1,    DATE_SUB(CURRENT_DATE, INTERVAL 45 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 320 DAY), 13000.00, 'Active'),
(5, 1, 3,    DATE_SUB(CURRENT_DATE, INTERVAL 40 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 10 DAY),  1500.00,  'Expired'),
(6, 2, 2,    DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 75 DAY),  4000.00,  'Active');

INSERT INTO Payment (subscription_id, amount_paid, payment_date, payment_method, receipt_no, remarks) VALUES
(1, 4000.00, DATE_SUB(CURRENT_DATE, INTERVAL 85 DAY), 'UPI',        'REC-2026-001', 'Full payment'),
(2, 5000.00, DATE_SUB(CURRENT_DATE, INTERVAL 60 DAY), 'Card',       'REC-2026-002', 'First installment'),
(3, 1500.00, DATE_SUB(CURRENT_DATE, INTERVAL 26 DAY), 'Cash',       'REC-2026-003', 'Full payment'),
(4, 8000.00, DATE_SUB(CURRENT_DATE, INTERVAL 45 DAY), 'NetBanking', 'REC-2026-004', 'First installment'),
(4, 2000.00, DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY), 'UPI',        'REC-2026-005', 'Second installment'),
(5, 1500.00, DATE_SUB(CURRENT_DATE, INTERVAL 40 DAY), 'Cash',       'REC-2026-006', 'Full payment'),
(6, 4000.00, DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY), 'UPI',        'REC-2026-007', 'Full payment');

INSERT INTO Workout_Schedule (member_id, trainer_id, day_of_week, start_time, end_time, workout_focus, notes) VALUES
(1, 1, 'Monday',    '07:00:00', '08:00:00', 'Chest & Triceps',    'Progressive overload'),
(1, 1, 'Wednesday', '07:00:00', '08:00:00', 'Back & Biceps',      'Pull-ups + rows'),
(2, 2, 'Tuesday',   '08:00:00', '09:00:00', 'HIIT & Core',        '40s work / 20s rest'),
(2, 2, 'Thursday',  '08:00:00', '09:00:00', 'Lower Body & Cardio','Squats + treadmill'),
(4, 1, 'Monday',    '18:00:00', '19:00:00', 'Full Body Strength', 'Compound lifts'),
(6, 2, 'Friday',    '17:30:00', '18:30:00', 'Functional Cardio',  'Kettlebell circuit');

INSERT INTO Attendance (member_id, attendance_date, check_in_time, check_out_time) VALUES
(1, DATE_SUB(CURRENT_DATE, INTERVAL 3 DAY), '07:02:00', '08:10:00'),
(1, DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY), '07:05:00', '08:05:00'),
(1, CURRENT_DATE,                           '07:00:00', '08:00:00'),
(2, DATE_SUB(CURRENT_DATE, INTERVAL 2 DAY), '08:00:00', '09:05:00'),
(2, CURRENT_DATE,                           '08:04:00', '09:00:00'),
(3, DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY), '18:15:00', '19:10:00'),
(4, DATE_SUB(CURRENT_DATE, INTERVAL 2 DAY), '18:00:00', '19:15:00'),
(4, CURRENT_DATE,                           '17:58:00', '19:02:00'),
(6, DATE_SUB(CURRENT_DATE, INTERVAL 1 DAY), '17:30:00', '18:30:00');

-- ============================================================================
-- PART 4: DEMO REPORT OUTPUTS (Shows result tabs automatically in Workbench)
-- ============================================================================

-- 1. Pending Dues Report
SELECT subscription_id, member_name, phone, plan_name, total_fee, amount_paid, pending_due, end_date
FROM v_member_dues
WHERE pending_due > 0
ORDER BY pending_due DESC;

-- 2. Renewal Reminders Report
SELECT * FROM v_renewal_reminders;

-- 3. Payment Receipt (Receipt #5)
CALL sp_payment_receipt(5);

-- 4. Member Attendance Summary
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

-- 5. Trainer Workload & Assigned Members
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

-- 6. Plan Popularity & Revenue Breakdown
SELECT
    mp.plan_name,
    COUNT(DISTINCT s.subscription_id) AS total_subscriptions,
    COALESCE(SUM(p.amount_paid), 0.00) AS total_revenue_collected
FROM Membership_Plan mp
LEFT JOIN Subscription s ON mp.plan_id = s.plan_id
LEFT JOIN Payment p      ON s.subscription_id = p.subscription_id
GROUP BY mp.plan_id, mp.plan_name
ORDER BY total_revenue_collected DESC;

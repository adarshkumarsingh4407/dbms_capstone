-- ============================================================================
-- Project: Smart Fitness Centre and Membership Management System
-- File:    fitness_db_complete.sql (SQLite 3 compatible)
-- Purpose: Single-file database script for instant offline testing via Python
--          or SQLite CLI without needing a running MySQL server.
-- ============================================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS Attendance;
DROP TABLE IF EXISTS Workout_Schedule;
DROP TABLE IF EXISTS Payment;
DROP TABLE IF EXISTS Subscription;
DROP TABLE IF EXISTS Membership_Plan;
DROP TABLE IF EXISTS Trainer;
DROP TABLE IF EXISTS Member;

-- 1. Member
CREATE TABLE Member (
    member_id         INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name         TEXT NOT NULL,
    gender            TEXT NOT NULL CHECK (gender IN ('Male', 'Female', 'Other')),
    dob               TEXT NOT NULL,
    phone             TEXT NOT NULL UNIQUE,
    email             TEXT NOT NULL UNIQUE,
    emergency_contact TEXT NOT NULL,
    join_date         TEXT NOT NULL DEFAULT (DATE('now')),
    status            TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Inactive'))
);

-- 2. Trainer
CREATE TABLE Trainer (
    trainer_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name       TEXT NOT NULL,
    specialization  TEXT NOT NULL,
    phone           TEXT NOT NULL UNIQUE,
    email           TEXT NOT NULL UNIQUE,
    hire_date       TEXT NOT NULL DEFAULT (DATE('now')),
    monthly_salary  REAL NOT NULL CHECK (monthly_salary > 0),
    is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
);

-- 3. Membership_Plan
CREATE TABLE Membership_Plan (
    plan_id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    plan_name                  TEXT NOT NULL UNIQUE,
    duration_days              INTEGER NOT NULL CHECK (duration_days > 0),
    fee                        REAL NOT NULL CHECK (fee > 0),
    includes_personal_training INTEGER NOT NULL DEFAULT 0 CHECK (includes_personal_training IN (0, 1)),
    description                TEXT
);

-- 4. Subscription
CREATE TABLE Subscription (
    subscription_id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id       INTEGER NOT NULL REFERENCES Member(member_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    plan_id         INTEGER NOT NULL REFERENCES Membership_Plan(plan_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    trainer_id      INTEGER NULL REFERENCES Trainer(trainer_id) ON DELETE SET NULL ON UPDATE CASCADE,
    start_date      TEXT NOT NULL,
    end_date        TEXT NULL,
    total_fee       REAL NULL CHECK (total_fee IS NULL OR total_fee > 0),
    status          TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Expired', 'Cancelled')),
    CHECK (end_date IS NULL OR end_date >= start_date)
);

-- 5. Payment
CREATE TABLE Payment (
    payment_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    subscription_id INTEGER NOT NULL REFERENCES Subscription(subscription_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    amount_paid     REAL NOT NULL CHECK (amount_paid > 0),
    payment_date    TEXT NOT NULL DEFAULT (DATE('now')),
    payment_method  TEXT NOT NULL CHECK (payment_method IN ('Cash', 'UPI', 'Card', 'NetBanking')),
    receipt_no      TEXT NOT NULL UNIQUE,
    remarks         TEXT
);

-- 6. Workout_Schedule
CREATE TABLE Workout_Schedule (
    schedule_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id      INTEGER NOT NULL REFERENCES Member(member_id) ON DELETE CASCADE ON UPDATE CASCADE,
    trainer_id     INTEGER NOT NULL REFERENCES Trainer(trainer_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    day_of_week    TEXT NOT NULL CHECK (day_of_week IN ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')),
    start_time     TEXT NOT NULL,
    end_time       TEXT NOT NULL,
    workout_focus  TEXT NOT NULL,
    notes          TEXT,
    CHECK (end_time > start_time),
    UNIQUE (member_id, day_of_week, start_time)
);

-- 7. Attendance
CREATE TABLE Attendance (
    attendance_id   INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id       INTEGER NOT NULL REFERENCES Member(member_id) ON DELETE CASCADE ON UPDATE CASCADE,
    attendance_date TEXT NOT NULL DEFAULT (DATE('now')),
    check_in_time   TEXT NOT NULL,
    check_out_time  TEXT NULL,
    CHECK (check_out_time IS NULL OR check_out_time >= check_in_time),
    UNIQUE (member_id, attendance_date)
);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-fill end_date & total_fee if omitted during Subscription insert
CREATE TRIGGER trg_sub_after_insert
AFTER INSERT ON Subscription
FOR EACH ROW
WHEN NEW.end_date IS NULL OR NEW.total_fee IS NULL
BEGIN
    UPDATE Subscription
    SET
        end_date = COALESCE(NEW.end_date, DATE(NEW.start_date, '+' || (SELECT duration_days FROM Membership_Plan WHERE plan_id = NEW.plan_id) || ' days')),
        total_fee = COALESCE(NEW.total_fee, (SELECT fee FROM Membership_Plan WHERE plan_id = NEW.plan_id))
    WHERE subscription_id = NEW.subscription_id;
END;

-- Prevent overpayment beyond subscription total_fee
CREATE TRIGGER trg_payment_before_insert
BEFORE INSERT ON Payment
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'Payment rejected: total paid exceeds subscription fee.')
    WHERE (
        (SELECT COALESCE(SUM(amount_paid), 0) FROM Payment WHERE subscription_id = NEW.subscription_id)
        + NEW.amount_paid
    ) > (SELECT total_fee FROM Subscription WHERE subscription_id = NEW.subscription_id);
END;

-- Block check-in without a valid active subscription covering attendance_date
CREATE TRIGGER trg_attendance_before_insert
BEFORE INSERT ON Attendance
FOR EACH ROW
BEGIN
    SELECT RAISE(ABORT, 'Check-in denied: no valid active membership for this date.')
    WHERE NOT EXISTS (
        SELECT 1 FROM Subscription
        WHERE member_id = NEW.member_id
          AND status = 'Active'
          AND NEW.attendance_date BETWEEN start_date AND end_date
    );
END;

-- ============================================================================
-- VIEWS
-- ============================================================================
CREATE VIEW v_member_dues AS
SELECT
    s.subscription_id,
    m.member_id,
    m.full_name AS member_name,
    m.phone,
    mp.plan_name,
    s.start_date,
    s.end_date,
    s.status AS subscription_status,
    s.total_fee,
    ROUND(COALESCE(SUM(p.amount_paid), 0.0), 2) AS amount_paid,
    ROUND(s.total_fee - COALESCE(SUM(p.amount_paid), 0.0), 2) AS pending_due
FROM Subscription s
JOIN Member m ON s.member_id = m.member_id
JOIN Membership_Plan mp ON s.plan_id = mp.plan_id
LEFT JOIN Payment p ON s.subscription_id = p.subscription_id
GROUP BY s.subscription_id;

CREATE VIEW v_renewal_reminders AS
SELECT
    m.member_id,
    m.full_name AS member_name,
    m.phone,
    m.email,
    mp.plan_name,
    s.end_date,
    CAST(JULIANDAY(s.end_date) - JULIANDAY(DATE('now')) AS INTEGER) AS days_remaining,
    CASE
        WHEN s.end_date < DATE('now') THEN 'Expired - Follow Up'
        ELSE 'Expiring Soon - Remind'
    END AS reminder_type
FROM Subscription s
JOIN Member m ON s.member_id = m.member_id
JOIN Membership_Plan mp ON s.plan_id = mp.plan_id
WHERE s.status IN ('Active', 'Expired')
  AND s.end_date <= DATE('now', '+7 days')
  AND s.end_date >= DATE('now', '-30 days')
ORDER BY s.end_date ASC;

-- ============================================================================
-- SEED DATA
-- ============================================================================
INSERT INTO Membership_Plan (plan_name, duration_days, fee, includes_personal_training, description) VALUES
('Monthly Basic',         30,  1500.00,  0, 'Full gym floor access for 30 days'),
('Quarterly Pro',         90,  4000.00,  1, '90-day gym access with assigned trainer'),
('Half-Yearly Transform', 180, 7500.00,  1, '180-day transformation program with trainer'),
('Annual Elite',          365, 13000.00, 1, 'Full-year all-access pass with personal training');

INSERT INTO Trainer (full_name, specialization, phone, email, hire_date, monthly_salary) VALUES
('Vikram Rathore', 'Strength & Conditioning', '9811100001', 'vikram@smartfit.in', DATE('now', '-500 days'), 38000.00),
('Neha Sharma',    'Fat Loss & HIIT',         '9811100002', 'neha@smartfit.in',   DATE('now', '-360 days'), 35000.00),
('Arjun Nair',     'Mobility & Yoga',         '9811100003', 'arjun@smartfit.in',  DATE('now', '-220 days'), 32000.00);

INSERT INTO Member (full_name, gender, dob, phone, email, emergency_contact, join_date, status) VALUES
('Aarav Mehta',   'Male',   '2002-04-12', '9900112201', 'aarav@mail.com',  '9900112291', DATE('now', '-85 days'),  'Active'),
('Priya Verma',   'Female', '2001-09-25', '9900112202', 'priya@mail.com',  '9900112292', DATE('now', '-60 days'),  'Active'),
('Rohan Das',     'Male',   '1999-12-03', '9900112203', 'rohan@mail.com',  '9900112293', DATE('now', '-26 days'),  'Active'),
('Sneha Iyer',    'Female', '2003-01-18', '9900112204', 'sneha@mail.com',  '9900112294', DATE('now', '-45 days'),  'Active'),
('Kabir Singh',   'Male',   '1998-07-09', '9900112205', 'kabir@mail.com',  '9900112295', DATE('now', '-120 days'), 'Active'),
('Ananya Gupta',  'Female', '2002-11-30', '9900112206', 'ananya@mail.com', '9900112296', DATE('now', '-15 days'),  'Active');

INSERT INTO Subscription (member_id, plan_id, trainer_id, start_date, end_date, total_fee, status) VALUES
(1, 2, 1,    DATE('now', '-85 days'), DATE('now', '+5 days'),   4000.00,  'Active'),
(2, 3, 2,    DATE('now', '-60 days'), DATE('now', '+120 days'), 7500.00,  'Active'),
(3, 1, NULL, DATE('now', '-26 days'), DATE('now', '+4 days'),   1500.00,  'Active'),
(4, 4, 1,    DATE('now', '-45 days'), DATE('now', '+320 days'), 13000.00, 'Active'),
(5, 1, 3,    DATE('now', '-40 days'), DATE('now', '-10 days'),  1500.00,  'Expired'),
(6, 2, 2,    DATE('now', '-15 days'), DATE('now', '+75 days'),  4000.00,  'Active');

INSERT INTO Payment (subscription_id, amount_paid, payment_date, payment_method, receipt_no, remarks) VALUES
(1, 4000.00, DATE('now', '-85 days'), 'UPI',        'REC-2026-001', 'Full payment'),
(2, 5000.00, DATE('now', '-60 days'), 'Card',       'REC-2026-002', 'First installment'),
(3, 1500.00, DATE('now', '-26 days'), 'Cash',       'REC-2026-003', 'Full payment'),
(4, 8000.00, DATE('now', '-45 days'), 'NetBanking', 'REC-2026-004', 'First installment'),
(4, 2000.00, DATE('now', '-15 days'), 'UPI',        'REC-2026-005', 'Second installment'),
(5, 1500.00, DATE('now', '-40 days'), 'Cash',       'REC-2026-006', 'Full payment'),
(6, 4000.00, DATE('now', '-15 days'), 'UPI',        'REC-2026-007', 'Full payment');

INSERT INTO Workout_Schedule (member_id, trainer_id, day_of_week, start_time, end_time, workout_focus, notes) VALUES
(1, 1, 'Monday',    '07:00:00', '08:00:00', 'Chest & Triceps',    'Progressive overload'),
(1, 1, 'Wednesday', '07:00:00', '08:00:00', 'Back & Biceps',      'Pull-ups + rows'),
(2, 2, 'Tuesday',   '08:00:00', '09:00:00', 'HIIT & Core',        '40s work / 20s rest'),
(2, 2, 'Thursday',  '08:00:00', '09:00:00', 'Lower Body & Cardio','Squats + treadmill'),
(4, 1, 'Monday',    '18:00:00', '19:00:00', 'Full Body Strength', 'Compound lifts'),
(6, 2, 'Friday',    '17:30:00', '18:30:00', 'Functional Cardio',  'Kettlebell circuit');

INSERT INTO Attendance (member_id, attendance_date, check_in_time, check_out_time) VALUES
(1, DATE('now', '-3 days'), '07:02:00', '08:10:00'),
(1, DATE('now', '-1 days'), '07:05:00', '08:05:00'),
(1, DATE('now'),            '07:00:00', '08:00:00'),
(2, DATE('now', '-2 days'), '08:00:00', '09:05:00'),
(2, DATE('now'),            '08:04:00', '09:00:00'),
(3, DATE('now', '-1 days'), '18:15:00', '19:10:00'),
(4, DATE('now', '-2 days'), '18:00:00', '19:15:00'),
(4, DATE('now'),            '17:58:00', '19:02:00'),
(6, DATE('now', '-1 days'), '17:30:00', '18:30:00');

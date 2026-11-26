-- ============================================================================
-- Project: Smart Fitness Centre and Membership Management System
-- File:    02_seed_data.sql (MySQL 8.0+)
-- Purpose: Populates realistic sample data using relative dates (CURRENT_DATE)
--          so renewal reminders, active plans, and expired plans always work.
-- ============================================================================

USE smart_fitness_db;

-- 1. Membership Plans
INSERT INTO Membership_Plan (plan_name, duration_days, fee, includes_personal_training, description) VALUES
('Monthly Basic',        30,  1500.00,  FALSE, 'Full gym floor access for 30 days'),
('Quarterly Pro',        90,  4000.00,  TRUE,  '90-day gym access with assigned trainer'),
('Half-Yearly Transform',180, 7500.00,  TRUE,  '180-day transformation program with trainer'),
('Annual Elite',         365, 13000.00, TRUE,  'Full-year all-access pass with personal training');

-- 2. Trainers
INSERT INTO Trainer (full_name, specialization, phone, email, hire_date, monthly_salary) VALUES
('Vikram Rathore', 'Strength & Conditioning', '9811100001', 'vikram@smartfit.in', DATE_SUB(CURRENT_DATE, INTERVAL 500 DAY), 38000.00),
('Neha Sharma',    'Fat Loss & HIIT',         '9811100002', 'neha@smartfit.in',   DATE_SUB(CURRENT_DATE, INTERVAL 360 DAY), 35000.00),
('Arjun Nair',     'Mobility & Yoga',         '9811100003', 'arjun@smartfit.in',  DATE_SUB(CURRENT_DATE, INTERVAL 220 DAY), 32000.00);

-- 3. Members
INSERT INTO Member (full_name, gender, dob, phone, email, emergency_contact, join_date, status) VALUES
('Aarav Mehta',   'Male',   '2002-04-12', '9900112201', 'aarav@mail.com',  '9900112291', DATE_SUB(CURRENT_DATE, INTERVAL 85 DAY), 'Active'),
('Priya Verma',   'Female', '2001-09-25', '9900112202', 'priya@mail.com',  '9900112292', DATE_SUB(CURRENT_DATE, INTERVAL 60 DAY), 'Active'),
('Rohan Das',     'Male',   '1999-12-03', '9900112203', 'rohan@mail.com',  '9900112293', DATE_SUB(CURRENT_DATE, INTERVAL 26 DAY), 'Active'),
('Sneha Iyer',    'Female', '2003-01-18', '9900112204', 'sneha@mail.com',  '9900112294', DATE_SUB(CURRENT_DATE, INTERVAL 45 DAY), 'Active'),
('Kabir Singh',   'Male',   '1998-07-09', '9900112205', 'kabir@mail.com',  '9900112295', DATE_SUB(CURRENT_DATE, INTERVAL 120 DAY),'Active'),
('Ananya Gupta',  'Female', '2002-11-30', '9900112206', 'ananya@mail.com', '9900112296', DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY), 'Active');

-- 4. Subscriptions (Note: triggers auto-fill end_date & total_fee if left NULL,
--    and we insert explicit dates/fees too so this script works in any run order)
INSERT INTO Subscription (member_id, plan_id, trainer_id, start_date, end_date, total_fee, status) VALUES
-- Aarav: Quarterly Pro, expiring in 5 days (triggers renewal reminder!)
(1, 2, 1, DATE_SUB(CURRENT_DATE, INTERVAL 85 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 5 DAY),   4000.00,  'Active'),
-- Priya: Half-Yearly Transform, active with pending due
(2, 3, 2, DATE_SUB(CURRENT_DATE, INTERVAL 60 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 120 DAY), 7500.00,  'Active'),
-- Rohan: Monthly Basic, expiring in 4 days (renewal reminder + fully paid)
(3, 1, NULL, DATE_SUB(CURRENT_DATE, INTERVAL 26 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 4 DAY),1500.00,  'Active'),
-- Sneha: Annual Elite, active with pending due
(4, 4, 1, DATE_SUB(CURRENT_DATE, INTERVAL 45 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 320 DAY), 13000.00, 'Active'),
-- Kabir: Monthly Basic, already expired 10 days ago
(5, 1, 3, DATE_SUB(CURRENT_DATE, INTERVAL 40 DAY), DATE_SUB(CURRENT_DATE, INTERVAL 10 DAY), 1500.00,  'Expired'),
-- Ananya: Quarterly Pro, recently joined, full paid
(6, 2, 2, DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY), DATE_ADD(CURRENT_DATE, INTERVAL 75 DAY),  4000.00,  'Active');

-- 5. Payments (Includes full payments and partial installments to show pending dues)
INSERT INTO Payment (subscription_id, amount_paid, payment_date, payment_method, receipt_no, remarks) VALUES
(1, 4000.00, DATE_SUB(CURRENT_DATE, INTERVAL 85 DAY), 'UPI',        'REC-2026-001', 'Full payment'),
(2, 5000.00, DATE_SUB(CURRENT_DATE, INTERVAL 60 DAY), 'Card',       'REC-2026-002', 'First installment'),
(3, 1500.00, DATE_SUB(CURRENT_DATE, INTERVAL 26 DAY), 'Cash',       'REC-2026-003', 'Full payment'),
(4, 8000.00, DATE_SUB(CURRENT_DATE, INTERVAL 45 DAY), 'NetBanking', 'REC-2026-004', 'First installment'),
(4, 2000.00, DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY), 'UPI',        'REC-2026-005', 'Second installment'),
(5, 1500.00, DATE_SUB(CURRENT_DATE, INTERVAL 40 DAY), 'Cash',       'REC-2026-006', 'Full payment'),
(6, 4000.00, DATE_SUB(CURRENT_DATE, INTERVAL 15 DAY), 'UPI',        'REC-2026-007', 'Full payment');

-- 6. Workout Schedules
INSERT INTO Workout_Schedule (member_id, trainer_id, day_of_week, start_time, end_time, workout_focus, notes) VALUES
(1, 1, 'Monday',    '07:00:00', '08:00:00', 'Chest & Triceps',   'Progressive overload'),
(1, 1, 'Wednesday', '07:00:00', '08:00:00', 'Back & Biceps',     'Pull-ups + rows'),
(2, 2, 'Tuesday',   '08:00:00', '09:00:00', 'HIIT & Core',       '40s work / 20s rest'),
(2, 2, 'Thursday',  '08:00:00', '09:00:00', 'Lower Body & Cardio','Squats + treadmill'),
(4, 1, 'Monday',    '18:00:00', '19:00:00', 'Full Body Strength','Compound lifts'),
(6, 2, 'Friday',    '17:30:00', '18:30:00', 'Functional Cardio', 'Kettlebell circuit');

-- 7. Attendance Logs
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

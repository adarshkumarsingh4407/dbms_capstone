-- ============================================================================
-- Project: Smart Fitness Centre and Membership Management System
-- File:    01_schema.sql (MySQL 8.0+)
-- Purpose: Creates the normalized (3NF/BCNF) database schema with constraints
-- ============================================================================

DROP DATABASE IF EXISTS smart_fitness_db;
CREATE DATABASE smart_fitness_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE smart_fitness_db;

-- ----------------------------------------------------------------------------
-- 1. MEMBER: Stores registered gym members
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 2. TRAINER: Stores certified fitness trainers
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 3. MEMBERSHIP_PLAN: Catalog of gym plans, durations, and standard fees
-- ----------------------------------------------------------------------------
CREATE TABLE Membership_Plan (
    plan_id                    INT AUTO_INCREMENT PRIMARY KEY,
    plan_name                  VARCHAR(60) NOT NULL UNIQUE,
    duration_days              INT NOT NULL CHECK (duration_days > 0),
    fee                        DECIMAL(10, 2) NOT NULL CHECK (fee > 0),
    includes_personal_training BOOLEAN NOT NULL DEFAULT FALSE,
    description                VARCHAR(255)
);

-- ----------------------------------------------------------------------------
-- 4. SUBSCRIPTION: Links a Member to a Membership_Plan & assigned Trainer
--    Tracks membership validity (start_date to end_date) and fee snapshot
-- ----------------------------------------------------------------------------
CREATE TABLE Subscription (
    subscription_id INT AUTO_INCREMENT PRIMARY KEY,
    member_id       INT NOT NULL,
    plan_id         INT NOT NULL,
    trainer_id      INT NULL,
    start_date      DATE NOT NULL,
    end_date        DATE NULL,
    total_fee       DECIMAL(10, 2) NULL CHECK (total_fee > 0),
    status          ENUM('Active', 'Expired', 'Cancelled') NOT NULL DEFAULT 'Active',

    CONSTRAINT fk_sub_member
        FOREIGN KEY (member_id) REFERENCES Member(member_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_sub_plan
        FOREIGN KEY (plan_id) REFERENCES Membership_Plan(plan_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_sub_trainer
        FOREIGN KEY (trainer_id) REFERENCES Trainer(trainer_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_sub_dates
        CHECK (end_date IS NULL OR end_date >= start_date)
);

-- ----------------------------------------------------------------------------
-- 5. PAYMENT: Stores fee installments / full payments & receipt numbers
-- ----------------------------------------------------------------------------
CREATE TABLE Payment (
    payment_id      INT AUTO_INCREMENT PRIMARY KEY,
    subscription_id INT NOT NULL,
    amount_paid     DECIMAL(10, 2) NOT NULL CHECK (amount_paid > 0),
    payment_date    DATE NOT NULL DEFAULT (CURRENT_DATE),
    payment_method  ENUM('Cash', 'UPI', 'Card', 'NetBanking') NOT NULL,
    receipt_no      VARCHAR(30) NOT NULL UNIQUE,
    remarks         VARCHAR(150),

    CONSTRAINT fk_pay_subscription
        FOREIGN KEY (subscription_id) REFERENCES Subscription(subscription_id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- ----------------------------------------------------------------------------
-- 6. WORKOUT_SCHEDULE: Weekly workout routines assigned to members by trainers
-- ----------------------------------------------------------------------------
CREATE TABLE Workout_Schedule (
    schedule_id    INT AUTO_INCREMENT PRIMARY KEY,
    member_id      INT NOT NULL,
    trainer_id     INT NOT NULL,
    day_of_week    ENUM('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday') NOT NULL,
    start_time     TIME NOT NULL,
    end_time       TIME NOT NULL,
    workout_focus  VARCHAR(80) NOT NULL,
    notes          VARCHAR(200),

    CONSTRAINT fk_ws_member
        FOREIGN KEY (member_id) REFERENCES Member(member_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_ws_trainer
        FOREIGN KEY (trainer_id) REFERENCES Trainer(trainer_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_ws_time
        CHECK (end_time > start_time),
    CONSTRAINT uq_member_slot
        UNIQUE (member_id, day_of_week, start_time)
);

-- ----------------------------------------------------------------------------
-- 7. ATTENDANCE: Daily member check-ins and check-outs
-- ----------------------------------------------------------------------------
CREATE TABLE Attendance (
    attendance_id   INT AUTO_INCREMENT PRIMARY KEY,
    member_id       INT NOT NULL,
    attendance_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    check_in_time   TIME NOT NULL,
    check_out_time  TIME NULL,

    CONSTRAINT fk_att_member
        FOREIGN KEY (member_id) REFERENCES Member(member_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_att_times
        CHECK (check_out_time IS NULL OR check_out_time >= check_in_time),
    CONSTRAINT uq_member_daily_att
        UNIQUE (member_id, attendance_date)
);

-- ----------------------------------------------------------------------------
-- INDEXES for faster reporting and lookup
-- ----------------------------------------------------------------------------
CREATE INDEX idx_sub_member_status ON Subscription(member_id, status, end_date);
CREATE INDEX idx_pay_subscription  ON Payment(subscription_id, payment_date);
CREATE INDEX idx_att_date          ON Attendance(attendance_date);

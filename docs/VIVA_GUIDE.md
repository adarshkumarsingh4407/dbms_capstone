# Viva & Presentation Cheat Sheet (Score Full Marks)

## 1. Your 2-Minute Opening Explanation (Memorize This Flow)

> "Good morning/afternoon. My DBMS Capstone project is the **Smart Fitness Centre and Membership Management System**.
>
> **The Problem:** Gyms often track memberships, payments, trainers, and attendance in scattered spreadsheets, leading to missed renewal reminders, untracked pending dues, and expired members still entering the gym.
>
> **My Database Design:** I designed a **7-table normalized schema in 3NF/BCNF**:
> 1. **Master tables:** `Member`, `Trainer`, and `Membership_Plan` store core entity details without duplication.
> 2. **Transaction tables:** `Subscription` links a member, a plan, and an optional assigned trainer with validity dates (`start_date` to `end_date`). `Payment` records installments and receipt numbers against each subscription.
> 3. **Operations tables:** `Workout_Schedule` tracks weekly trainer sessions, and `Attendance` logs daily check-in and check-out times.
>
> **Database Intelligence (Triggers & Views):** Rather than putting all logic in the UI, I enforced key rules directly inside the database:
> - A trigger automatically computes `end_date` from the plan's duration.
> - A validation trigger blocks **overpayment** beyond the subscription fee.
> - An attendance trigger blocks **check-in** if the member's subscription is expired.
> - Views (`v_member_dues`, `v_renewal_reminders`) and a stored procedure (`sp_payment_receipt`) generate pending dues, 7-day renewal alerts, attendance reports, and payment receipts."

---

## 2. Top 15 Examiner Viva Questions & Crisp Answers

### Q1. Why did you separate `Membership_Plan` and `Subscription` instead of keeping plan name and fee directly inside `Member`?
**Answer:** If we put plan details inside `Member`, changing a plan's fee would require updating hundreds of rows (update anomaly), and a member couldn't hold multiple historical memberships cleanly. Separating `Membership_Plan` (catalog) and `Subscription` (purchase history) achieves **3NF** and supports renewals over time.

### Q2. Wait — if `Membership_Plan` already has `fee`, why does `Subscription` also have `total_fee`? Isn't that redundant?
**Answer:** Great question! `Membership_Plan.fee` is the *current* catalog price, whereas `Subscription.total_fee` is the *historical price locked in when the member joined*. If the gym raises the Quarterly plan from ₹4,000 to ₹4,500 next month, existing members' pending dues shouldn't suddenly increase by ₹500. So `total_fee` depends on `subscription_id`, not `plan_id`—meaning there is **no transitive dependency**.

### Q3. Why didn't you store `pending_due` as a column in `Subscription`?
**Answer:** Because `pending_due` is a **derived attribute** (`total_fee - SUM(amount_paid)`). Storing it physically risks inconsistency if a payment row is inserted or corrected. Computing it dynamically via the `v_member_dues` **View** guarantees it is always 100% accurate.

### Q4. How does your database prevent invalid data?
**Answer:** At three levels:
1. **Column/Table Constraints:** `CHECK (amount_paid > 0)`, `CHECK (end_time > start_time)`, `UNIQUE (phone)`, `UNIQUE (receipt_no)`, `UNIQUE (member_id, attendance_date)`.
2. **Referential Integrity:** Foreign keys with `ON DELETE RESTRICT` on `Member`, `Membership_Plan`, and `Subscription` so financial/payment records cannot be accidentally wiped out.
3. **Triggers:** Reject overpayments and block attendance check-ins for expired memberships.

### Q5. Explain your 3 triggers in one line each.
1. `trg_subscription_before_insert`: Auto-fills `end_date` and `total_fee` from `Membership_Plan` when omitted.
2. `trg_payment_before_insert`: Raises an error if `(already_paid + new_amount) > total_fee`.
3. `trg_attendance_before_insert`: Raises an error if the member has no `Active` subscription covering `attendance_date`.

### Q6. Why is `trainer_id` nullable (`NULL`) in `Subscription`, but `NOT NULL` in `Workout_Schedule`?
**Answer:** A member buying a basic plan ("Monthly Basic") does not get a personal trainer, so `trainer_id` in `Subscription` can be `NULL`. However, a `Workout_Schedule` entry represents an actual trainer-led session, so it must reference both a member and a trainer (`NOT NULL`).

### Q7. How did you handle `ON DELETE` rules?
**Answer:**
* `Member → Subscription` and `Subscription → Payment`: `ON DELETE RESTRICT` to preserve billing/audit history.
* `Trainer → Subscription`: `ON DELETE SET NULL` so removing/archiving a trainer doesn't delete the member's paid subscription.
* `Member → Attendance` / `Workout_Schedule`: `ON DELETE CASCADE` (or soft-deactivate via `Member.status = 'Inactive'` in production).

### Q8. What normal form is your database in?
**Answer:** **BCNF (Boyce-Codd Normal Form)**. Every table has atomic values (1NF), no partial dependencies (2NF), no transitive dependencies (3NF), and every determinant in every functional dependency is a candidate key (BCNF).

### Q9. How do you generate a Payment Receipt?
**Answer:** Using the stored procedure `sp_payment_receipt(payment_id)`, which joins `Payment`, `Subscription`, `Member`, and `Membership_Plan`, and uses a correlated subquery to show both the **amount paid on that receipt** and the **remaining balance** up to that receipt.

### Q10. How do Renewal Reminders work?
**Answer:** The view `v_renewal_reminders` checks subscriptions whose `end_date` is within the next 7 days (`end_date <= CURRENT_DATE + 7 days`) or expired within the last 30 days, and labels them `'Expiring Soon - Remind'` or `'Expired - Follow Up'` sorted by `end_date`.

### Q11. What happens if a member tries to check in twice on the same day?
**Answer:** The composite unique constraint `UNIQUE (member_id, attendance_date)` rejects the duplicate scan cleanly.

### Q12. What happens if two workouts are scheduled for a member at the same day and time?
**Answer:** `UNIQUE (member_id, day_of_week, start_time)` prevents double-booking the member into conflicting slots.

### Q13. Which indexes did you create and why?
**Answer:**
* `idx_sub_member_status` on `Subscription(member_id, status, end_date)` — speeds up the attendance trigger check and renewal reminder queries.
* `idx_pay_subscription` on `Payment(subscription_id, payment_date)` — speeds up `SUM(amount_paid)` in `v_member_dues`.
* `idx_att_date` on `Attendance(attendance_date)` — speeds up daily attendance register lookups.

### Q14. What is the difference between a View and a Stored Procedure in your project?
**Answer:** A **View** (`v_member_dues`, `v_renewal_reminders`) acts like a reusable virtual table that can be queried with `SELECT ... WHERE ...`. A **Stored Procedure** (`sp_payment_receipt(id)`, `sp_refresh_expired_subscriptions()`) accepts parameters or performs batch `UPDATE` operations when invoked with `CALL`.

### Q15. How could this database scale if the gym opens multiple branches?
**Answer:** Simply add one `Branch(branch_id, branch_name, city)` table and add `branch_id` as a foreign key in `Trainer`, `Subscription`, and `Attendance`—without changing the rest of the normalized design!

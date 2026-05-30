# GLCL — Presentation Strategy Run Guide

> Run every command block in **MySQL Workbench** (or the MySQL CLI).
> Always confirm `USE GLCL_DB;` is active before running anything.

---

## Prerequisites — Run First (Once Per Session)

If the database is not already set up, run these in order:

```sql
SOURCE GLCL_Database_MySQL.sql;   -- creates schema + constraints
SOURCE seedata.sql;               -- loads test data
SOURCE recreate_triggers.sql;     -- creates business-logic triggers
```

Verify the database is selected:

```sql
USE GLCL_DB;
SELECT DATABASE();                -- should return: GLCL_DB
```

---

## Member 1 — Strategy: Composite Indexes

### What it does
Creates 6 composite indexes targeted at the sub-queries that fire inside
`TR_BookingPassenger_BI_ValidateRules` and
`TR_BookingCabin_BI_PreventDoubleBooking` on every INSERT.

### Step 1 — Run the indexes

```sql
CREATE INDEX IDX_FareRule_Voyage_Cabin_Age_Date
    ON FareRule (VoyageID, CabinCategoryID, AgeCategoryID, EffectiveFrom DESC);

CREATE INDEX IDX_BookingPassenger_Cabin_Booking
    ON BookingPassenger (BookingCabinID, BookingID);

CREATE INDEX IDX_BookingCabin_Cabin_Booking
    ON BookingCabin (CabinID, BookingID);

CREATE INDEX IDX_Booking_Voyage_Status
    ON Booking (VoyageID, BookingStatus);

CREATE INDEX IDX_CancellationPolicy_Operator_Hours
    ON CancellationPolicy (OperatorID, HoursBeforeDeparture ASC);

CREATE INDEX IDX_BaggageRule_Operator_Date
    ON BaggageRule (OperatorID, EffectiveFrom, EffectiveTo);
```

### Step 2 — Verify the indexes exist

```sql
SHOW INDEX FROM FareRule;
SHOW INDEX FROM BookingPassenger;
SHOW INDEX FROM Booking;
```

Look for `Key_name` = `IDX_FareRule_Voyage_Cabin_Age_Date` etc. in the output.

### Step 3 — Demonstrate the benefit (EXPLAIN)

Run this BEFORE and AFTER creating the index to show the difference.
(If indexes are already created, drop one first to show the contrast.)

```sql
-- Shows how MySQL resolves the fare lookup inside the trigger
EXPLAIN SELECT BaseFare
FROM FareRule
WHERE VoyageID        = 1
  AND CabinCategoryID = 1
  AND AgeCategoryID   = 3
ORDER BY EffectiveFrom DESC
LIMIT 1;
```

**What to point out in the EXPLAIN output:**

| Column | Without index | With index |
|--------|---------------|------------|
| `type` | `ALL` (full scan) | `ref` or `range` |
| `rows` | entire FareRule table | 1–3 rows |
| `Extra` | `Using filesort` | `Using index` |

### What to say

> "Every time a passenger is inserted, this trigger runs seven sub-queries.
> Without the index, each query scans the whole FareRule table.
> With the composite index, MySQL seeks directly to the matching voyage,
> cabin, and age category in O(log n) time and reads the rows pre-sorted
> by date — so the ORDER BY LIMIT 1 needs no filesort at all."

---

## Member 2 — Strategy: Selective Denormalization

### What it does
The BEFORE INSERT trigger `TR_PassengerSpecialService_BI_SnapFee`
automatically copies `SpecialService.Fee` into
`PassengerSpecialService.Fee` at the moment of booking.
This freezes the price charged, so historical billing records
are never corrupted by future catalogue price changes.

### Step 1 — Run the trigger

```sql
DELIMITER $$

CREATE TRIGGER TR_PassengerSpecialService_BI_SnapFee
BEFORE INSERT ON PassengerSpecialService
FOR EACH ROW
BEGIN
    DECLARE v_CurrentFee DECIMAL(10,2);

    SELECT Fee
    INTO   v_CurrentFee
    FROM   SpecialService
    WHERE  ServiceID = NEW.ServiceID;

    IF v_CurrentFee IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Referenced SpecialService not found.';
    END IF;

    SET NEW.Fee = v_CurrentFee;
END$$

DELIMITER ;
```

### Step 2 — Verify the trigger exists

```sql
SHOW TRIGGERS WHERE `Table` = 'PassengerSpecialService';
```

Expected output: one row with `Trigger` = `TR_PassengerSpecialService_BI_SnapFee`.

### Step 3 — Demonstrate the benefit (live proof)

**First, check the current catalogue price:**

```sql
SELECT ServiceID, ServiceName, Fee
FROM SpecialService
WHERE ServiceID = 1;
-- Note the Fee value shown, e.g. 50.00
```

**Insert a booking record WITHOUT providing a Fee value:**

```sql
INSERT INTO PassengerSpecialService
    (BookingPassengerID, ServiceID, RequestStatus)
VALUES
    (1, 1, 'Requested');
-- Fee column is deliberately omitted
```

**Read back the inserted row:**

```sql
SELECT PassengerServiceID, BookingPassengerID, ServiceID, Fee, RequestStatus
FROM PassengerSpecialService
ORDER BY PassengerServiceID DESC
LIMIT 1;
```

The `Fee` column will show the value from the catalogue automatically —
the application did not set it.

**Now simulate a price change and show the snapshot is unaffected:**

```sql
UPDATE SpecialService SET Fee = 999.00 WHERE ServiceID = 1;

-- Old booking still shows the original fee
SELECT pss.PassengerServiceID,
       pss.Fee          AS FeePaidAtBooking,
       ss.Fee           AS CurrentCatalogueFee
FROM   PassengerSpecialService pss
INNER JOIN SpecialService ss ON pss.ServiceID = ss.ServiceID
WHERE  pss.ServiceID = 1;
```

The two columns will show **different values** — this is the point.
`FeePaidAtBooking` is locked; `CurrentCatalogueFee` has changed.

**Clean up the price change after the demo:**

```sql
UPDATE SpecialService SET Fee = 50.00 WHERE ServiceID = 1;
-- (replace 50.00 with whatever the original value was)
```

### What to say

> "In a fully normalized design, PassengerSpecialService would only store
> a foreign key to SpecialService and look up the fee at query time.
> But SpecialService.Fee is a live catalogue price — it can be updated
> any time. If we re-derive the fee on every query, historical billing
> reports silently show the wrong amount. This trigger snapshots the
> price at the moment of booking, so the record is immutable.
> This is the same pattern used in BookingCancellation, where
> PenaltyAmount is computed and stored at cancellation time
> rather than being re-derived from CancellationPolicy later."

---

## Member 3 — Strategy: Reporting Views

### What it does
Creates two named views that encapsulate the deep join chains used
repeatedly across reporting queries.

- `vw_BookingPassengerDetails` — 10-table join: full passenger booking
  detail including computed age at departure.
- `vw_VoyageCabinAvailability` — cabin availability per voyage using
  a LEFT JOIN derived table (not a correlated subquery) for efficiency.

### Step 1 — Run the views

```sql
CREATE VIEW vw_BookingPassengerDetails AS
SELECT
    b.BookingID,
    b.BookingDate,
    b.BookingStatus,
    v.VoyageID,
    r.RouteName,
    r.RouteType,
    s.ShipName,
    c.CabinNumber,
    cc.CategoryName                                           AS CabinCategory,
    p.PassengerID,
    p.FullName,
    p.PassportNo,
    fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime)) AS AgeAtDeparture,
    ac.CategoryName                                           AS AgeCategory,
    bp.InfantBedOption,
    bp.IsChaperonedYouth,
    bp.FinalFare
FROM BookingPassenger bp
INNER JOIN Booking       b   ON bp.BookingID      = b.BookingID
INNER JOIN CruiseVoyage  v   ON b.VoyageID        = v.VoyageID
INNER JOIN CruiseRoute   r   ON v.RouteID         = r.RouteID
INNER JOIN CruiseShip    s   ON v.ShipID          = s.ShipID
INNER JOIN BookingCabin  bc  ON bp.BookingCabinID = bc.BookingCabinID
INNER JOIN Cabin         c   ON bc.CabinID        = c.CabinID
INNER JOIN CabinCategory cc  ON c.CabinCategoryID = cc.CabinCategoryID
INNER JOIN Passenger     p   ON bp.PassengerID    = p.PassengerID
INNER JOIN AgeCategory   ac  ON bp.AgeCategoryID  = ac.AgeCategoryID;

CREATE VIEW vw_VoyageCabinAvailability AS
SELECT
    v.VoyageID,
    s.ShipName,
    r.RouteName,
    c.CabinID,
    c.CabinNumber,
    cc.CategoryName AS CabinCategory,
    c.MaxOccupancy,
    CASE
        WHEN active.CabinID IS NOT NULL THEN 'Booked'
        ELSE 'Available'
    END AS AvailabilityStatus
FROM CruiseVoyage   v
INNER JOIN CruiseShip    s  ON v.ShipID          = s.ShipID
INNER JOIN CruiseRoute   r  ON v.RouteID         = r.RouteID
INNER JOIN Cabin         c  ON s.ShipID          = c.ShipID
INNER JOIN CabinCategory cc ON c.CabinCategoryID = cc.CabinCategoryID
LEFT JOIN (
    SELECT bc.CabinID,
           b.VoyageID
    FROM   BookingCabin bc
    INNER JOIN Booking b ON bc.BookingID = b.BookingID
    WHERE  b.BookingStatus IN ('Pending', 'Confirmed')
) active ON active.CabinID  = c.CabinID
        AND active.VoyageID = v.VoyageID;
```

### Step 2 — Verify the views exist

```sql
SHOW FULL TABLES IN GLCL_DB WHERE Table_type = 'VIEW';
```

Both `vw_BookingPassengerDetails` and `vw_VoyageCabinAvailability`
should appear.

### Step 3 — Demonstrate the views working

**Query the passenger detail view — no join needed by the caller:**

```sql
SELECT PassengerID, FullName, AgeCategory, AgeAtDeparture,
       CabinCategory, FinalFare, BookingStatus
FROM   vw_BookingPassengerDetails
WHERE  VoyageID = 1
ORDER BY PassengerID;
```

**Query the availability view with a simple filter:**

```sql
SELECT CabinNumber, CabinCategory, MaxOccupancy, AvailabilityStatus
FROM   vw_VoyageCabinAvailability
WHERE  VoyageID = 1
ORDER BY CabinCategory, CabinNumber;
```

**Show that EXPLAIN still uses Member 1's indexes through the view:**

```sql
EXPLAIN SELECT *
FROM   vw_BookingPassengerDetails
WHERE  VoyageID = 1 AND BookingStatus = 'Confirmed';
```

Point to the `key` column — MySQL pushes the `VoyageID + BookingStatus`
filter into the view and uses `IDX_Booking_Voyage_Status` automatically.

### What to say

> "The most common query in this system joins ten tables: BookingPassenger
> all the way through to Passenger, Cabin, Voyage, Route, and AgeCategory.
> Without a view, every developer must reconstruct that join from scratch
> and risk a missed condition or Cartesian product.
> The view encapsulates the correct join once. MySQL does not materialize
> it — it treats it as an inline subquery — so WHERE filters from the
> outer query are pushed in, and Member 1's composite indexes still apply.
> The availability view replaces a correlated EXISTS sub-select that ran
> once per cabin per voyage with a LEFT JOIN derived table that scans
> active bookings only once, regardless of how many cabins the ship has."

---

## Quick Reference — Verification Commands

```sql
-- Member 1: confirm all 6 indexes
SELECT TABLE_NAME, INDEX_NAME, COLUMN_NAME, SEQ_IN_INDEX
FROM   INFORMATION_SCHEMA.STATISTICS
WHERE  TABLE_SCHEMA = 'GLCL_DB'
  AND  INDEX_NAME LIKE 'IDX_%'
ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX;

-- Member 2: confirm trigger exists
SHOW TRIGGERS WHERE `Table` = 'PassengerSpecialService';

-- Member 3: confirm both views exist
SELECT TABLE_NAME, TABLE_TYPE
FROM   INFORMATION_SCHEMA.TABLES
WHERE  TABLE_SCHEMA = 'GLCL_DB'
  AND  TABLE_TYPE   = 'VIEW';
```

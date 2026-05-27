# GLCL Database — Third Normal Form (3NF) Analysis & Fix

> **MySQL 8+ · Academic Assignment · GLOBAL LUXURY CRUISE LINES**

---

## Overview

This document identifies every 3NF violation found in `GLCL_Database_MySQL_Clean.sql` and provides corrected `CREATE TABLE` statements along with companion views that restore all derived data without storing it redundantly.

---

## What Is 3NF?

A table is in **Third Normal Form (3NF)** when:

1. It is in **1NF** — all values are atomic; no repeating groups.
2. It is in **2NF** — every non-key attribute depends on the **whole** primary key (no partial dependencies).
3. Every non-key attribute depends **directly on the primary key only** — not on another non-key attribute (**no transitive dependencies**).

> **Rule:** If `PK → A → B`, then B violates 3NF because it depends on non-key A rather than directly on the PK.

---

## Tables Already in 3NF (No Changes Required)

| Table | Verdict |
|---|---|
| `CruiseOperator` | ✅ 3NF |
| `CruiseShip` | ✅ 3NF |
| `CabinCategory` | ✅ 3NF |
| `Cabin` | ✅ 3NF |
| `CabinAdjacency` | ✅ 3NF |
| `CruiseRoute` | ✅ 3NF |
| `Port` | ✅ 3NF |
| `RoutePort` | ✅ 3NF |
| `Passenger` | ✅ 3NF |
| `AgeCategory` | ✅ 3NF |
| `BookingCabin` | ✅ 3NF |
| `FareRule` | ✅ 3NF |
| `DiningOption` | ✅ 3NF |
| `ShipDiningOption` | ✅ 3NF |
| `SpecialtyDiningType` | ✅ 3NF |
| `ShipSpecialtyDining` | ✅ 3NF |
| `VoyageMealPackageType` | ✅ 3NF |
| `VoyageMealPackageRule` | ✅ 3NF |
| `VoyageMealPackage` | ✅ 3NF |
| `SpecialService` | ✅ 3NF |
| `BaggageRule` | ✅ 3NF |
| `Excursion` | ✅ 3NF |
| `VoyageExcursion` | ✅ 3NF |
| `BookingExcursion` | ✅ 3NF |
| `CancellationPolicy` | ✅ 3NF |
| `BookingCancellation` | ✅ 3NF |
| `RescheduleRequest` | ✅ 3NF |
| `Payment` | ✅ 3NF |

---

## Tables Violating 3NF — Problems and Fixes

---

### ❌ Table 1: `CruiseVoyage`

#### Problem — `VoyageLengthDays` (Stored Derived Column)

| Attribute | Detail |
|---|---|
| **Offending column** | `VoyageLengthDays` |
| **Dependency chain** | `VoyageID → DepartureDateTime + ArrivalDateTime → VoyageLengthDays` |
| **Violation type** | Transitive dependency through two non-key columns |

**Explanation:**  
`VoyageLengthDays` is calculated as `DATEDIFF(ArrivalDateTime, DepartureDateTime)`. Both `DepartureDateTime` and `ArrivalDateTime` are non-key attributes. Therefore, `VoyageLengthDays` is not determined by `VoyageID` alone — it is determined by two other non-key columns. This is a transitive dependency and violates 3NF.

Even though MySQL uses `GENERATED ALWAYS AS … STORED`, the academic 3NF definition does not distinguish between stored computed columns and manually maintained ones. The redundancy is still present.

#### Fixed Table

```sql
CREATE TABLE CruiseVoyage (
    VoyageID              INT             AUTO_INCREMENT PRIMARY KEY,
    ShipID                INT             NOT NULL,
    RouteID               INT             NOT NULL,
    DepartureDateTime     DATETIME        NOT NULL,
    ArrivalDateTime       DATETIME        NOT NULL,
    -- REMOVED: VoyageLengthDays
    -- Reason: derived from DepartureDateTime and ArrivalDateTime (transitive dependency).
    -- Use vw_VoyageLength or DATEDIFF() in queries instead.
    BaggageWeightLimitKG  DECIMAL(6,2)    NOT NULL,
    VoyageStatus          VARCHAR(30)     NOT NULL DEFAULT 'Scheduled',
    CONSTRAINT FK_CruiseVoyage_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_CruiseVoyage_CruiseRoute
        FOREIGN KEY (RouteID) REFERENCES CruiseRoute(RouteID),
    CONSTRAINT CK_CruiseVoyage_ArrivalAfterDeparture
        CHECK (ArrivalDateTime > DepartureDateTime),
    CONSTRAINT CK_CruiseVoyage_BaggageLimit
        CHECK (BaggageWeightLimitKG > 0),
    CONSTRAINT CK_CruiseVoyage_Status
        CHECK (VoyageStatus IN ('Scheduled', 'Boarding', 'Departed', 'Completed', 'Cancelled'))
);
```

#### Companion View (Replaces the Removed Column)

```sql
CREATE VIEW vw_VoyageLength AS
SELECT
    VoyageID,
    DepartureDateTime,
    ArrivalDateTime,
    DATEDIFF(ArrivalDateTime, DepartureDateTime) AS VoyageLengthDays
FROM CruiseVoyage;
```

---

### ❌ Table 2: `Booking`

#### Problem — `TotalAmount` (Stored Aggregate)

| Attribute | Detail |
|---|---|
| **Offending column** | `TotalAmount` |
| **Dependency chain** | `BookingID → {BookingPassenger rows} → SUM(FinalFare) → TotalAmount` |
| **Violation type** | Derived aggregate — determined by child rows, not directly by PK |

**Explanation:**  
`TotalAmount` is documented as *"the sum of all passenger fares within this booking"*. It is entirely derivable by aggregating `BookingPassenger.FinalFare`. Storing it creates a **redundancy** and an **update anomaly**: if any passenger fare is corrected, `TotalAmount` must also be updated manually or via trigger. In 3NF, no non-key attribute may be derivable from other non-key data in related tables.

#### Fixed Table

```sql
CREATE TABLE Booking (
    BookingID            INT           AUTO_INCREMENT PRIMARY KEY,
    BookingDate          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CustomerPassengerID  INT           NOT NULL,
    VoyageID             INT           NOT NULL,
    BookingStatus        VARCHAR(30)   NOT NULL DEFAULT 'Confirmed',
    -- REMOVED: TotalAmount
    -- Reason: derived aggregate of BookingPassenger.FinalFare (transitive dependency).
    -- Use vw_BookingTotal or a SUM() query instead.
    OriginalBookingID    INT           NULL,
    CONSTRAINT FK_Booking_CustomerPassenger
        FOREIGN KEY (CustomerPassengerID) REFERENCES Passenger(PassengerID),
    CONSTRAINT FK_Booking_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_Booking_OriginalBooking
        FOREIGN KEY (OriginalBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CK_Booking_Status
        CHECK (BookingStatus IN ('Pending', 'Confirmed', 'Waitlisted',
                                 'Cancelled', 'Rescheduled', 'Completed'))
);
```

#### Companion View (Replaces the Removed Column)

```sql
CREATE VIEW vw_BookingTotal AS
SELECT
    b.BookingID,
    b.BookingDate,
    b.CustomerPassengerID,
    b.VoyageID,
    b.BookingStatus,
    COALESCE(SUM(pf.FinalFare), 0) AS TotalAmount
FROM Booking b
LEFT JOIN vw_PassengerFare pf ON b.BookingID = pf.BookingID
GROUP BY
    b.BookingID,
    b.BookingDate,
    b.CustomerPassengerID,
    b.VoyageID,
    b.BookingStatus;
```

---

### ❌ Table 3: `BookingPassenger`

#### Problem A — `FinalFare` (Transitive Dependency via `FareRuleID`)

| Attribute | Detail |
|---|---|
| **Offending column** | `FinalFare` |
| **Dependency chain** | `BookingPassengerID → FareRuleID → FareRule.BaseFare → FinalFare` |
| **Violation type** | Transitive dependency: non-key `FareRuleID` determines `FinalFare` |

**Explanation:**  
For non-infant passengers, the trigger sets `FinalFare = FareRule.BaseFare`. This means `FareRuleID` (a non-key attribute of `BookingPassenger`) functionally determines `FinalFare`. The chain is:

```
BookingPassengerID → FareRuleID → FareRule.BaseFare = FinalFare
```

This is a textbook transitive dependency. The value is already stored in `FareRule.BaseFare` — keeping a copy in `BookingPassenger` violates 3NF.

#### Problem B — `DailySupervisionFee` (Redundant Copy from `SpecialService`)

| Attribute | Detail |
|---|---|
| **Offending column** | `DailySupervisionFee` |
| **Dependency chain** | `BookingPassengerID → IsChaperonedYouth = TRUE → SpecialService.Fee → DailySupervisionFee` |
| **Violation type** | Transitive dependency through non-key `IsChaperonedYouth` and an external table lookup |

**Explanation:**  
`DailySupervisionFee` is copied by the trigger from `SpecialService.Fee WHERE ServiceType = 'Chaperoned Youth'`. The fee already exists in `SpecialService`. Storing a copy here means two places hold the same fact, creating a potential inconsistency if the fee is updated.

#### Fixed Table

```sql
CREATE TABLE BookingPassenger (
    BookingPassengerID  INT          AUTO_INCREMENT PRIMARY KEY,
    BookingID           INT          NOT NULL,
    BookingCabinID      INT          NOT NULL,
    PassengerID         INT          NOT NULL,
    AgeCategoryID       INT          NOT NULL,
    FareRuleID          INT          NULL,   -- kept as FK reference only
    InfantBedOption     VARCHAR(20)  NOT NULL DEFAULT 'NotApplicable',
    IsChaperonedYouth   BOOLEAN      NOT NULL DEFAULT FALSE,
    -- REMOVED: DailySupervisionFee
    -- Reason: redundant copy of SpecialService.Fee for 'Chaperoned Youth'.
    -- Derive via vw_PassengerFare using SpecialService lookup.
    -- REMOVED: FinalFare
    -- Reason: transitively determined by FareRuleID → FareRule.BaseFare.
    -- Derive via vw_PassengerFare instead.
    CONSTRAINT FK_BookingPassenger_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BookingPassenger_BookingCabin
        FOREIGN KEY (BookingCabinID) REFERENCES BookingCabin(BookingCabinID),
    CONSTRAINT FK_BookingPassenger_Passenger
        FOREIGN KEY (PassengerID) REFERENCES Passenger(PassengerID),
    CONSTRAINT FK_BookingPassenger_AgeCategory
        FOREIGN KEY (AgeCategoryID) REFERENCES AgeCategory(AgeCategoryID),
    CONSTRAINT FK_BookingPassenger_FareRule
        FOREIGN KEY (FareRuleID) REFERENCES FareRule(FareRuleID),
    CONSTRAINT CK_BookingPassenger_InfantBedOption
        CHECK (InfantBedOption IN ('SharedBed', 'Cot', 'NotApplicable')),
    CONSTRAINT UQ_BookingPassenger_Booking_Passenger
        UNIQUE (BookingID, PassengerID)
);
```

#### Companion View (Replaces Both Removed Columns)

```sql
CREATE VIEW vw_PassengerFare AS
SELECT
    bp.BookingPassengerID,
    bp.BookingID,
    bp.PassengerID,
    bp.AgeCategoryID,
    bp.FareRuleID,
    bp.InfantBedOption,
    bp.IsChaperonedYouth,

    -- DailySupervisionFee: looked up from SpecialService, not stored
    CASE
        WHEN bp.IsChaperonedYouth = TRUE
        THEN (
            SELECT COALESCE(MAX(ss.Fee), 0)
            FROM SpecialService ss
            WHERE ss.ServiceType = 'Chaperoned Youth'
        )
        ELSE 0.00
    END AS DailySupervisionFee,

    -- FinalFare: computed based on age category and infant option
    CASE
        WHEN ac.CategoryName = 'Infant' AND bp.InfantBedOption = 'SharedBed'
            THEN adult_fr.BaseFare * 0.15

        WHEN ac.CategoryName = 'Infant' AND bp.InfantBedOption = 'Cot'
            THEN child_fr.BaseFare * 0.50

        ELSE
            fr.BaseFare
    END AS FinalFare

FROM BookingPassenger bp
JOIN AgeCategory ac ON bp.AgeCategoryID = ac.AgeCategoryID

-- Non-infant fare rule
LEFT JOIN FareRule fr ON bp.FareRuleID = fr.FareRuleID

-- Adult fare rule (for Infant SharedBed calculation)
LEFT JOIN (
    SELECT
        fr2.VoyageID,
        fr2.CabinCategoryID,
        fr2.BaseFare,
        b2.BookingID
    FROM FareRule fr2
    JOIN AgeCategory  ac2 ON fr2.AgeCategoryID  = ac2.AgeCategoryID
    JOIN Booking      b2  ON b2.VoyageID        = fr2.VoyageID
    WHERE ac2.CategoryName = 'Adult'
) adult_fr ON adult_fr.BookingID = bp.BookingID

-- Child fare rule (for Infant Cot calculation)
LEFT JOIN (
    SELECT
        fr3.VoyageID,
        fr3.CabinCategoryID,
        fr3.BaseFare,
        b3.BookingID
    FROM FareRule fr3
    JOIN AgeCategory  ac3 ON fr3.AgeCategoryID  = ac3.AgeCategoryID
    JOIN Booking      b3  ON b3.VoyageID        = fr3.VoyageID
    WHERE ac3.CategoryName = 'Child'
) child_fr ON child_fr.BookingID = bp.BookingID;
```

---

### ❌ Table 4: `PassengerSpecialService`

#### Problem — `Fee` (Redundant Copy from `SpecialService`)

| Attribute | Detail |
|---|---|
| **Offending column** | `Fee` |
| **Dependency chain** | `PassengerServiceID → ServiceID → SpecialService.Fee` |
| **Violation type** | Transitive dependency: non-key `ServiceID` determines `Fee` |

**Explanation:**  
`SpecialService` already stores the fee for each service type. Repeating `Fee` in `PassengerSpecialService` means the same fact exists in two tables. If `SpecialService.Fee` is ever updated, all `PassengerSpecialService` rows must be updated too — a classic **update anomaly**.

> **Note:** If the intent is to capture the *fee at the time of the service request* (a historical snapshot), the column must be renamed to `AppliedFee` and documented explicitly. As designed with no such documentation, it is a 3NF violation.

#### Fixed Table

```sql
CREATE TABLE PassengerSpecialService (
    PassengerServiceID  INT          AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT          NOT NULL,
    ServiceID           INT          NOT NULL,
    RequestStatus       VARCHAR(30)  NOT NULL DEFAULT 'Requested',
    -- REMOVED: Fee
    -- Reason: ServiceID already determines the fee via SpecialService.Fee (transitive dependency).
    -- Join to SpecialService to retrieve the fee when needed.
    CONSTRAINT FK_PassengerSpecialService_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT FK_PassengerSpecialService_SpecialService
        FOREIGN KEY (ServiceID) REFERENCES SpecialService(ServiceID),
    CONSTRAINT CK_PassengerSpecialService_Status
        CHECK (RequestStatus IN ('Requested', 'Approved', 'Rejected', 'Completed', 'Cancelled')),
    CONSTRAINT UQ_PassengerSpecialService_Passenger_Service
        UNIQUE (BookingPassengerID, ServiceID)
);
```

#### How to Retrieve Service Fee

```sql
-- Join to SpecialService to get the current fee
SELECT
    pss.PassengerServiceID,
    pss.BookingPassengerID,
    ss.ServiceName,
    ss.ServiceType,
    ss.Fee          AS ServiceFee,
    pss.RequestStatus
FROM PassengerSpecialService pss
JOIN SpecialService ss ON pss.ServiceID = ss.ServiceID;
```

---

### ❌ Table 5: `BookingBaggage`

#### Problem — `IsOverLimit` (Stored Derived Boolean)

| Attribute | Detail |
|---|---|
| **Offending column** | `IsOverLimit` |
| **Dependency chain** | `BaggageID → WeightKG + (join chain) → CruiseVoyage.BaggageWeightLimitKG → IsOverLimit` |
| **Violation type** | Derived flag — fully deterministic from `WeightKG` and the voyage limit |

**Explanation:**  
`IsOverLimit` is always `TRUE` when `WeightKG > CruiseVoyage.BaggageWeightLimitKG`, and `FALSE` otherwise. Both `WeightKG` (stored in this table) and `BaggageWeightLimitKG` (stored in `CruiseVoyage`) already exist in the database. The boolean is 100% derivable and storing it creates a redundancy — if the voyage's weight limit changes, every `IsOverLimit` flag would need recalculation.

#### Fixed Table

```sql
CREATE TABLE BookingBaggage (
    BaggageID           INT            AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT            NOT NULL,
    WeightKG            DECIMAL(6,2)   NOT NULL,
    -- REMOVED: IsOverLimit
    -- Reason: derived from WeightKG vs. CruiseVoyage.BaggageWeightLimitKG (transitive dependency).
    -- Use vw_BaggageOverLimit to determine over-limit status.
    ExcessFee           DECIMAL(10,2)  NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingBaggage_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT CK_BookingBaggage_Weight
        CHECK (WeightKG >= 0),
    CONSTRAINT CK_BookingBaggage_ExcessFee
        CHECK (ExcessFee >= 0)
);
```

#### Companion View (Replaces the Removed Column)

```sql
CREATE VIEW vw_BaggageOverLimit AS
SELECT
    bb.BaggageID,
    bb.BookingPassengerID,
    bb.WeightKG,
    v.BaggageWeightLimitKG,
    (bb.WeightKG > v.BaggageWeightLimitKG)     AS IsOverLimit,
    bb.ExcessFee
FROM BookingBaggage    bb
JOIN BookingPassenger  bp ON bb.BookingPassengerID = bp.BookingPassengerID
JOIN Booking           b  ON bp.BookingID          = b.BookingID
JOIN CruiseVoyage      v  ON b.VoyageID            = v.VoyageID;
```

---

## Complete 3NF-Compliant Schema (Affected Tables Only)

The five corrected tables together, ready to paste into a clean MySQL script:

```sql
/* ============================================================
   3NF-CORRECTED TABLES
   All derived, redundant, and transitively dependent columns
   have been removed. Use companion views for derived data.
   ============================================================ */

/* 1. CruiseVoyage — VoyageLengthDays removed */
CREATE TABLE CruiseVoyage (
    VoyageID              INT           AUTO_INCREMENT PRIMARY KEY,
    ShipID                INT           NOT NULL,
    RouteID               INT           NOT NULL,
    DepartureDateTime     DATETIME      NOT NULL,
    ArrivalDateTime       DATETIME      NOT NULL,
    BaggageWeightLimitKG  DECIMAL(6,2)  NOT NULL,
    VoyageStatus          VARCHAR(30)   NOT NULL DEFAULT 'Scheduled',
    CONSTRAINT FK_CruiseVoyage_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_CruiseVoyage_CruiseRoute
        FOREIGN KEY (RouteID) REFERENCES CruiseRoute(RouteID),
    CONSTRAINT CK_CruiseVoyage_ArrivalAfterDeparture
        CHECK (ArrivalDateTime > DepartureDateTime),
    CONSTRAINT CK_CruiseVoyage_BaggageLimit
        CHECK (BaggageWeightLimitKG > 0),
    CONSTRAINT CK_CruiseVoyage_Status
        CHECK (VoyageStatus IN ('Scheduled', 'Boarding', 'Departed', 'Completed', 'Cancelled'))
);

/* 2. Booking — TotalAmount removed */
CREATE TABLE Booking (
    BookingID            INT          AUTO_INCREMENT PRIMARY KEY,
    BookingDate          DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CustomerPassengerID  INT          NOT NULL,
    VoyageID             INT          NOT NULL,
    BookingStatus        VARCHAR(30)  NOT NULL DEFAULT 'Confirmed',
    OriginalBookingID    INT          NULL,
    CONSTRAINT FK_Booking_CustomerPassenger
        FOREIGN KEY (CustomerPassengerID) REFERENCES Passenger(PassengerID),
    CONSTRAINT FK_Booking_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_Booking_OriginalBooking
        FOREIGN KEY (OriginalBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CK_Booking_Status
        CHECK (BookingStatus IN ('Pending', 'Confirmed', 'Waitlisted',
                                 'Cancelled', 'Rescheduled', 'Completed'))
);

/* 3. BookingPassenger — FinalFare and DailySupervisionFee removed */
CREATE TABLE BookingPassenger (
    BookingPassengerID  INT          AUTO_INCREMENT PRIMARY KEY,
    BookingID           INT          NOT NULL,
    BookingCabinID      INT          NOT NULL,
    PassengerID         INT          NOT NULL,
    AgeCategoryID       INT          NOT NULL,
    FareRuleID          INT          NULL,
    InfantBedOption     VARCHAR(20)  NOT NULL DEFAULT 'NotApplicable',
    IsChaperonedYouth   BOOLEAN      NOT NULL DEFAULT FALSE,
    CONSTRAINT FK_BookingPassenger_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BookingPassenger_BookingCabin
        FOREIGN KEY (BookingCabinID) REFERENCES BookingCabin(BookingCabinID),
    CONSTRAINT FK_BookingPassenger_Passenger
        FOREIGN KEY (PassengerID) REFERENCES Passenger(PassengerID),
    CONSTRAINT FK_BookingPassenger_AgeCategory
        FOREIGN KEY (AgeCategoryID) REFERENCES AgeCategory(AgeCategoryID),
    CONSTRAINT FK_BookingPassenger_FareRule
        FOREIGN KEY (FareRuleID) REFERENCES FareRule(FareRuleID),
    CONSTRAINT CK_BookingPassenger_InfantBedOption
        CHECK (InfantBedOption IN ('SharedBed', 'Cot', 'NotApplicable')),
    CONSTRAINT UQ_BookingPassenger_Booking_Passenger
        UNIQUE (BookingID, PassengerID)
);

/* 4. PassengerSpecialService — Fee removed */
CREATE TABLE PassengerSpecialService (
    PassengerServiceID  INT          AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT          NOT NULL,
    ServiceID           INT          NOT NULL,
    RequestStatus       VARCHAR(30)  NOT NULL DEFAULT 'Requested',
    CONSTRAINT FK_PassengerSpecialService_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT FK_PassengerSpecialService_SpecialService
        FOREIGN KEY (ServiceID) REFERENCES SpecialService(ServiceID),
    CONSTRAINT CK_PassengerSpecialService_Status
        CHECK (RequestStatus IN ('Requested', 'Approved', 'Rejected', 'Completed', 'Cancelled')),
    CONSTRAINT UQ_PassengerSpecialService_Passenger_Service
        UNIQUE (BookingPassengerID, ServiceID)
);

/* 5. BookingBaggage — IsOverLimit removed */
CREATE TABLE BookingBaggage (
    BaggageID           INT            AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT            NOT NULL,
    WeightKG            DECIMAL(6,2)   NOT NULL,
    ExcessFee           DECIMAL(10,2)  NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingBaggage_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT CK_BookingBaggage_Weight
        CHECK (WeightKG >= 0),
    CONSTRAINT CK_BookingBaggage_ExcessFee
        CHECK (ExcessFee >= 0)
);

/* ============================================================
   COMPANION VIEWS (replace removed derived columns)
   ============================================================ */

/* Voyage length — replaces CruiseVoyage.VoyageLengthDays */
CREATE VIEW vw_VoyageLength AS
SELECT
    VoyageID,
    DepartureDateTime,
    ArrivalDateTime,
    DATEDIFF(ArrivalDateTime, DepartureDateTime) AS VoyageLengthDays
FROM CruiseVoyage;

/* Passenger fare and supervision fee — replaces BookingPassenger.FinalFare
   and BookingPassenger.DailySupervisionFee */
CREATE VIEW vw_PassengerFare AS
SELECT
    bp.BookingPassengerID,
    bp.BookingID,
    bp.PassengerID,
    ac.CategoryName                                         AS AgeCategory,
    bp.InfantBedOption,
    bp.IsChaperonedYouth,

    CASE
        WHEN bp.IsChaperonedYouth = TRUE
        THEN (SELECT COALESCE(MAX(ss.Fee), 0)
              FROM SpecialService ss
              WHERE ss.ServiceType = 'Chaperoned Youth')
        ELSE 0.00
    END                                                     AS DailySupervisionFee,

    CASE
        WHEN ac.CategoryName = 'Infant' AND bp.InfantBedOption = 'SharedBed'
            THEN adult_fr.BaseFare * 0.15
        WHEN ac.CategoryName = 'Infant' AND bp.InfantBedOption = 'Cot'
            THEN child_fr.BaseFare * 0.50
        ELSE
            fr.BaseFare
    END                                                     AS FinalFare

FROM BookingPassenger bp
JOIN AgeCategory ac ON bp.AgeCategoryID = ac.AgeCategoryID
LEFT JOIN FareRule fr ON bp.FareRuleID = fr.FareRuleID
LEFT JOIN (
    SELECT fr2.VoyageID, fr2.CabinCategoryID, fr2.BaseFare, b2.BookingID
    FROM FareRule fr2
    JOIN AgeCategory ac2 ON fr2.AgeCategoryID = ac2.AgeCategoryID
    JOIN Booking     b2  ON b2.VoyageID       = fr2.VoyageID
    WHERE ac2.CategoryName = 'Adult'
) adult_fr ON adult_fr.BookingID = bp.BookingID
LEFT JOIN (
    SELECT fr3.VoyageID, fr3.CabinCategoryID, fr3.BaseFare, b3.BookingID
    FROM FareRule fr3
    JOIN AgeCategory ac3 ON fr3.AgeCategoryID = ac3.AgeCategoryID
    JOIN Booking     b3  ON b3.VoyageID       = fr3.VoyageID
    WHERE ac3.CategoryName = 'Child'
) child_fr ON child_fr.BookingID = bp.BookingID;

/* Booking total — replaces Booking.TotalAmount */
CREATE VIEW vw_BookingTotal AS
SELECT
    b.BookingID,
    b.BookingDate,
    b.CustomerPassengerID,
    b.VoyageID,
    b.BookingStatus,
    COALESCE(SUM(pf.FinalFare), 0) AS TotalAmount
FROM Booking b
LEFT JOIN vw_PassengerFare pf ON b.BookingID = pf.BookingID
GROUP BY
    b.BookingID,
    b.BookingDate,
    b.CustomerPassengerID,
    b.VoyageID,
    b.BookingStatus;

/* Baggage over-limit — replaces BookingBaggage.IsOverLimit */
CREATE VIEW vw_BaggageOverLimit AS
SELECT
    bb.BaggageID,
    bb.BookingPassengerID,
    bb.WeightKG,
    v.BaggageWeightLimitKG,
    (bb.WeightKG > v.BaggageWeightLimitKG) AS IsOverLimit,
    bb.ExcessFee
FROM BookingBaggage   bb
JOIN BookingPassenger bp ON bb.BookingPassengerID = bp.BookingPassengerID
JOIN Booking          b  ON bp.BookingID          = b.BookingID
JOIN CruiseVoyage     v  ON b.VoyageID            = v.VoyageID;
```

---

## Summary of All Changes

| Table | Column Removed | Reason | Replacement |
|---|---|---|---|
| `CruiseVoyage` | `VoyageLengthDays` | Derived from `DepartureDateTime` + `ArrivalDateTime` | `vw_VoyageLength` |
| `Booking` | `TotalAmount` | Aggregate of `BookingPassenger.FinalFare` | `vw_BookingTotal` |
| `BookingPassenger` | `FinalFare` | Transitively determined by `FareRuleID → BaseFare` | `vw_PassengerFare` |
| `BookingPassenger` | `DailySupervisionFee` | Redundant copy of `SpecialService.Fee` | `vw_PassengerFare` |
| `PassengerSpecialService` | `Fee` | Transitively determined by `ServiceID → SpecialService.Fee` | Direct join to `SpecialService` |
| `BookingBaggage` | `IsOverLimit` | Derived Boolean from `WeightKG` vs voyage limit | `vw_BaggageOverLimit` |

---

*Document prepared for GLCL Academic Database Assignment — MySQL 8+*

# GLCL Database — Optimization Strategy, Constraints & Triggers

> **MySQL 8+ · Academic Assignment · GLOBAL LUXURY CRUISE LINES**

---

## Part (b) — Optimization Strategy

> *"Document and provide a written description and justification of your optimization strategy. Each group member is required to produce one optimization strategy."*
> **(10 marks)**

---

### Strategy 1 — Composite Indexing on Frequently Joined and Filtered Columns

#### Description

The most computationally expensive operations in the GLCL database are the booking and reporting queries, which involve multi-table joins across `BookingPassenger`, `Booking`, `CruiseVoyage`, `Cabin`, and `FareRule`. Without indexes on foreign key columns and common filter predicates, MySQL must perform full table scans on every join, which degrades significantly as booking volume grows.

The optimization strategy is to create **composite indexes** on the combinations of columns that are most commonly used together in `WHERE` clauses, `JOIN` conditions, and `ORDER BY` clauses — going beyond the single-column indexes MySQL automatically creates for primary keys.

#### Indexes Implemented

```sql
-- 1. FareRule — the most-queried lookup during fare calculation.
--    Queries filter by (VoyageID, CabinCategoryID, AgeCategoryID) and
--    then sort by EffectiveFrom DESC to find the most current rule.
CREATE INDEX IDX_FareRule_Voyage_Cabin_Age_Date
    ON FareRule (VoyageID, CabinCategoryID, AgeCategoryID, EffectiveFrom DESC);

-- 2. BookingPassenger — supports occupancy checks (JOIN + WHERE BookingCabinID)
--    and passenger lookups within a booking (JOIN + WHERE BookingID).
CREATE INDEX IDX_BookingPassenger_BookingCabin
    ON BookingPassenger (BookingCabinID, BookingID);

-- 3. BookingCabin — supports double-booking prevention trigger and
--    voyage-level cabin availability queries.
CREATE INDEX IDX_BookingCabin_Cabin_Booking
    ON BookingCabin (CabinID, BookingID);

-- 4. Booking — supports filtering by VoyageID (voyage manifests)
--    and BookingStatus (active booking queries).
CREATE INDEX IDX_Booking_Voyage_Status
    ON Booking (VoyageID, BookingStatus);

-- 5. CancellationPolicy — used by the cancellation trigger to look up
--    the applicable policy by OperatorID and HoursBeforeDeparture.
CREATE INDEX IDX_CancellationPolicy_Operator_Hours
    ON CancellationPolicy (OperatorID, HoursBeforeDeparture ASC);

-- 6. BaggageRule — used to look up active baggage limits by operator
--    and effective date range.
CREATE INDEX IDX_BaggageRule_Operator_Date
    ON BaggageRule (OperatorID, EffectiveFrom, EffectiveTo);

-- 7. VoyageExcursion — supports excursion availability and slot queries
--    grouped by voyage and route port stop.
CREATE INDEX IDX_VoyageExcursion_Voyage_RoutePort
    ON VoyageExcursion (VoyageID, RoutePortID);

-- 8. RoutePort — supports route itinerary lookups in stop order.
CREATE INDEX IDX_RoutePort_Route_Sequence
    ON RoutePort (RouteID, StopSequence ASC);
```

#### Justification

| Index | Why It Is Needed |
|---|---|
| `IDX_FareRule_Voyage_Cabin_Age_Date` | The fare calculation trigger runs on every `INSERT` and `UPDATE` to `BookingPassenger`. Without this index, each trigger execution scans the entire `FareRule` table. With it, MySQL resolves the correct fare rule in O(log n) time. |
| `IDX_BookingPassenger_BookingCabin` | The cabin occupancy check counts passengers per cabin (`WHERE BookingCabinID = X`). Without the index, this is a full scan of `BookingPassenger` per insert. |
| `IDX_BookingCabin_Cabin_Booking` | The double-booking trigger checks whether a cabin is already booked for the same voyage. This index makes the existence check a fast index seek instead of a full table scan. |
| `IDX_Booking_Voyage_Status` | Voyage manifest and availability reports filter `Booking` by `VoyageID` and `BookingStatus`. A composite index covering both eliminates two separate single-column scans. |
| `IDX_CancellationPolicy_Operator_Hours` | The cancellation trigger selects the most applicable policy row with `ORDER BY HoursBeforeDeparture ASC LIMIT 1`. Without an index, MySQL sorts the entire policy table per cancellation. |
| `IDX_BaggageRule_Operator_Date` | Baggage limit lookups filter on `OperatorID` and a date range. The composite index makes range scans on `EffectiveFrom`/`EffectiveTo` significantly faster. |
| `IDX_VoyageExcursion_Voyage_RoutePort` | Excursion availability queries group and filter by voyage and port stop. The composite index supports both the filter and the potential sort without a filesort. |
| `IDX_RoutePort_Route_Sequence` | Itinerary display queries retrieve all stops for a route in stop sequence order. The index makes both the filter (`RouteID`) and the sort (`StopSequence`) index-covered operations. |

#### Trade-Off Acknowledgement

Indexes increase storage space and add a small overhead to `INSERT`, `UPDATE`, and `DELETE` operations because the index structure must be maintained. In the GLCL context, this trade-off is justified because:

1. **Read operations vastly outnumber writes.** A booking system is queried for availability, fares, manifests, and reports far more frequently than records are inserted or updated.
2. **Triggers already perform reads on every write.** The fare calculation and double-booking triggers read `FareRule`, `BookingPassenger`, and `Booking` on every insert. These reads benefit the most from indexing.
3. **Academic data volumes are small**, but the indexing strategy correctly anticipates real-world scaling where these tables can grow to millions of rows.

---

### Strategy 2 — Selective Denormalization with Justification (Historical Price Snapshot)

#### Description

In the `PassengerSpecialService` table, a `Fee` column was removed during 3NF normalization because it was deemed transitively dependent on `ServiceID → SpecialService.Fee`. However, a deliberate **selective denormalization** is justified for auditing and legal purposes: the fee that was actually applied to a passenger at the time of their service request should be recorded independently of any future changes to `SpecialService.Fee`.

This is the distinction between *current price* (stored in `SpecialService`) and *applied price at the time of booking* (which must be captured as an independent fact for financial audit trails).

#### Implementation

```sql
-- Re-introduce AppliedFee as a documented, justified denormalization
-- It is NOT a redundant copy — it captures a point-in-time historical fact.
ALTER TABLE PassengerSpecialService
    ADD COLUMN AppliedFee DECIMAL(10,2) NOT NULL DEFAULT 0
        COMMENT 'Fee charged at the time of the service request. 
                 Retained independently of SpecialService.Fee 
                 for audit trail and financial reporting purposes. 
                 Justified denormalization: historical price snapshot.';
```

A trigger populates `AppliedFee` automatically from `SpecialService.Fee` at the moment of booking:

```sql
DELIMITER $$
CREATE TRIGGER TR_PassengerSpecialService_BI_SetAppliedFee
BEFORE INSERT ON PassengerSpecialService
FOR EACH ROW
BEGIN
    SELECT COALESCE(Fee, 0)
    INTO   NEW.AppliedFee
    FROM   SpecialService
    WHERE  ServiceID = NEW.ServiceID;
END$$
DELIMITER ;
```

#### Justification

| Concern | Explanation |
|---|---|
| **Why denormalize?** | Financial systems must preserve the exact amount charged to a customer at the time of transaction. `SpecialService.Fee` is a current price list — it may change. Recording only the FK means historical booking reports will show incorrect (current) fees instead of the fee actually paid. |
| **Why is this not a 3NF violation?** | A pure 3NF copy of `SpecialService.Fee` would always mirror the current value. `AppliedFee` is a different fact — the fee at a specific point in time — making it functionally dependent on `PassengerServiceID` (the event record), not solely on `ServiceID`. The two attributes describe different things. |
| **Is this justified in the assignment context?** | Yes. The assignment states: *"Data must be in 3NF or higher unless it has been denormalized for performance reasons, in which case a detailed explanation must be given."* Audit trail preservation is a stronger justification than performance alone. |
| **Precedent in the original schema** | The original schema's `CancellationPolicy`-triggered `PenaltyAmount` and `RefundAmount` in `BookingCancellation` follow the same pattern — computed and stored at event time for historical accuracy, not re-derived dynamically. This strategy is consistent with that design decision. |

---

### Strategy 3 — Use of Reporting Views to Avoid Repeated Complex Joins

#### Description

The GLCL schema involves deep join chains that are repeatedly needed across different queries (e.g., `BookingPassenger → Booking → CruiseVoyage → CruiseShip → CruiseOperator`). Repeating these joins in ad-hoc queries is error-prone and inefficient. The strategy is to encapsulate frequently needed join paths into **named views**, which both optimize development time and allow MySQL's query optimizer to apply caching and materialization strategies.

#### Views Implemented

```sql
-- Full passenger booking detail (used in reservation reports and manifests)
CREATE VIEW vw_BookingPassengerDetails AS
SELECT
    b.BookingID,
    b.BookingDate,
    b.BookingStatus,
    v.VoyageID,
    r.RouteName,
    r.RouteType,
    s.ShipName,
    co.OperatorName,
    c.CabinNumber,
    cc.CategoryName                                                 AS CabinCategory,
    p.PassengerID,
    p.FullName,
    p.PassportNo,
    fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime))       AS AgeAtDeparture,
    ac.CategoryName                                                 AS AgeCategory,
    bp.InfantBedOption,
    bp.IsChaperonedYouth
FROM BookingPassenger  bp
JOIN Booking           b   ON bp.BookingID      = b.BookingID
JOIN CruiseVoyage      v   ON b.VoyageID        = v.VoyageID
JOIN CruiseRoute       r   ON v.RouteID         = r.RouteID
JOIN CruiseShip        s   ON v.ShipID          = s.ShipID
JOIN CruiseOperator    co  ON s.OperatorID      = co.OperatorID
JOIN BookingCabin      bc  ON bp.BookingCabinID = bc.BookingCabinID
JOIN Cabin             c   ON bc.CabinID        = c.CabinID
JOIN CabinCategory     cc  ON c.CabinCategoryID = cc.CabinCategoryID
JOIN Passenger         p   ON bp.PassengerID    = p.PassengerID
JOIN AgeCategory       ac  ON bp.AgeCategoryID  = ac.AgeCategoryID;

-- Cabin availability per voyage
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
        WHEN EXISTS (
            SELECT 1
            FROM BookingCabin bc
            JOIN Booking b2 ON bc.BookingID = b2.BookingID
            WHERE b2.VoyageID = v.VoyageID
              AND bc.CabinID  = c.CabinID
              AND b2.BookingStatus IN ('Pending', 'Confirmed')
        ) THEN 'Booked'
        ELSE 'Available'
    END AS AvailabilityStatus
FROM CruiseVoyage   v
JOIN CruiseShip     s  ON v.ShipID          = s.ShipID
JOIN CruiseRoute    r  ON v.RouteID         = r.RouteID
JOIN Cabin          c  ON s.ShipID          = c.ShipID
JOIN CabinCategory  cc ON c.CabinCategoryID = cc.CabinCategoryID;
```

#### Justification

Views encapsulate complexity without materializing data. Every query that uses `vw_BookingPassengerDetails` benefits from a single, tested, optimized join path rather than each developer writing their own. MySQL's optimizer treats views as subquery definitions and can apply index usage, predicate pushdown, and join reordering automatically. This reduces both development effort and the risk of cartesian products or missing join conditions in ad-hoc queries.

---

## Part (c) — Constraints and Triggers

> *"Document all the constraints included in your system and justify and explain the constraints used and the ways in which they support the business rules. Provide a functional description of all the triggers. Each group member is required to design one constraint and trigger."*
> **(10 marks)**

---

## Section C1 — Constraints Documentation

### Constraint Types Used

| Type | Keyword | Purpose |
|---|---|---|
| Primary Key | `PRIMARY KEY` / `PK_` | Uniquely identifies every row |
| Foreign Key | `FOREIGN KEY` / `FK_` | Enforces referential integrity between tables |
| Check | `CHECK` / `CK_` | Enforces domain rules on column values |
| Unique | `UNIQUE` / `UQ_` | Prevents duplicate combinations of values |
| Not Null | `NOT NULL` | Ensures mandatory fields are always provided |

---

### Primary Key Constraints

All tables use `INT AUTO_INCREMENT PRIMARY KEY`, ensuring every row has a unique system-generated identifier. This supports referential integrity across all foreign key relationships and guarantees that no two records for the same entity can be confused.

---

### Foreign Key Constraints — Full List

| Constraint Name | Child Table | Parent Table | Business Rule Supported |
|---|---|---|---|
| `FK_CruiseShip_CruiseOperator` | `CruiseShip` | `CruiseOperator` | A ship must belong to a registered operator |
| `FK_Cabin_CruiseShip` | `Cabin` | `CruiseShip` | A cabin must exist on a known ship |
| `FK_Cabin_CabinCategory` | `Cabin` | `CabinCategory` | Cabin type must be one of the four permitted categories |
| `FK_CabinAdjacency_Cabin` | `CabinAdjacency` | `Cabin` | Adjacency records must reference real cabins |
| `FK_CabinAdjacency_AdjacentCabin` | `CabinAdjacency` | `Cabin` | Adjacent cabin must also be a real cabin |
| `FK_RoutePort_CruiseRoute` | `RoutePort` | `CruiseRoute` | A port stop must belong to a defined route |
| `FK_RoutePort_Port` | `RoutePort` | `Port` | A stop must reference a registered port |
| `FK_CruiseVoyage_CruiseShip` | `CruiseVoyage` | `CruiseShip` | A voyage must be operated by a real ship |
| `FK_CruiseVoyage_CruiseRoute` | `CruiseVoyage` | `CruiseRoute` | A voyage must follow a defined route |
| `FK_Booking_CustomerPassenger` | `Booking` | `Passenger` | The person who made the booking must be a registered passenger |
| `FK_Booking_CruiseVoyage` | `Booking` | `CruiseVoyage` | A booking must reference a real voyage |
| `FK_Booking_OriginalBooking` | `Booking` | `Booking` | Rescheduled bookings trace back to the original booking |
| `FK_BookingCabin_Booking` | `BookingCabin` | `Booking` | A cabin assignment must belong to a booking |
| `FK_BookingCabin_Cabin` | `BookingCabin` | `Cabin` | The assigned cabin must exist |
| `FK_FareRule_CruiseVoyage` | `FareRule` | `CruiseVoyage` | Fares apply to a specific voyage |
| `FK_FareRule_CabinCategory` | `FareRule` | `CabinCategory` | Fares are defined per cabin category |
| `FK_FareRule_AgeCategory` | `FareRule` | `AgeCategory` | Fares are defined per age band |
| `FK_BookingPassenger_Booking` | `BookingPassenger` | `Booking` | Passenger assignment must belong to a booking |
| `FK_BookingPassenger_BookingCabin` | `BookingPassenger` | `BookingCabin` | Passenger must be placed in a booked cabin |
| `FK_BookingPassenger_Passenger` | `BookingPassenger` | `Passenger` | Only registered passengers can be booked |
| `FK_BookingPassenger_AgeCategory` | `BookingPassenger` | `AgeCategory` | Age category must be one of the defined bands |
| `FK_BookingPassenger_FareRule` | `BookingPassenger` | `FareRule` | Non-infant fares must reference a valid fare rule |
| `FK_ShipDiningOption_CruiseShip` | `ShipDiningOption` | `CruiseShip` | Dining option is assigned to a real ship |
| `FK_ShipDiningOption_DiningOption` | `ShipDiningOption` | `DiningOption` | Only the three permitted dining types are assigned |
| `FK_ShipSpecialtyDining_CruiseShip` | `ShipSpecialtyDining` | `CruiseShip` | Specialty dining is offered on a real ship |
| `FK_ShipSpecialtyDining_SpecialtyDiningType` | `ShipSpecialtyDining` | `SpecialtyDiningType` | Only registered cuisine types are offered |
| `FK_VoyageMealPackage_CruiseVoyage` | `VoyageMealPackage` | `CruiseVoyage` | Meal package is linked to a real voyage |
| `FK_VoyageMealPackage_VoyageMealPackageRule` | `VoyageMealPackage` | `VoyageMealPackageRule` | Meal package type must match a defined rule |
| `FK_VoyageMealPackageRule_VoyageMealPackageType` | `VoyageMealPackageRule` | `VoyageMealPackageType` | Rule must reference a valid package type |
| `FK_PassengerSpecialService_BookingPassenger` | `PassengerSpecialService` | `BookingPassenger` | Service is requested by a booked passenger |
| `FK_PassengerSpecialService_SpecialService` | `PassengerSpecialService` | `SpecialService` | Service must be a defined service type |
| `FK_BaggageRule_CruiseOperator` | `BaggageRule` | `CruiseOperator` | Baggage rules belong to a specific operator |
| `FK_BookingBaggage_BookingPassenger` | `BookingBaggage` | `BookingPassenger` | Baggage record belongs to a booked passenger |
| `FK_Excursion_Port` | `Excursion` | `Port` | An excursion is offered at a real port |
| `FK_VoyageExcursion_CruiseVoyage` | `VoyageExcursion` | `CruiseVoyage` | Excursion availability is tied to a voyage |
| `FK_VoyageExcursion_RoutePort` | `VoyageExcursion` | `RoutePort` | Excursion is available at a specific route stop |
| `FK_VoyageExcursion_Excursion` | `VoyageExcursion` | `Excursion` | Must reference a defined excursion |
| `FK_CancellationPolicy_CruiseOperator` | `CancellationPolicy` | `CruiseOperator` | Cancellation rules belong to an operator |
| `FK_BookingCancellation_Booking` | `BookingCancellation` | `Booking` | A cancellation is linked to one booking |
| `FK_RescheduleRequest_OriginalBooking` | `RescheduleRequest` | `Booking` | Reschedule refers to the original booking |
| `FK_RescheduleRequest_NewBooking` | `RescheduleRequest` | `Booking` | Links to the new booking once approved |
| `FK_RescheduleRequest_NewVoyage` | `RescheduleRequest` | `CruiseVoyage` | The new voyage must be a valid voyage |
| `FK_Payment_Booking` | `Payment` | `Booking` | Payments must be linked to an existing booking |

---

### CHECK Constraints — Full List with Justification

#### `CruiseShip`

```sql
CONSTRAINT CK_CruiseShip_TotalDecks      CHECK (TotalDecks > 0)
CONSTRAINT CK_CruiseShip_PassengerCapacity CHECK (PassengerCapacity > 0)
```
**Justification:** A ship with zero or negative decks or capacity is physically impossible. These constraints prevent data entry errors that would corrupt capacity calculations.

---

#### `CabinCategory`

```sql
CONSTRAINT CK_CabinCategory_CategoryName
    CHECK (CategoryName IN ('Interior', 'Ocean View', 'Balcony', 'Suite'))
```
**Justification:** GLCL permits exactly four cabin types. Enforcing this at the database level guarantees that no unsupported category can enter the system, regardless of the application layer.

---

#### `Cabin`

```sql
CONSTRAINT CK_Cabin_MaxOccupancy CHECK (MaxOccupancy BETWEEN 1 AND 5)
CONSTRAINT CK_Cabin_DeckNumber   CHECK (DeckNumber > 0)
```
**Justification:** The business rule states a strict maximum of 5 passengers per cabin. Constraining `MaxOccupancy` to `1–5` enforces this at the storage level — even a direct SQL `INSERT` bypassing the application will be rejected. `DeckNumber > 0` prevents physically nonsensical values.

---

#### `CabinAdjacency`

```sql
CONSTRAINT CK_CabinAdjacency_Type    CHECK (AdjacencyType IN ('Adjacent', 'Connecting'))
CONSTRAINT CK_CabinAdjacency_NotSelf CHECK (CabinID <> AdjacentCabinID)
```
**Justification:** A cabin cannot be adjacent to itself — this would create a logical contradiction in guardian validation. Only two adjacency types are defined in the business domain; restricting to these prevents invalid classifications.

---

#### `CruiseRoute`

```sql
CONSTRAINT CK_CruiseRoute_RouteType
    CHECK (RouteType IN ('One-way', 'Round-trip', 'Multi-destination'))
```
**Justification:** GLCL offers exactly three itinerary types. This constraint ensures all route type queries return consistent, predictable results.

---

#### `CruiseVoyage`

```sql
CONSTRAINT CK_CruiseVoyage_ArrivalAfterDeparture CHECK (ArrivalDateTime > DepartureDateTime)
CONSTRAINT CK_CruiseVoyage_BaggageLimit           CHECK (BaggageWeightLimitKG > 0)
CONSTRAINT CK_CruiseVoyage_Status
    CHECK (VoyageStatus IN ('Scheduled', 'Boarding', 'Departed', 'Completed', 'Cancelled'))
```
**Justification:** It is physically impossible for a ship to arrive before it departs. This constraint prevents chronological data errors that would make duration calculations negative. The baggage limit and status domain constraints ensure data consistency for the baggage trigger and voyage reporting queries.

---

#### `AgeCategory`

```sql
CONSTRAINT CK_AgeCategory_AgeRange
    CHECK (MinAge >= 0 AND (MaxAge IS NULL OR MaxAge >= MinAge))
```
**Justification:** Age ranges must be logically valid. A `MaxAge` below `MinAge` would create an empty category and cause fare lookups to silently fail. `MinAge >= 0` prevents negative ages.

---

#### `Booking`

```sql
CONSTRAINT CK_Booking_Status
    CHECK (BookingStatus IN ('Pending', 'Confirmed', 'Waitlisted',
                              'Cancelled', 'Rescheduled', 'Completed'))
```
**Justification:** Booking status drives business logic — cancellation policies, trigger conditions, and reporting filters all depend on specific status values. Restricting to the defined set prevents states that the system cannot handle.

---

#### `BookingCabin`

```sql
CONSTRAINT CK_BookingCabin_CabinPrice CHECK (CabinPrice >= 0)
```
**Justification:** A negative cabin price is not a valid business value. This prevents accidental negative-price records from distorting revenue reports.

---

#### `FareRule`

```sql
CONSTRAINT CK_FareRule_BaseFare      CHECK (BaseFare >= 0)
CONSTRAINT CK_FareRule_EffectiveDate CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
```
**Justification:** Fares cannot be negative. An `EffectiveTo` before `EffectiveFrom` would create a zero-duration fare rule that could never apply, causing fare lookups to silently return no result.

---

#### `BookingPassenger`

```sql
CONSTRAINT CK_BookingPassenger_InfantBedOption
    CHECK (InfantBedOption IN ('SharedBed', 'Cot', 'NotApplicable'))
```
**Justification:** The infant pricing formula is determined entirely by `InfantBedOption`. Allowing arbitrary values here would break the trigger's fare calculation. Only the three defined options are valid: two for infants and one for all other passengers.

---

#### `SpecialService`

```sql
CONSTRAINT CK_SpecialService_ServiceType
    CHECK (ServiceType IN ('Childcare', 'Teen Club', 'Accessibility', 'Mobility', 'Chaperoned Youth'))
CONSTRAINT CK_SpecialService_AgeRestriction
    CHECK (
        (AgeRestrictionMin IS NULL AND AgeRestrictionMax IS NULL)
        OR
        (AgeRestrictionMin IS NOT NULL AND AgeRestrictionMax IS NOT NULL
         AND AgeRestrictionMax >= AgeRestrictionMin)
    )
CONSTRAINT CK_SpecialService_Fee CHECK (Fee >= 0)
```
**Justification:** Service type must match one of the five GLCL-defined categories. The age restriction rule enforces that either both bounds are defined or neither is — partial age restrictions (only min or only max) would make age eligibility checks ambiguous. The fee constraint prevents negative charges.

---

#### `CancellationPolicy`

```sql
CONSTRAINT CK_CancellationPolicy_Hours        CHECK (HoursBeforeDeparture >= 0)
CONSTRAINT CK_CancellationPolicy_PenaltyType
    CHECK (PenaltyType IN ('Percentage', 'FixedAmount', 'FullForfeit'))
CONSTRAINT CK_CancellationPolicy_PenaltyValue CHECK (PenaltyValue >= 0)
```
**Justification:** The three penalty types map directly to the three calculation branches in the cancellation trigger. Any other string would cause the trigger to fall through to a null match and grant a full refund incorrectly. `HoursBeforeDeparture >= 0` ensures the policy threshold is non-negative.

---

#### `BookingCancellation`

```sql
CONSTRAINT CK_BookingCancellation_Amounts
    CHECK (PenaltyAmount >= 0 AND RefundAmount >= 0)
```
**Justification:** Both penalty and refund amounts must be non-negative. A negative penalty or refund would indicate a data corruption issue and could cause incorrect financial calculations.

---

#### `Payment`

```sql
CONSTRAINT CK_Payment_Amount CHECK (Amount > 0)
CONSTRAINT CK_Payment_Status
    CHECK (PaymentStatus IN ('Pending', 'Paid', 'Failed', 'Refunded', 'Partially Refunded'))
```
**Justification:** A payment of zero or less is not a valid transaction. Payment status must match one of the five defined states to ensure the payment lifecycle is correctly tracked.

---

### UNIQUE Constraints — Full List with Justification

| Constraint | Table | Columns | Business Rule |
|---|---|---|---|
| `UQ_CruiseShip_Operator_ShipName` | `CruiseShip` | `(OperatorID, ShipName)` | Two ships of the same operator cannot share a name |
| `UQ_Cabin_Ship_CabinNumber` | `Cabin` | `(ShipID, CabinNumber)` | Cabin numbers are unique per ship |
| `UQ_CabinAdjacency` | `CabinAdjacency` | `(CabinID, AdjacentCabinID)` | The same pair of cabins cannot be declared adjacent twice |
| `UQ_Port_Name_Country` | `Port` | `(PortName, Country)` | Prevents duplicate port entries for the same port in the same country |
| `UQ_RoutePort_Route_StopSequence` | `RoutePort` | `(RouteID, StopSequence)` | Each stop position in a route is unique |
| `UQ_FareRule_Voyage_Category_Age_Date` | `FareRule` | `(VoyageID, CabinCategoryID, AgeCategoryID, EffectiveFrom)` | Only one fare rule per voyage/cabin/age combination per effective date |
| `UQ_BookingCabin_Booking_Cabin` | `BookingCabin` | `(BookingID, CabinID)` | A cabin cannot be added to the same booking twice |
| `UQ_BookingPassenger_Booking_Passenger` | `BookingPassenger` | `(BookingID, PassengerID)` | A passenger can appear only once per booking |
| `UQ_ShipDiningOption_Ship_DiningOption` | `ShipDiningOption` | `(ShipID, DiningOptionID)` | A dining option is offered once per ship |
| `UQ_ShipSpecialtyDining_Ship_Type` | `ShipSpecialtyDining` | `(ShipID, SpecialtyDiningTypeID)` | A specialty dining type is listed once per ship |
| `UQ_VoyageMealPackageRule_LengthBand` | `VoyageMealPackageRule` | `(MinVoyageLengthDays, MaxVoyageLengthDays)` | No two rules cover the same voyage length band |
| `UQ_VoyageMealPackage_Voyage` | `VoyageMealPackage` | `VoyageID` | Each voyage has exactly one meal package assignment |
| `UQ_PassengerSpecialService_Passenger_Service` | `PassengerSpecialService` | `(BookingPassengerID, ServiceID)` | A passenger cannot request the same service twice per booking |
| `UQ_Excursion_Port_Name` | `Excursion` | `(PortID, ExcursionName)` | An excursion name is unique per port |
| `UQ_VoyageExcursion_Voyage_Port_Excursion` | `VoyageExcursion` | `(VoyageID, RoutePortID, ExcursionID)` | An excursion appears once per voyage stop |
| `UQ_BookingExcursion_Passenger_Excursion` | `BookingExcursion` | `(BookingPassengerID, VoyageExcursionID)` | A passenger can book the same excursion only once |
| `UQ_BookingCancellation_Booking` | `BookingCancellation` | `BookingID` | A booking can only be cancelled once |
| `UQ_CabinCategory_CategoryName` | `CabinCategory` | `CategoryName` | Each category name is globally unique |
| `UQ_DiningOption_DiningName` | `DiningOption` | `DiningName` | Each dining type is globally unique |

---

## Section C2 — Trigger Functional Descriptions

The GLCL schema includes **13 triggers** across 6 tables. Every business rule that cannot be expressed by a simple CHECK constraint is enforced by a trigger.

---

### Trigger Group 1 — `Passenger` Table

#### `TR_Passenger_BI_ValidateDateOfBirth` (BEFORE INSERT)
#### `TR_Passenger_BU_ValidateDateOfBirth` (BEFORE UPDATE)

**Purpose:** Prevent a future date of birth from being stored.

**Logic:**
- If `NEW.DateOfBirth > CURDATE()`, raise an error.

**Business Rule Supported:** A passenger's date of birth must be a real past date. A future DOB would corrupt all age-dependent calculations (fare category assignment, Chaperoned Youth eligibility, minor guardian rules).

**Why a trigger and not a CHECK constraint?**  
MySQL CHECK constraints cannot reference functions like `CURDATE()` dynamically — the value of "today" changes. A trigger executes the comparison at the moment of the DML operation, ensuring the check is always against the current date.

---

### Trigger Group 2 — `BookingCabin` Table

#### `TR_BookingCabin_BI_PreventDoubleBooking` (BEFORE INSERT)
#### `TR_BookingCabin_BU_PreventDoubleBooking` (BEFORE UPDATE)

**Purpose:** Ensure a cabin is not booked twice on the same voyage, and that the cabin physically belongs to the voyage's ship.

**Logic (in order):**
1. Retrieve the `ShipID` of the voyage associated with `NEW.BookingID`.
2. Retrieve the `ShipID` of the cabin `NEW.CabinID`.
3. If the two `ShipID` values differ, raise an error — the cabin does not belong to the voyage's ship.
4. Check if any other `Pending` or `Confirmed` booking on the same voyage has already claimed `NEW.CabinID`.
5. If a conflict exists, raise an error preventing the double-booking.
6. The UPDATE trigger additionally excludes the row being updated (`OLD.BookingCabinID`) from the conflict check.

**Business Rule Supported:** A cabin can only be occupied by one booking per voyage. Guests must be placed in cabins on the ship they are sailing on.

**Why a trigger and not a UNIQUE constraint?**  
A UNIQUE constraint on `(CabinID, VoyageID)` would require `VoyageID` to be stored in `BookingCabin`. This would denormalize the table (VoyageID is already in `Booking`). The trigger retrieves voyage context via a join at runtime, preserving normalization.

---

### Trigger Group 3 — `BookingPassenger` Table

#### `TR_BookingPassenger_BI_ValidateRules` (BEFORE INSERT)
#### `TR_BookingPassenger_BU_ValidateRules` (BEFORE UPDATE)

**Purpose:** The central business rule enforcement trigger for passenger bookings.

**Logic (executed in this order):**

| Step | Action | Business Rule |
|---|---|---|
| 1 | Verify `BookingCabinID` belongs to the same `BookingID` | Prevents cross-booking cabin assignment |
| 2 | Count existing passengers in the cabin; reject if adding this passenger would exceed `MaxOccupancy` or the hard cap of 5 | Cabin maximum of 5 passengers |
| 3 | Calculate the passenger's age at the voyage departure date using `fn_CalculateAge()`. Verify it falls within the selected `AgeCategory` bounds | Age category must match actual age |
| 4 | If category is `Infant`, `InfantBedOption` must be `SharedBed` or `Cot`. If not `Infant`, it must be `NotApplicable` | Infant bed option applies only to infants |
| 5 | If `IsChaperonedYouth = TRUE`, verify passenger is aged 15–17 and the operator's `AllowsChaperonedYouth` flag is `TRUE` | Chaperoned Youth programme eligibility |
| 6 | If passenger is aged ≤ 17 and not in Chaperoned Youth, check for an adult (MinAge ≥ 18) in the same cabin. If none, check for an adult in an adjacent or connecting cabin via `CabinAdjacency` | Minor safety: adult guardian required |
| 7 | If `IsChaperonedYouth = TRUE`, look up and set `DailySupervisionFee` from `SpecialService` | Automatic supervision fee assignment |
| 8 | Calculate `FinalFare`: Infant SharedBed = 15% of adult base fare; Infant Cot = 50% of child base fare; all others = `FareRule.BaseFare` | Fare computation per GLCL pricing rules |

**Why a trigger and not CHECK constraints?**  
Steps 3–8 each require joins to multiple other tables and runtime calculations. No CHECK constraint can perform cross-table lookups or conditional multi-step logic. The trigger is the only mechanism capable of enforcing these composite business rules at the database level.

**Difference between BI and BU versions:**  
The UPDATE trigger excludes the current passenger row (`OLD.BookingPassengerID`) from the occupancy count to avoid self-counting. The adjacent cabin guardian check is also omitted on update, as the relationship was already verified at insert time.

---

### Trigger Group 4 — `BookingBaggage` Table

#### `TR_BookingBaggage_BI_ValidateLimit` (BEFORE INSERT)
#### `TR_BookingBaggage_BU_ValidateLimit` (BEFORE UPDATE)

**Purpose:** Automatically determine whether a passenger's declared baggage weight exceeds the voyage limit and set `IsOverLimit` accordingly.

**Logic:**
1. Traverse the join chain `BookingPassenger → Booking → CruiseVoyage` to retrieve `BaggageWeightLimitKG` for the voyage.
2. Set `NEW.IsOverLimit = (NEW.WeightKG > AllowedWeight)`.

**Business Rule Supported:** GLCL enforces strict baggage weight limits per voyage. Passengers exceeding the limit must be flagged for excess fee calculation and handling. The trigger ensures `IsOverLimit` is always accurate, even if the weight is later corrected via an UPDATE.

**Why a trigger?**  
`IsOverLimit` depends on `BaggageWeightLimitKG` from a different table — a CHECK constraint cannot reach across tables. The trigger performs the cross-table comparison at the point of write.

---

### Trigger Group 5 — `BookingCancellation` Table

#### `TR_BookingCancellation_BI_ApplyPenalty` (BEFORE INSERT)
#### `TR_BookingCancellation_BU_ApplyPenalty` (BEFORE UPDATE)

**Purpose:** Compute `PenaltyAmount` and `RefundAmount` automatically based on the operator's cancellation policy and the time remaining until departure.

**Logic:**
1. Join `Booking → CruiseVoyage → CruiseShip → CancellationPolicy` to find the most applicable policy for this operator and the remaining hours until departure.
2. Calculate `HoursUntilDeparture = TIMESTAMPDIFF(HOUR, CancellationDateTime, DepartureDateTime)`.
3. Apply the matched policy:
   - **FullForfeit (< 48 hours):** `PenaltyAmount = TotalAmount`, `RefundAmount = 0`
   - **Percentage:** `PenaltyAmount = TotalAmount × (PenaltyValue / 100)`, `RefundAmount = TotalAmount − PenaltyAmount`
   - **FixedAmount:** `PenaltyAmount = MIN(PenaltyValue, TotalAmount)`, `RefundAmount = TotalAmount − PenaltyAmount`
   - **No policy matched:** `PenaltyAmount = 0`, `RefundAmount = TotalAmount` (full refund)

**Business Rule Supported:** Cancellation less than 48 hours before departure forfeits the entire ticket value. The penalty structure is operator-specific and date-sensitive — both facts that can only be evaluated at runtime.

#### `TR_BookingCancellation_AI_UpdateBookingStatus` (AFTER INSERT)

**Purpose:** After a cancellation record is committed, mark the corresponding `Booking` row as `'Cancelled'`.

**Logic:**
```sql
UPDATE Booking SET BookingStatus = 'Cancelled' WHERE BookingID = NEW.BookingID;
```

**Why AFTER INSERT and not BEFORE?**  
The cancellation row must first be successfully inserted (referential integrity verified) before the booking status can be updated. An AFTER trigger guarantees the cancellation row exists before the parent booking is modified.

---

### Trigger Group 6 — `RescheduleRequest` Table

#### `TR_RescheduleRequest_BI_ValidateRules` (BEFORE INSERT)
#### `TR_RescheduleRequest_BU_ValidateRules` (BEFORE UPDATE)

**Purpose:** Validate reschedule requests against three business rules before the record is written.

**Logic (in order):**
1. Retrieve `OriginalBookingDate`, `OriginalDepartureTime`, and `TotalAmount` from the original booking.
2. Retrieve `DepartureDateTime` of the requested new voyage.
3. **Rule 1:** If `RequestDateTime >= OriginalDepartureTime`, the voyage has already departed — reject with error.
4. **Rule 2:** If `NewDepartureDateTime > OriginalBookingDate + 1 YEAR`, the new voyage falls outside the one-year window — reject with error.
5. **Rule 3:** If `HoursUntilDeparture <= 48`, set `RescheduleFee = OriginalTotalAmount` (full booking cost charged as fee).

**Business Rules Supported:**
- You cannot reschedule a voyage that has already departed.
- The replacement voyage must depart within one year of the original booking date.
- Rescheduling within 48 hours of departure incurs a fee equal to the full booking value.

---

### Summary — Triggers vs. Constraints Decision Table

| Enforcement Need | Mechanism Used | Reason |
|---|---|---|
| Column value in a defined set | CHECK constraint | Simple domain check, no cross-table lookup needed |
| Column value within numeric range | CHECK constraint | Simple comparison, evaluatable without joins |
| Cross-table referential integrity | FOREIGN KEY | Standard referential integrity enforcement |
| No duplicate combinations | UNIQUE constraint | Set-membership check handled natively |
| Comparison to `CURDATE()` | Trigger | CHECK constraints cannot use dynamic functions |
| Cross-table join logic | Trigger | CHECK constraints cannot reference other tables |
| Conditional multi-step computation | Trigger | Business logic with branching requires procedural code |
| Cascading status updates | AFTER trigger | Secondary table must be updated after primary insert commits |

---

*Document prepared for GLCL Academic Database Assignment — MySQL 8+*

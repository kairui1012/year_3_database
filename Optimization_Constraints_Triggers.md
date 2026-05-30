# GLCL Database — Optimization Strategy, Constraints & Triggers

> **MySQL 8+ · Academic Assignment · GLOBAL LUXURY CRUISE LINES**

---

## Part (b) — Optimization Strategy

> *"Document and provide a written description and justification of your optimization strategy. Each group member is required to produce one optimization strategy."*
> **(10 marks)**

---

### Strategy 1 — Composite Indexing on Trigger-Critical Query Paths

**Prepared by: Member 1**

The primary optimization strategy applied to the GLCL database is the introduction of composite indexes targeted at the query paths executed inside the system's triggers. The rationale for focusing on triggers rather than general reporting queries is that trigger sub-queries fire on every `INSERT` statement — making them the highest-frequency reads in the system. Without purpose-built indexes, each trigger sub-query performs a full table scan, meaning that the cost of a single booking insert scales linearly with the size of the affected tables.

The most expensive trigger in the schema is `TR_BookingPassenger_BI_ValidateRules`, which executes multiple sequential queries on `BookingPassenger`, `FareRule`, `Booking`, `CruiseVoyage`, `CruiseShip`, and `CruiseOperator` before each passenger row is committed. The fare lookup alone — which retrieves the applicable `BaseFare` from `FareRule` filtered by `(VoyageID, CabinCategoryID, AgeCategoryID)` and sorted by `EffectiveFrom DESC` — is executed on every booking insert with no index support by default. A composite index on `FareRule (VoyageID, CabinCategoryID, AgeCategoryID, EffectiveFrom DESC)` reduces this from a full table scan to an O(log n) B-tree seek, and because the equality filters narrow the result to at most a few rows per voyage-cabin-age combination, the `ORDER BY ... LIMIT 1` clause is resolved from the index's pre-sorted order without a filesort.

Similarly, the cabin occupancy count (`COUNT(*) WHERE BookingCabinID = ?`) inside the same trigger benefits from a composite index on `BookingPassenger (BookingCabinID, BookingID)`. Without it, every passenger insert scans the entire `BookingPassenger` table to count the 0–5 occupants of a single cabin. The double-booking check in `TR_BookingCabin_BI_PreventDoubleBooking` benefits from an index on `BookingCabin (CabinID, BookingID)`, which allows the `EXISTS` sub-query to seek directly to the relevant cabin's bookings rather than scanning all cabin assignments. For `Booking`, a composite index on `(VoyageID, BookingStatus)` supports both the trigger's voyage-level conflict check and all voyage manifest queries, with `VoyageID` placed first because it has higher selectivity than `BookingStatus` (which has only six distinct values). For the cancellation trigger, an index on `CancellationPolicy (OperatorID, HoursBeforeDeparture ASC)` means the `ORDER BY HoursBeforeDeparture ASC LIMIT 1` policy lookup terminates after reading a single index leaf page rather than sorting the entire policy table.

The trade-off of this strategy is that each additional index increases the overhead of `INSERT`, `UPDATE`, and `DELETE` operations, since the InnoDB engine must update the B-tree structure of every affected index on each write. However, this cost is justified in the GLCL context for two reasons. First, the triggers themselves already introduce read operations on every write — so the write path already pays a read cost, and indexing those reads directly reduces the net transaction cost. Second, a cruise reservation system is inherently read-dominant: each booking, once created, is queried repeatedly for manifests, payment processing, excursion lookups, and cancellation checks, so optimizing reads at the cost of marginally slower writes is the correct priority for this workload.

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

---

### Strategy 2 — Selective Denormalization for Historical Price Preservation

**Prepared by: Member 2**

The second optimization strategy is the deliberate and documented selective denormalization of the `PassengerSpecialService` table. In a strictly normalized 3NF design, `PassengerSpecialService` would store only a foreign key to `SpecialService` and derive the applicable fee by joining to `SpecialService.Fee` at query time. However, this approach is incorrect for financial audit purposes: `SpecialService.Fee` represents the *current* price of a service, which may be updated over time. A passenger who booked a service at a specific fee must have that exact amount preserved permanently in their booking record, regardless of any subsequent price changes. Storing only the foreign key means that historical booking reports will silently show the wrong fee — whichever value `SpecialService.Fee` holds at the time the report is run rather than at the time the booking was made.

The denormalization introduces an `AppliedFee` column in `PassengerSpecialService` that records the fee at the moment of booking. This column is automatically populated by a BEFORE INSERT trigger that reads `SpecialService.Fee` at insert time and writes it into `NEW.AppliedFee`, ensuring the value is captured once and never altered by subsequent changes to the price list. This is not a violation of 3NF in the meaningful sense: `AppliedFee` is not a redundant copy of `SpecialService.Fee` — it is a different fact, describing the fee charged at a specific point in time, which is functionally dependent on the booking event (`PassengerServiceID`) rather than solely on `ServiceID`. The assignment explicitly permits denormalization where a detailed explanation is provided, and this case satisfies that requirement. The same design pattern is already present in the original schema, where `BookingCancellation.PenaltyAmount` and `RefundAmount` are computed at cancellation time and stored independently rather than being re-derived from `CancellationPolicy` on each query.

---

### Strategy 3 — Reporting Views to Encapsulate Repeated Join Paths

**Prepared by: Member 3**

The third optimization strategy is the creation of named views to encapsulate the deep join chains that appear repeatedly across different queries in the GLCL schema. The most common such chain traverses `BookingPassenger → BookingCabin → Cabin → CabinCategory → Booking → CruiseVoyage → CruiseRoute → CruiseShip → CruiseOperator → Passenger → AgeCategory` — a ten-table join that is required for reservation manifests, passenger age reports, and revenue breakdowns. Without views, each developer writing an ad-hoc query must reconstruct this join path from scratch, creating risk of missing join conditions, incorrect alias usage, or inadvertent Cartesian products that silently return incorrect results.

Two views are introduced: `vw_BookingPassengerDetails`, which exposes the full passenger booking detail join path as a single queryable object including the passenger's computed age at departure using `fn_CalculateAge`, and `vw_VoyageCabinAvailability`, which surfaces cabin availability status per voyage without requiring callers to understand the double-booking logic. MySQL's query optimizer treats views as inline subquery definitions rather than materializing them, meaning it can apply predicate pushdown — pushing `WHERE` filters from the outer query into the view's join — and can use the indexes created under Strategy 1 to resolve the view's joins efficiently. This means the views add no storage overhead and impose no performance penalty compared to writing the joins directly, while significantly reducing the complexity and error surface of reporting queries.

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

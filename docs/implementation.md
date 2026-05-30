# GLCL Database — Implementation Report

> **Question 2(a) · MySQL 8+ · GLOBAL LUXURY CRUISE LINES**

---

## Tables and Schema Design

The GLCL database is implemented across 27 tables organised into six functional domains: operator and ship management (`CruiseOperator`, `CruiseShip`, `Cabin`, `CabinCategory`, `CabinAdjacency`), route and voyage scheduling (`CruiseRoute`, `Port`, `RoutePort`, `CruiseVoyage`), passenger and booking management (`Passenger`, `AgeCategory`, `Booking`, `BookingCabin`, `BookingPassenger`, `FareRule`), dining (`DiningOption`, `ShipDiningOption`, `SpecialtyDiningType`, `ShipSpecialtyDining`, `VoyageMealPackageType`, `VoyageMealPackageRule`, `VoyageMealPackage`), special services and baggage (`SpecialService`, `PassengerSpecialService`, `BaggageRule`, `BookingBaggage`), excursions (`Excursion`, `VoyageExcursion`, `BookingExcursion`), and financial operations (`CancellationPolicy`, `BookingCancellation`, `RescheduleRequest`, `Payment`). Every table uses an `INT AUTO_INCREMENT` surrogate primary key, which keeps foreign key joins efficient and avoids the fragility of natural-key updates. All tables are implemented in MySQL 8.0 using `InnoDB`, which provides row-level locking and full foreign key enforcement.

---

## Referential Integrity

Referential integrity is enforced throughout the schema using 43 foreign key constraints following the naming convention `FK_ChildTable_ParentTable`. Key relationships include: `CruiseShip.OperatorID → CruiseOperator`, `Cabin.ShipID → CruiseShip`, `CruiseVoyage.ShipID → CruiseShip` and `CruiseVoyage.RouteID → CruiseRoute`, `Booking.VoyageID → CruiseVoyage`, `BookingCabin.BookingID → Booking` and `BookingCabin.CabinID → Cabin`, and `BookingPassenger.BookingCabinID → BookingCabin`. The self-referencing `Booking.OriginalBookingID → Booking` preserves the audit trail for rescheduled bookings. All foreign keys use the default `RESTRICT` behaviour, meaning a parent record cannot be deleted while child records exist, which protects booking history from accidental data loss.

---

## Test Data

Seed data is provided in `seedata.sql` and is designed to exercise every business rule enforced by the schema. It includes at least two cruise operators (one with `AllowsChaperonedYouth = TRUE`), multiple ships with cabins across all four categories (`Interior`, `Ocean View`, `Balcony`, `Suite`), and cabins with `CabinAdjacency` records to support minor guardian validation. Passengers span all five age categories (Infant, Child, Teen, Adult, Senior) and include at least one infant with each bed option (`SharedBed` and `Cot`) to verify the fare computation trigger. Bookings cover all six status values (`Pending`, `Confirmed`, `Waitlisted`, `Cancelled`, `Rescheduled`, `Completed`) so that reporting queries can be verified against filtered and unfiltered result sets. At least one cancellation record is included to validate `TR_BookingCancellation_BI_ApplyPenalty` and confirm that the booking status is updated to `Cancelled` by the after-insert trigger.

---

## Constraints

The schema uses five categories of constraints. Primary key constraints uniquely identify every row. Foreign key constraints enforce referential integrity as described above. Six `CHECK` constraints enforce domain rules that cannot be expressed as foreign keys: `CK_Cabin_MaxOccupancy` (1–5 passengers), `CK_CruiseVoyage_ArrivalAfterDeparture` (arrival must follow departure), `CK_BookingPassenger_InfantBedOption` (valid bed options), `CK_Booking_Status` (six permitted states), `CK_CancellationPolicy_PenaltyType` (three penalty types), and `CK_AgeCategory_AgeRange` (logical age bounds). `UNIQUE` constraints prevent duplicate combinations such as the same cabin being added to a booking twice (`UQ_BookingCabin_Booking_Cabin`) and the same passenger appearing twice in a booking (`UQ_BookingPassenger_Booking_Passenger`). `NOT NULL` constraints enforce mandatory fields at every table boundary. Business rules that require cross-table lookups — cabin occupancy limits, fare calculation, double-booking prevention, and cancellation penalty computation — are enforced by six BEFORE/AFTER INSERT triggers rather than constraints, because MySQL `CHECK` constraints cannot reference other tables.

---

## Optimization Techniques

Three optimization strategies are implemented, one per group member, documented in full in `Optimization_Constraints_Triggers.md`. Member 1's strategy introduces composite indexes on the query paths executed inside the system's triggers. The most expensive trigger, `TR_BookingPassenger_BI_ValidateRules`, executes seven sequential sub-queries on every passenger insert; the index `IDX_FareRule_Voyage_Cabin_Age_Date` on `FareRule (VoyageID, CabinCategoryID, AgeCategoryID, EffectiveFrom DESC)` reduces the fare lookup from a full table scan to an O(log n) B-tree seek, and `IDX_Booking_Voyage_Status` on `Booking (VoyageID, BookingStatus)` supports both the double-booking trigger and all voyage manifest queries. All six indexes are created after seed data is loaded so that MySQL builds each B-tree in a single pass rather than updating it incrementally on every insert. Member 2's strategy addresses selective denormalization, and Member 3's strategy introduces reporting views; both are documented separately.

---

## Mapping and Denormalization Justification

The schema is normalised to Third Normal Form (3NF) throughout, with two deliberate and documented exceptions. First, `CruiseVoyage.VoyageLengthDays` is a `STORED` generated column computed as `DATEDIFF(ArrivalDateTime, DepartureDateTime)`. This is not a 3NF violation in the strict sense — MySQL's generated column mechanism ensures the value is always consistent with its source columns — but it is noted here because it stores a derived value physically. The justification is that `VoyageLengthDays` is used in multiple joins and filter conditions across both reporting queries and the meal package rule lookup, and computing `DATEDIFF` repeatedly in every query would add unnecessary overhead. Second, `BookingCancellation.PenaltyAmount` and `RefundAmount` are computed at event time by a trigger and stored as independent facts rather than being re-derived from `CancellationPolicy` on each query. This is justified on audit trail grounds: the penalty applied to a customer must reflect the policy in force at the moment of cancellation, not any subsequent changes to the policy table. This design pattern is consistent with standard financial system practice, where historical transaction amounts must be immutable.

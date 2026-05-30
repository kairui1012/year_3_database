/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    Member 1 - Answers

    Covers:
    - Q1c : Constraint & Trigger description
    - Q2c : Stored Procedure
    - Q2d : Queries i - vii
*/

USE GLCL_DB;

/* =========================================================
   Q1c - CONSTRAINT & TRIGGER DESIGN (Member 1)
   =========================================================

    ---------------------------------------------------------
    PART A1 - CONSTRAINT #1 (CHECK)
    ---------------------------------------------------------
    Constraint Name : CK_Cabin_MaxOccupancy
    Table           : Cabin
    Type            : CHECK constraint
    Definition      : CHECK (MaxOccupancy BETWEEN 1 AND 5)

    BUSINESS RULE SUPPORTED
    GLCL's safety policy and maritime regulations state that
    no cabin may be sold for more than 5 passengers, and a
    cabin with 0 occupancy is meaningless because it cannot
    be booked. MaxOccupancy must therefore always fall
    between 1 and 5 inclusive.

    JUSTIFICATION (why a CHECK constraint)
    1. vs. enforcing it in the application layer only:
        A CHECK constraint is enforced by the database engine
        itself. Even a direct INSERT from SSMS, an ETL job,
        or a different application cannot bypass it. The
        business rule cannot be broken by code that forgets
        the validation.
    2. vs. a trigger:
        A CHECK constraint is declarative - the engine knows
        its meaning and uses it for query optimisation (it
        can skip impossible result branches). A trigger would
        need a SELECT + IF + ROLLBACK on every INSERT, which
        is heavier and harder to read.
    3. vs. a FOREIGN KEY to a lookup table:
        Only 5 valid values exist and they form a continuous
        range. A lookup table would be over-engineering.

    HOW IT SUPPORTS THE BUSINESS RULE
    - Insert / update of any Cabin row with MaxOccupancy
        outside 1-5 is rejected at the engine level.
    - The trigger TR_BookingPassenger_BI_ValidateRules then
        uses this column at insert time to also block any
        attempt to put more passengers in a cabin than its
        MaxOccupancy allows - the constraint guarantees that
        value is always trustworthy.

    ---------------------------------------------------------
    PART A2 - CONSTRAINT #2 (UNIQUE)
    ---------------------------------------------------------
    Constraint Name : UQ_Cabin_Ship_CabinNumber
    Table           : Cabin
    Type            : UNIQUE constraint (composite)
    Definition      : UNIQUE (ShipID, CabinNumber)

    BUSINESS RULE SUPPORTED
    On any given ship, a cabin number (e.g. "A-201") must
    identify exactly one physical cabin. Two cabins on the
    same ship sharing the same number would make crew
    assignment, housekeeping and emergency muster impossible
    to manage. However, two different ships are allowed to
    reuse the same cabin number (most cruise lines do),
    so the uniqueness must be scoped to the ship - hence a
    composite UNIQUE on (ShipID, CabinNumber) rather than
    on CabinNumber alone.

    JUSTIFICATION (why a UNIQUE constraint)
    1. vs. checking for duplicates in the application:
        A second concurrent INSERT could slip through between
        the check and the write. A UNIQUE constraint uses an
        index and is enforced atomically by the engine - even
        under high concurrency, only one row can win.
    2. vs. using CabinNumber as a primary key:
        The same cabin number is intentionally reused across
        ships (Ship A's "A-201" is not Ship B's "A-201"),
        so a global PK on CabinNumber would forbid valid data.
        The surrogate CabinID stays as PK; UNIQUE expresses
        the real-world identity rule.
    3. vs. a trigger:
        UNIQUE is declarative and backed by an index, which
        also speeds up lookups like
            "find cabin A-201 on Ship 3".
        A trigger would be slower and easier to get wrong.

    HOW IT SUPPORTS THE BUSINESS RULE
    - Prevents data-entry errors that would create two
        rows with the same (ShipID, CabinNumber).
    - Guarantees that downstream queries (cabin assignment,
        housekeeping rota, manifest) can identify a cabin
        unambiguously by ship + number.
    - The supporting index also accelerates the BookingCabin
        and trigger lookups that join through Cabin.

   ---------------------------------------------------------
   PART B - TRIGGER (functional description)
   ---------------------------------------------------------
   Trigger Name : TR_BookingPassenger_BI_ValidateRules
   Table        : BookingPassenger
   Event        : BEFORE INSERT (logical - implemented as
                  INSTEAD OF INSERT in SQL Server)

   PURPOSE
   This single trigger atomically enforces every business
   rule that applies the moment a passenger is added to a
   cabin within a booking. Centralising the rules here
   means no INSERT path can bypass any of them.

   FUNCTIONAL DESCRIPTION (step by step)
   1. OWNERSHIP CHECK
      Confirms BookingPassenger.BookingID matches the
      BookingID stored on the BookingCabin row referenced.
      Rejects the row otherwise - prevents a passenger
      being attached to a cabin from a different booking.

   2. OCCUPANCY CHECK
      Counts existing passengers in the target cabin and
      rejects if adding the new one would exceed either:
        (a) Cabin.MaxOccupancy, or
        (b) the absolute ceiling of 5.

   3. AGE CATEGORY CHECK
      Calculates the passenger's age at voyage departure
      from Passenger.DateOfBirth and verifies that the
      supplied AgeCategoryID matches the age band defined
      in AgeCategory (Infant / Child / Teen / Adult /
      Senior). Prevents fare manipulation by mislabelling.

   4. INFANT FARE & BED OPTION
      For infants only:
        - SharedBed  => FinalFare = 15 % of adult base fare
        - Cot        => FinalFare = 50 % of child base fare
      For everyone else FinalFare is read from FareRule.
      InfantBedOption must be 'NotApplicable' for non-infants.

   5. GUARDIAN / CHAPERONED YOUTH CHECK
      For passengers aged 17 or below:
        - Pass if an adult is in the same cabin, OR in an
          adjacent / connecting cabin on the same voyage.
        - Otherwise, if the operator allows Chaperoned
          Youth and the passenger is aged 15-17, attach
          the supervision fee from SpecialService and
          set IsChaperonedYouth = 1.
        - Otherwise reject - a lone minor cannot sail.

   WHY A TRIGGER (rather than constraints alone)
   - The rules cross multiple tables (Cabin, Passenger,
     AgeCategory, FareRule, CabinAdjacency,
     SpecialService). CHECK constraints can only reference
     columns of one row - they cannot express these rules.
   - The fare must be COMPUTED, not just validated. A
     constraint can reject bad values but cannot fill in
     a derived value. Triggers can.
   - Putting the logic in the database guarantees every
     channel (web, mobile, agent desk, batch import) sees
     the same rules.
   ========================================================= */

/* =========================================================
   Q2c - STORED PROCEDURE
   sp_GetVoyageRevenueSummary

   BUSINESS REQUIREMENT
   Finance and operations teams need a revenue report for any
   single voyage, broken down by cabin category, with the ship
   total shown alongside each row.

   WHY A STORED PROCEDURE (vs other approaches)
   1. vs. writing the SQL inside each report/screen:
      The query joins 9 tables and must only count Confirmed
      and Completed bookings. If every report writes its own
      version the filter rules will drift apart and revenue
      totals will stop matching across reports.
   2. vs. a VIEW:
      A view cannot accept @VoyageID. Filtering with
      WHERE VoyageID = 1 outside the view forces SQL Server to
      compute aggregates for every voyage first and then throw
      most away. The SP pushes the filter inside.
   3. vs. a FUNCTION:
      An inline TVF cannot run input validation (THROW if the
      voyage does not exist). A scalar function returns only
      one value, not a result set.

   HOW TO USE
       EXEC sp_GetVoyageRevenueSummary @VoyageID = 1;

   BENEFITS
   - Single source of truth - every report agrees
   - Parameterised => safe from SQL injection
   - Compiled execution plan is cached and reused
   - EXECUTE rights can be granted without giving callers
     SELECT on the underlying booking tables
   ========================================================= */

IF OBJECT_ID('sp_GetVoyageRevenueSummary', 'P') IS NOT NULL
    DROP PROCEDURE sp_GetVoyageRevenueSummary;
GO

CREATE PROCEDURE sp_GetVoyageRevenueSummary
    @VoyageID INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM CruiseVoyage WHERE VoyageID = @VoyageID)
        THROW 50000, 'Voyage not found.', 1;

    SELECT
        s.ShipID                                            AS ShipCode,
        co.OperatorName,
        r.RouteName,
        r.RouteType,
        v.DepartureDateTime,
        v.ArrivalDateTime,
        cc.CabinCategoryID                                  AS CabinCategoryCode,
        cc.CategoryName                                     AS CabinCategory,
        COUNT(DISTINCT bc.BookingCabinID)                   AS CabinsSold,
        SUM(bp.FinalFare)                                   AS CategoryFareRevenue,
        SUM(SUM(bp.FinalFare))
            OVER (PARTITION BY s.ShipID)                    AS TotalShipFareRevenue
    FROM CruiseVoyage     v
    INNER JOIN CruiseShip     s    ON v.ShipID         = s.ShipID
    INNER JOIN CruiseOperator co   ON s.OperatorID     = co.OperatorID
    INNER JOIN CruiseRoute    r    ON v.RouteID        = r.RouteID
    INNER JOIN Booking        b    ON b.VoyageID       = v.VoyageID
        AND b.BookingStatus IN ('Confirmed', 'Completed')
    INNER JOIN BookingCabin   bc   ON bc.BookingID     = b.BookingID
    INNER JOIN Cabin          c    ON bc.CabinID       = c.CabinID
    INNER JOIN CabinCategory  cc   ON c.CabinCategoryID = cc.CabinCategoryID
    INNER JOIN BookingPassenger bp  ON bp.BookingCabinID = bc.BookingCabinID
    WHERE v.VoyageID = @VoyageID
    GROUP BY
        s.ShipID, co.OperatorName, r.RouteName, r.RouteType,
        v.DepartureDateTime, v.ArrivalDateTime,
        cc.CabinCategoryID, cc.CategoryName
    ORDER BY cc.CabinCategoryID;
END;
GO

/* =========================================================
   Q2d - QUERIES
   ========================================================= */

-- -------------------------------------------------------
-- Query i
-- Round-trip sailings for given dates, departure port,
-- and arrival port.
-- (For round-trips the departure and arrival port are the
--  same home port; we filter on first stop = last stop.)
-- -------------------------------------------------------
SELECT
    v.VoyageID,
    r.RouteName,
    p_dep.PortName AS DeparturePort,
    p_arr.PortName AS ArrivalPort,
    v.DepartureDateTime,
    v.ArrivalDateTime
FROM CruiseVoyage v
INNER JOIN CruiseRoute r ON v.RouteID = r.RouteID

-- First port (departure)
INNER JOIN RoutePort rp_dep
    ON r.RouteID = rp_dep.RouteID
   AND rp_dep.StopSequence = 1
INNER JOIN Port p_dep
    ON rp_dep.PortID = p_dep.PortID

-- Last port (arrival)
INNER JOIN (
    SELECT RouteID, MAX(StopSequence) AS LastSeq
    FROM RoutePort
    GROUP BY RouteID
) last_seq
    ON r.RouteID = last_seq.RouteID

INNER JOIN RoutePort rp_arr
    ON r.RouteID = rp_arr.RouteID
   AND rp_arr.StopSequence = last_seq.LastSeq
INNER JOIN Port p_arr
    ON rp_arr.PortID = p_arr.PortID

WHERE r.RouteType = 'Round-trip'
  AND p_dep.PortID = p_arr.PortID
  AND CAST(v.DepartureDateTime AS DATE)
      BETWEEN '2026-01-01' AND '2026-12-31'
ORDER BY v.DepartureDateTime;

-- -------------------------------------------------------
-- Query ii
-- Ship code, cabin category code, expected revenue per
-- cabin category, and total revenue per ship for a given
-- cruise operator on a single voyage.
-- -------------------------------------------------------
SELECT
    s.ShipID AS ShipCode,
    cc.CabinCategoryID AS CabinCategoryCode,
    SUM(bp.FinalFare) AS CategoryRevenue,
    SUM(SUM(bp.FinalFare)) OVER (PARTITION BY s.ShipID) AS TotalShipRevenue
FROM Booking b
INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
INNER JOIN CruiseShip s ON v.ShipID = s.ShipID
INNER JOIN CruiseOperator co ON s.OperatorID = co.OperatorID
INNER JOIN BookingCabin bc ON bc.BookingID = b.BookingID
INNER JOIN Cabin c ON bc.CabinID = c.CabinID
INNER JOIN CabinCategory cc ON c.CabinCategoryID = cc.CabinCategoryID
INNER JOIN BookingPassenger bp ON bp.BookingCabinID = bc.BookingCabinID
WHERE co.OperatorName = 'Global Luxury Cruise Lines'
  AND v.VoyageID = 1
  AND b.BookingStatus IN ('Confirmed', 'Completed')
GROUP BY s.ShipID, cc.CabinCategoryID
ORDER BY cc.CabinCategoryID;

-- -------------------------------------------------------
-- Query iii
-- All passenger IDs with textual descriptions of their
-- reservation status for a specific cruise operator.
-- -------------------------------------------------------
SELECT
    p.PassengerID,
    p.FullName,
    b.BookingID,
    b.BookingStatus,
    CASE b.BookingStatus
        WHEN 'Pending'     THEN 'Booking submitted and awaiting confirmation'
        WHEN 'Confirmed'   THEN 'Reservation is confirmed and active'
        WHEN 'Waitlisted'  THEN 'Passenger is on the waiting list pending availability'
        WHEN 'Rescheduled' THEN 'Booking has been moved to a new voyage'
        WHEN 'Cancelled'   THEN 'Reservation has been cancelled'
        WHEN 'Completed'   THEN 'Voyage has been successfully completed'
        ELSE 'Status unknown'
    END                         AS ReservationStatusDescription,
    co.OperatorName
FROM Passenger p
INNER JOIN BookingPassenger bp ON p.PassengerID  = bp.PassengerID
INNER JOIN Booking          b  ON bp.BookingID   = b.BookingID
INNER JOIN CruiseVoyage     v  ON b.VoyageID     = v.VoyageID
INNER JOIN CruiseShip       s  ON v.ShipID       = s.ShipID
INNER JOIN CruiseOperator   co ON s.OperatorID   = co.OperatorID
WHERE co.OperatorName = 'Global Luxury Cruise Lines'
ORDER BY p.PassengerID, b.BookingID;

-- -------------------------------------------------------
-- Query iv
-- Cruise operator most frequently booked by passengers
-- for a specified departure port in a given date range.
-- -------------------------------------------------------
SELECT TOP 1
    co.OperatorName,
    COUNT(b.BookingID) AS TotalBookings
FROM Booking        b
INNER JOIN CruiseVoyage   v    ON b.VoyageID   = v.VoyageID
INNER JOIN CruiseShip     s    ON v.ShipID     = s.ShipID
INNER JOIN CruiseOperator co   ON s.OperatorID = co.OperatorID
-- Match the departure port (first stop on the route)
INNER JOIN RoutePort      rp   ON v.RouteID    = rp.RouteID
    AND rp.StopSequence = 1
INNER JOIN Port           p    ON rp.PortID    = p.PortID
WHERE p.PortName = 'Port Klang'
  AND CAST(b.BookingDate AS DATE) BETWEEN '2026-01-01' AND '2026-12-31'
  AND b.BookingStatus IN ('Confirmed', 'Completed')
GROUP BY co.OperatorID, co.OperatorName
ORDER BY TotalBookings DESC;

-- -------------------------------------------------------
-- Query v
-- For each age category: total infants, children, teens,
-- adults, seniors on a specified voyage by a given cruise
-- line. Detailed breakdown + grand total using ROLLUP.
-- -------------------------------------------------------
SELECT
    COALESCE(ac.CategoryName, 'Grand Total') AS AgeCategory,
    SUM(CASE WHEN ac.CategoryName = 'Infant' THEN 1 ELSE 0 END) AS Infants,
    SUM(CASE WHEN ac.CategoryName = 'Child'  THEN 1 ELSE 0 END) AS Children,
    SUM(CASE WHEN ac.CategoryName = 'Teen'   THEN 1 ELSE 0 END) AS Teens,
    SUM(CASE WHEN ac.CategoryName = 'Adult'  THEN 1 ELSE 0 END) AS Adults,
    SUM(CASE WHEN ac.CategoryName = 'Senior' THEN 1 ELSE 0 END) AS Seniors,
    COUNT(*) AS TotalPassengers
FROM BookingPassenger bp
JOIN AgeCategory ac ON bp.AgeCategoryID = ac.AgeCategoryID
JOIN Booking b ON bp.BookingID = b.BookingID
JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
JOIN CruiseShip s ON v.ShipID = s.ShipID
JOIN CruiseOperator co ON s.OperatorID = co.OperatorID
WHERE v.VoyageID = 1
  AND co.OperatorName = 'Global Luxury Cruise Lines'
  AND b.BookingStatus IN ('Confirmed', 'Completed')
GROUP BY ROLLUP(ac.CategoryName);

-- -------------------------------------------------------
-- Query vi
-- Cruise operator offering the maximum number of
-- multi-destination itineraries, with departure and
-- final arrival port names.
-- -------------------------------------------------------
SELECT TOP 1
    co.OperatorName,
    p_dep.PortName          AS DeparturePort,
    p_arr.PortName          AS FinalArrivalPort,
    COUNT(v.VoyageID)       AS MultiDestinationVoyages
FROM CruiseVoyage  v
INNER JOIN CruiseShip     s        ON v.ShipID   = s.ShipID
INNER JOIN CruiseOperator co       ON s.OperatorID = co.OperatorID
INNER JOIN CruiseRoute    r        ON v.RouteID  = r.RouteID
INNER JOIN RoutePort      rp_dep   ON r.RouteID  = rp_dep.RouteID
    AND rp_dep.StopSequence = 1
INNER JOIN Port           p_dep    ON rp_dep.PortID = p_dep.PortID
INNER JOIN (
    SELECT RouteID, MAX(StopSequence) AS LastSeq
    FROM   RoutePort
    GROUP  BY RouteID
)                         last_seq ON r.RouteID = last_seq.RouteID
INNER JOIN RoutePort      rp_arr   ON r.RouteID  = rp_arr.RouteID
    AND rp_arr.StopSequence = last_seq.LastSeq
INNER JOIN Port           p_arr    ON rp_arr.PortID = p_arr.PortID
WHERE r.RouteType = 'Multi-destination'
GROUP BY
    co.OperatorID, co.OperatorName,
    p_dep.PortName, p_arr.PortName
ORDER BY MultiDestinationVoyages DESC;

-- -------------------------------------------------------
-- Query vii  (additional - own design)
-- Passenger lifetime value report: total fare spend,
-- total excursion spend, and combined lifetime value
-- for each passenger who has at least one booking.
-- Useful for loyalty programme targeting and marketing.
-- Uses a LEFT JOIN to capture passengers with no
-- excursion purchases (NULL -> 0 via COALESCE).
-- -------------------------------------------------------
SELECT
    p.PassengerID,
    p.FullName,
    p.Nationality,
    COUNT(DISTINCT b.BookingID)                              AS TotalBookings,
    COALESCE(SUM(bp.FinalFare), 0)                          AS TotalFareSpend,
    COALESCE(SUM(be.AmountPaid), 0)                         AS TotalExcursionSpend,
    COALESCE(SUM(bp.FinalFare), 0)
        + COALESCE(SUM(be.AmountPaid), 0)                   AS LifetimeValue,
    RANK() OVER (
        ORDER BY COALESCE(SUM(bp.FinalFare), 0)
               + COALESCE(SUM(be.AmountPaid), 0) DESC
    )                                                        AS ValueRank
FROM Passenger p
INNER JOIN BookingPassenger bp ON p.PassengerID        = bp.PassengerID
INNER JOIN Booking          b  ON bp.BookingID         = b.BookingID
    AND b.BookingStatus IN ('Confirmed', 'Completed')
LEFT JOIN BookingExcursion  be ON bp.BookingPassengerID = be.BookingPassengerID
    AND be.ExcursionStatus IN ('Booked', 'Completed')
GROUP BY p.PassengerID, p.FullName, p.Nationality
ORDER BY LifetimeValue DESC;

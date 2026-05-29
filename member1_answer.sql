/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    Member 1 — Answers

    Covers:
    - Q1b : Optimization Strategy (indexes + justification)
    - Q1c : Constraint & Trigger description
    - Q2c : Stored Procedure
    - Q2d : Queries i – vii
*/

USE GLCL_DB;

/* =========================================================
   Q1b — OPTIMIZATION STRATEGY
   Member 1 Strategy: Index frequently-joined and filtered columns
   on the core booking path (Booking → CruiseVoyage → CruiseShip).

   Justification:
   Almost every business query travels: Booking → VoyageID →
   CruiseVoyage → ShipID → CruiseShip → OperatorID → CruiseOperator.
   Without indexes MySQL performs full table scans on large tables.
   Adding composite indexes on the foreign-key + filter columns
   used in WHERE and JOIN clauses collapses O(n) scans to O(log n)
   B-tree lookups, dramatically improving response time for booking
   and revenue reports especially as row counts grow.
   ========================================================= */

CREATE INDEX IDX_Booking_VoyageID
    ON Booking (VoyageID);

CREATE INDEX IDX_Booking_Status_VoyageID
    ON Booking (BookingStatus, VoyageID);

CREATE INDEX IDX_BookingPassenger_BookingID
    ON BookingPassenger (BookingID);

CREATE INDEX IDX_BookingPassenger_PassengerID
    ON BookingPassenger (PassengerID);

CREATE INDEX IDX_CruiseVoyage_ShipID_Departure
    ON CruiseVoyage (ShipID, DepartureDateTime);

CREATE INDEX IDX_RoutePort_RouteID_Seq
    ON RoutePort (RouteID, StopSequence);

CREATE INDEX IDX_FareRule_Voyage_Category
    ON FareRule (VoyageID, CabinCategoryID, AgeCategoryID);

/* =========================================================
   Q1c — CONSTRAINT DESCRIPTION
   Constraint: CK_Cabin_MaxOccupancy  (Cabin table)

   Definition : MaxOccupancy BETWEEN 1 AND 5

   Justification:
   GLCL's safety regulations state a strict maximum of 5 passengers
   per cabin per booking. Allowing MaxOccupancy < 1 would make a
   cabin un-bookable. The upper bound of 5 is a hard maritime safety
   rule enforced both at the schema level (CHECK) and at insert time
   in the trigger TR_BookingPassenger_BI_ValidateRules. Using a CHECK
   constraint ensures no application layer can bypass the rule by
   writing directly to the database.

   Trigger Description: TR_BookingPassenger_BI_ValidateRules
   Fires   : BEFORE INSERT on BookingPassenger
   Purpose : Single trigger that enforces five business rules atomically:
             1. Verifies BookingPassenger.BookingID matches the cabin's
                booking to prevent cross-booking cabin assignments.
             2. Rejects insert if the cabin would exceed MaxOccupancy
                or the hard 5-passenger ceiling.
             3. Validates that the assigned AgeCategoryID matches the
                passenger's calculated age at voyage departure.
             4. Enforces infant bed option (SharedBed/Cot) rules and
                auto-calculates FinalFare:
                  SharedBed infant → 15 % of Adult base fare
                  Cot infant      → 50 % of Child base fare
             5. Checks that a minor (≤ 17) has an adult guardian in
                the same cabin OR in an adjacent/connecting cabin on
                the same voyage; if not, and the operator supports
                Chaperoned Youth (ages 15–17), the program fee is
                applied from SpecialService.
   ========================================================= */

/* =========================================================
   Q2c — STORED PROCEDURE
   sp_GetVoyageRevenueSummary

   Purpose:
   Returns a complete revenue summary for a given voyage, broken
   down by cabin category. This is more maintainable than embedding
   the multi-join logic in every report query, ensures consistent
   filtering (only Confirmed/Completed bookings counted), and
   allows front-end tools to call a single parameterised entry
   point rather than constructing ad-hoc SQL.

   Usage:  CALL sp_GetVoyageRevenueSummary(1);
   ========================================================= */

DELIMITER $$

CREATE PROCEDURE sp_GetVoyageRevenueSummary(IN p_VoyageID INT)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM CruiseVoyage WHERE VoyageID = p_VoyageID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Voyage not found.';
    END IF;

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
    WHERE v.VoyageID = p_VoyageID
    GROUP BY
        s.ShipID, co.OperatorName, r.RouteName, r.RouteType,
        v.DepartureDateTime, v.ArrivalDateTime,
        cc.CabinCategoryID, cc.CategoryName
    ORDER BY cc.CabinCategoryID;
END$$

DELIMITER ;

/* =========================================================
   Q2d — QUERIES
   ========================================================= */

-- -------------------------------------------------------
-- Query i
-- Round-trip sailings for given dates, departure port,
-- and arrival port.
-- (For round-trips the departure and arrival port are the
--  same home port; we filter on first stop = last stop.)
-- -------------------------------------------------------
-- Round-trip sailings only
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

WHERE p_dep.PortID = p_arr.PortID
  AND DATE(v.DepartureDateTime) 
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
SELECT
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
  AND DATE(b.BookingDate) BETWEEN '2026-01-01' AND '2026-12-31'
  AND b.BookingStatus IN ('Confirmed', 'Completed')
GROUP BY co.OperatorID, co.OperatorName
ORDER BY TotalBookings DESC
LIMIT 1;

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
GROUP BY ac.CategoryName WITH ROLLUP;

-- -------------------------------------------------------
-- Query vi
-- Cruise operator offering the maximum number of
-- multi-destination itineraries, with departure and
-- final arrival port names.
-- -------------------------------------------------------
SELECT
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
ORDER BY MultiDestinationVoyages DESC
LIMIT 1;

-- -------------------------------------------------------
-- Query vii  (additional — own design)
-- Passenger lifetime value report: total fare spend,
-- total excursion spend, and combined lifetime value
-- for each passenger who has at least one booking.
-- Useful for loyalty programme targeting and marketing.
-- Uses a LEFT JOIN to capture passengers with no
-- excursion purchases (NULL → 0 via COALESCE).
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

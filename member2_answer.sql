/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    Member 2 — Answers

    Covers:
    - Q1b : Optimization Strategy (indexes + justification)
    - Q1c : Constraint & Trigger description
    - Q2c : Stored Procedure
    - Q2d : Queries viii – xiv
*/

USE GLCL_DB;

/* =========================================================
   Q1b — OPTIMIZATION STRATEGY
   Member 2 Strategy: Selective denormalization for historical
   price preservation in PassengerSpecialService.

   The AppliedFee column records the fee charged to a passenger
   at the time of their service request, independently of any
   future changes to SpecialService.Fee. This is not a 3NF
   violation — AppliedFee captures a point-in-time fact
   functionally dependent on the booking event, not on ServiceID.
   A BEFORE INSERT trigger populates it automatically from
   SpecialService.Fee at insert time.
   Full justification: see Optimization_Constraints_Triggers.md
   ========================================================= */

/* =========================================================
   Q1c — CONSTRAINT DESCRIPTION
   Constraint: CK_CruiseRoute_RouteType  (CruiseRoute table)

   Definition:
       CHECK (RouteType IN ('One-way', 'Round-trip', 'Multi-destination'))

   Justification:
   GLCL offers exactly three itinerary types as defined in the
   business specification. Restricting RouteType to these three
   values prevents data entry errors (e.g. typos like 'Roundtrip'
   or 'one way') that would cause queries filtering on RouteType
   to miss rows. This is enforced at the database engine level,
   making it independent of any application layer validation.

   Trigger Description: TR_BookingCabin_BI_PreventDoubleBooking
   Fires   : BEFORE INSERT on BookingCabin
   Purpose : Prevents the same cabin from being assigned to two
             different confirmed bookings on the same voyage.
             Steps:
             1. Retrieves the ShipID for the booking's voyage.
             2. Retrieves the ShipID of the cabin being added.
             3. Rejects the insert if the two ShipIDs differ —
                ensuring a cabin can only be assigned to its
                own ship's voyage.
             4. Checks whether the cabin already appears in any
                Pending or Confirmed BookingCabin record for the
                same voyage; rejects with a clear error if so.
             This prevents double-booking at the database level
             even if two sessions race to book the same cabin
             simultaneously.
   ========================================================= */

/* =========================================================
   Q2c — STORED PROCEDURE
   sp_SearchAvailableCabins

   Purpose:
   Returns all unbooked cabins for a given voyage, optionally
   filtered by cabin category. Including the Adult base fare
   allows the front-end to display pricing alongside
   availability in a single call. This avoids two round-trips
   (one for availability, one for fares) and encapsulates
   the "not in any active booking" subquery in one reusable
   location.

   Usage:
       CALL sp_SearchAvailableCabins(1, 'Suite');
       CALL sp_SearchAvailableCabins(2, NULL);  -- all categories
   ========================================================= */

DELIMITER $$

CREATE PROCEDURE sp_SearchAvailableCabins(
    IN p_VoyageID     INT,
    IN p_CategoryName VARCHAR(50)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM CruiseVoyage WHERE VoyageID = p_VoyageID) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Voyage not found.';
    END IF;

    SELECT
        c.CabinID,
        c.CabinNumber,
        c.DeckNumber,
        cc.CategoryName             AS CabinCategory,
        c.MaxOccupancy,
        c.IsWheelchairAccessible,
        COALESCE(fr.BaseFare, 0)    AS AdultBaseFare
    FROM Cabin         c
    INNER JOIN CruiseVoyage  v    ON v.VoyageID       = p_VoyageID
        AND v.ShipID = c.ShipID
    INNER JOIN CabinCategory cc   ON c.CabinCategoryID = cc.CabinCategoryID
    -- Fetch the current Adult fare for display purposes
    LEFT JOIN FareRule       fr   ON fr.VoyageID       = p_VoyageID
        AND fr.CabinCategoryID = c.CabinCategoryID
        AND fr.EffectiveFrom  <= CURDATE()
        AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= CURDATE())
    LEFT JOIN AgeCategory    ac   ON fr.AgeCategoryID  = ac.AgeCategoryID
        AND ac.CategoryName = 'Adult'
    WHERE (p_CategoryName IS NULL OR cc.CategoryName = p_CategoryName)
      AND c.CabinID NOT IN (
              SELECT bc.CabinID
              FROM   BookingCabin bc
              INNER JOIN Booking b ON bc.BookingID = b.BookingID
              WHERE  b.VoyageID     = p_VoyageID
                AND  b.BookingStatus IN ('Pending', 'Confirmed')
          )
    ORDER BY cc.CategoryName, c.DeckNumber, c.CabinNumber;
END$$

DELIMITER ;

/* =========================================================
   Q2d — QUERIES
   ========================================================= */

-- -------------------------------------------------------
-- Query viii
-- Ship code, regular fare, and discounted fare (15%
-- early-bird) for the Suite cabin category.
-- Labels: Ship Code | Regular Suite Fare | Discounted Suite Fare
-- (Adult fare used as the reference fare.)
-- -------------------------------------------------------
SELECT
    s.ShipID                                AS 'Ship Code',
    fr.BaseFare                             AS 'Regular Suite Fare',
    ROUND(fr.BaseFare * 0.85, 2)            AS 'Discounted Suite Fare'
FROM FareRule      fr
INNER JOIN CabinCategory cc ON fr.CabinCategoryID = cc.CabinCategoryID
    AND cc.CategoryName = 'Suite'
INNER JOIN AgeCategory   ac ON fr.AgeCategoryID   = ac.AgeCategoryID
    AND ac.CategoryName = 'Adult'
INNER JOIN CruiseVoyage  v  ON fr.VoyageID        = v.VoyageID
INNER JOIN CruiseShip    s  ON v.ShipID           = s.ShipID
WHERE fr.EffectiveFrom <= CURDATE()
  AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= CURDATE())
ORDER BY s.ShipID, fr.VoyageID;

-- -------------------------------------------------------
-- Query ix
-- Sorted sailing details to a given destination port code,
-- shortest duration voyage displayed first.
-- -------------------------------------------------------
SELECT
    v.VoyageID,
    s.ShipName,
    co.OperatorName,
    r.RouteName,
    r.RouteType,
    p_dest.PortName         AS DestinationPort,
    p_dest.Country          AS DestinationCountry,
    v.DepartureDateTime,
    v.ArrivalDateTime,
    v.VoyageLengthDays      AS DurationDays,
    v.VoyageStatus
FROM CruiseVoyage  v
INNER JOIN CruiseShip     s       ON v.ShipID     = s.ShipID
INNER JOIN CruiseOperator co      ON s.OperatorID = co.OperatorID
INNER JOIN CruiseRoute    r       ON v.RouteID    = r.RouteID
INNER JOIN RoutePort      rp      ON r.RouteID    = rp.RouteID
INNER JOIN Port           p_dest  ON rp.PortID    = p_dest.PortID
WHERE p_dest.PortName = 'Singapore Cruise Centre'
GROUP BY
    v.VoyageID, s.ShipName, co.OperatorName, r.RouteName, r.RouteType,
    p_dest.PortName, p_dest.Country,
    v.DepartureDateTime, v.ArrivalDateTime,
    v.VoyageLengthDays, v.VoyageStatus
ORDER BY v.VoyageLengthDays ASC;

-- -------------------------------------------------------
-- Query x
-- Types of specialty dining options offered on specific ships.
-- -------------------------------------------------------
SELECT
    s.ShipName,
    sdt.TypeName        AS SpecialtyDiningType,
    sdt.Description     AS SpecialtyDescription
FROM ShipSpecialtyDining   ssd
INNER JOIN CruiseShip        s   ON ssd.ShipID             = s.ShipID
INNER JOIN SpecialtyDiningType sdt ON ssd.SpecialtyDiningTypeID = sdt.SpecialtyDiningTypeID
WHERE s.ShipName = 'GLCL Majesty'
ORDER BY sdt.TypeName;

-- -------------------------------------------------------
-- Query xi
-- Names of countries where GLCL ships are scheduled to dock.
-- Duplicate country names eliminated.
-- -------------------------------------------------------
SELECT DISTINCT
    p.Country
FROM Port           p
INNER JOIN RoutePort    rp  ON p.PortID    = rp.PortID
INNER JOIN CruiseRoute  r   ON rp.RouteID  = r.RouteID
INNER JOIN CruiseVoyage v   ON r.RouteID   = v.RouteID
INNER JOIN CruiseShip   s   ON v.ShipID    = s.ShipID
WHERE v.VoyageStatus IN ('Scheduled', 'Boarding', 'Departed')
ORDER BY p.Country;

-- -------------------------------------------------------
-- Query xii
-- Total voyages scheduled per cruise operator for a given
-- departure date. Detailed breakdown + grand total via ROLLUP.
-- -------------------------------------------------------
SELECT
    COALESCE(co.OperatorName, 'All Operators') AS CruiseOperator,
    COUNT(v.VoyageID)                           AS TotalVoyages
FROM CruiseVoyage  v
INNER JOIN CruiseShip     s  ON v.ShipID     = s.ShipID
INNER JOIN CruiseOperator co ON s.OperatorID = co.OperatorID
WHERE DATE(v.DepartureDateTime) = '2026-09-10'
GROUP BY co.OperatorName WITH ROLLUP;

-- -------------------------------------------------------
-- Query xiii
-- Onshore excursion options available for a given ship's
-- itinerary (all voyages that ship is scheduled for).
-- -------------------------------------------------------
SELECT
    s.ShipName,
    v.VoyageID,
    v.DepartureDateTime,
    p_stop.PortName         AS ExcursionPort,
    p_stop.Country,
    rp.StopSequence,
    e.ExcursionName,
    e.Description           AS ExcursionDescription,
    e.DurationHours,
    e.Price                 AS ExcursionPrice,
    ve.AvailableSlots
FROM VoyageExcursion ve
INNER JOIN CruiseVoyage v      ON ve.VoyageID     = v.VoyageID
INNER JOIN CruiseShip   s      ON v.ShipID        = s.ShipID
INNER JOIN Excursion    e      ON ve.ExcursionID  = e.ExcursionID
INNER JOIN RoutePort    rp     ON ve.RoutePortID  = rp.RoutePortID
INNER JOIN Port         p_stop ON rp.PortID       = p_stop.PortID
WHERE s.ShipName = 'GLCL Majesty'
ORDER BY v.DepartureDateTime, rp.StopSequence, e.ExcursionName;

-- -------------------------------------------------------
-- Query xiv  (additional — own design)
-- Cabin occupancy rate per voyage.
-- Shows total cabins available on each ship, how many are
-- booked, and the occupancy percentage. Useful for revenue
-- management and capacity planning decisions.
-- -------------------------------------------------------
SELECT
    v.VoyageID,
    s.ShipName,
    co.OperatorName,
    r.RouteType,
    v.DepartureDateTime,
    COUNT(DISTINCT c.CabinID)                               AS TotalCabinsOnShip,
    COUNT(DISTINCT CASE WHEN b.BookingID IS NOT NULL THEN c.CabinID END) AS BookedCabins,
        COUNT(DISTINCT c.CabinID)
        - COUNT(DISTINCT CASE WHEN b.BookingID IS NOT NULL THEN c.CabinID END) AS AvailableCabins,
        
    ROUND(
        COUNT(DISTINCT CASE WHEN b.BookingID IS NOT NULL THEN c.CabinID END) * 100.0
        / NULLIF(COUNT(DISTINCT c.CabinID), 0)
    , 2)                                                    AS OccupancyRatePct
FROM CruiseVoyage  v
INNER JOIN CruiseShip     s    ON v.ShipID         = s.ShipID
INNER JOIN CruiseOperator co   ON s.OperatorID     = co.OperatorID
INNER JOIN CruiseRoute    r    ON v.RouteID        = r.RouteID
INNER JOIN Cabin          c    ON s.ShipID         = c.ShipID
LEFT JOIN  BookingCabin   bc   ON c.CabinID        = bc.CabinID
LEFT JOIN  Booking        b    ON bc.BookingID     = b.BookingID
    AND b.VoyageID    = v.VoyageID
    AND b.BookingStatus IN ('Confirmed', 'Completed')
GROUP BY
    v.VoyageID, s.ShipName, co.OperatorName, r.RouteType, v.DepartureDateTime
ORDER BY v.DepartureDateTime, OccupancyRatePct DESC;

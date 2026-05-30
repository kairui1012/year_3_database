/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    Member 3 — Q1b: Optimization Strategy

    Strategy: Reporting views to encapsulate repeated deep join
    chains across the schema.

    Two views are introduced:
    - vw_BookingPassengerDetails  : full 10-table passenger booking
      detail path including computed age at departure.
    - vw_VoyageCabinAvailability  : cabin availability per voyage
      using a LEFT JOIN derived table (not a correlated subquery).

    SQL Server can optimize predicates through views, so Member 1's
    composite indexes (IDX_BookingPassenger_Cabin_Booking,
    IDX_Booking_Voyage_Status, IDX_BookingCabin_Cabin_Booking)
    accelerate the view joins automatically.

    Full justification: see docs/Optimization_Constraints_Triggers.md
*/

USE GLCL_DB;

/* =========================================================
   Q1b — OPTIMIZATION STRATEGY
   ========================================================= */

-- Encapsulates the full 10-table passenger booking detail path.
IF OBJECT_ID('vw_BookingPassengerDetails', 'V') IS NOT NULL
    DROP VIEW vw_BookingPassengerDetails;

EXEC(N'CREATE VIEW vw_BookingPassengerDetails AS
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
    dbo.fn_CalculateAge(p.DateOfBirth, CAST(v.DepartureDateTime AS DATE)) AS AgeAtDeparture,
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
INNER JOIN AgeCategory   ac  ON bp.AgeCategoryID  = ac.AgeCategoryID;');

-- Uses a LEFT JOIN derived table instead of a correlated EXISTS
-- subquery: active bookings are scanned once and joined, avoiding
-- a per-cabin-row sub-select over the full BookingCabin table.
IF OBJECT_ID('vw_VoyageCabinAvailability', 'V') IS NOT NULL
    DROP VIEW vw_VoyageCabinAvailability;

EXEC(N'CREATE VIEW vw_VoyageCabinAvailability AS
SELECT
    v.VoyageID,
    s.ShipName,
    r.RouteName,
    c.CabinID,
    c.CabinNumber,
    cc.CategoryName AS CabinCategory,
    c.MaxOccupancy,
    CASE
        WHEN active.CabinID IS NOT NULL THEN ''Booked''
        ELSE ''Available''
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
    WHERE  b.BookingStatus IN (''Pending'', ''Confirmed'')
) active ON active.CabinID  = c.CabinID
        AND active.VoyageID = v.VoyageID;');

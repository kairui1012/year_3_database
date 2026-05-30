/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    Member 3 — Answers

    Covers:
    - Q1c : Constraint & Trigger description
    - Q2c : Stored Procedure
    - Q2d : Queries xv – xxi
*/

USE GLCL_DB;

/* =========================================================
   Q1c — CONSTRAINT DESCRIPTION
   Constraint: CK_BookingPassenger_InfantBedOption
               (BookingPassenger table)

   Definition:
       CHECK (InfantBedOption IN ('SharedBed', 'Cot', 'NotApplicable'))

   Justification:
   The business rules specify exactly two infant sleeping
   arrangements that carry different pricing:
     - SharedBed : charged 15 % of the adult fare
     - Cot       : charged 50 % of the child fare
   'NotApplicable' is required for all non-infant passengers so
   the column is never left ambiguous. Without this CHECK, a data
   entry error (e.g. NULL or a typo) would cause the fare
   calculation in the trigger to silently produce an incorrect
   result. The constraint eliminates that risk at the engine level
   independently of the application layer.

   Trigger Description: TR_BookingCancellation_BI_ApplyPenalty
   Fires   : BEFORE INSERT on BookingCancellation
   Purpose : Automatically calculates the penalty and refund
             amounts whenever a cancellation record is created,
             so the business rule (48-hour full forfeit) cannot
             be bypassed.
             Steps:
             1. Retrieves the voyage departure time and booking
                total for the booking being cancelled.
             2. Joins CancellationPolicy for the operator to find
                the applicable penalty rule.
             3. Calculates hours remaining until departure.
             4. If ≤ 48 hours and policy is FullForfeit, sets
                PenaltyAmount = TotalAmount and RefundAmount = 0.
             5. If policy is Percentage, calculates proportional
                penalty and refund.
             6. If policy is FixedAmount, caps penalty at the
                booking total.
             7. If no policy row matches, full refund is given.
             A companion AFTER INSERT trigger then sets
             Booking.BookingStatus = 'Cancelled' automatically.
   ========================================================= */

/* =========================================================
   Q2c — STORED PROCEDURE
   sp_ProcessCancellation

   Purpose:
   Provides a single, validated entry point for cancelling a
   booking. Rather than calling INSERT on BookingCancellation
   directly (which would bypass status and departure checks
   at the application layer), this procedure:
     1. Validates the booking exists and is in a cancellable
        state (not already Cancelled or Completed).
     2. Validates that the voyage has not already departed.
     3. Inserts the BookingCancellation row (the existing
        BEFORE INSERT trigger then handles penalty/refund
        calculation and the AFTER INSERT trigger updates
        Booking.BookingStatus).
     4. Returns the calculated PenaltyAmount and RefundAmount
        as OUT parameters so the caller can display them to
        the user immediately.

   Usage:
       EXEC sp_ProcessCancellation
            @BookingID = 1,
            @Reason = 'Change of plans',
            @ProcessedBy = 'Agent01',
            @PenaltyAmt = @penalty OUTPUT,
            @RefundAmt = @refund OUTPUT;
       SELECT @penalty AS Penalty, @refund AS Refund;
   ========================================================= */

IF OBJECT_ID('sp_ProcessCancellation', 'P') IS NOT NULL
    DROP PROCEDURE sp_ProcessCancellation;

EXEC(N'CREATE PROCEDURE sp_ProcessCancellation
    @BookingID   INT,
    @Reason      VARCHAR(255),
    @ProcessedBy VARCHAR(100),
    @PenaltyAmt  DECIMAL(12,2) OUTPUT,
    @RefundAmt   DECIMAL(12,2) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BookingStatus  VARCHAR(30);
    DECLARE @DepartureTime  DATETIME;
    DECLARE @HoursLeft      INT;

    -- Step 1: fetch booking state
    SELECT @BookingStatus = b.BookingStatus,
           @DepartureTime = v.DepartureDateTime
    FROM   Booking       b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE  b.BookingID = @BookingID;

    IF @BookingStatus IS NULL
        THROW 50000, ''Booking not found.'', 1;

    -- Step 2: reject if already in a terminal state
    IF @BookingStatus IN (''Cancelled'', ''Completed'')
        THROW 50000, ''This booking cannot be cancelled in its current status.'', 1;

    -- Step 3: reject if voyage has already departed
    SET @HoursLeft = DATEDIFF(HOUR, GETDATE(), @DepartureTime);

    IF @HoursLeft < 0
        THROW 50000, ''Cannot cancel a voyage that has already departed.'', 1;

    -- Step 4: insert cancellation — triggers handle penalty calc + status update
    INSERT INTO BookingCancellation (BookingID, Reason, ProcessedBy)
    VALUES (@BookingID, @Reason, @ProcessedBy);

    -- Step 5: return the calculated amounts to the caller
    SELECT @PenaltyAmt = PenaltyAmount,
           @RefundAmt = RefundAmount
    FROM   BookingCancellation
    WHERE  BookingID = @BookingID;
END;
');

/* =========================================================
   Q2d — QUERIES
   ========================================================= */

-- -------------------------------------------------------
-- Query xv
-- Min, max, and average voyage duration (in days) for
-- sailings to a given destination port code.
-- Column headings: Minimum Duration | Maximum Duration |
--                  Average Duration
-- -------------------------------------------------------
SELECT
    MIN(v.VoyageLengthDays)              AS 'Minimum Duration',
    MAX(v.VoyageLengthDays)              AS 'Maximum Duration',
    ROUND(AVG(v.VoyageLengthDays), 2)    AS 'Average Duration'
FROM CruiseVoyage  v
INNER JOIN CruiseRoute r   ON v.RouteID  = r.RouteID
INNER JOIN RoutePort   rp  ON r.RouteID  = rp.RouteID
INNER JOIN Port        p   ON rp.PortID  = p.PortID
WHERE p.PortName = 'Singapore Cruise Centre';

-- -------------------------------------------------------
-- Query xvi
-- Departure date, number of booked passengers in the party,
-- and cabin category name for a specifically given passenger ID.
-- "Party" = all passengers sharing the same booking.
-- -------------------------------------------------------
SELECT
    v.DepartureDateTime                             AS DepartureDate,
    party.PassengersInParty,
    cc.CategoryName                                 AS CabinCategory
FROM BookingPassenger  bp
INNER JOIN Booking          b        ON bp.BookingID       = b.BookingID
INNER JOIN CruiseVoyage     v        ON b.VoyageID         = v.VoyageID
INNER JOIN BookingCabin     bc       ON bp.BookingCabinID  = bc.BookingCabinID
INNER JOIN Cabin             c       ON bc.CabinID         = c.CabinID
INNER JOIN CabinCategory     cc      ON c.CabinCategoryID  = cc.CabinCategoryID
-- Count the full party once per booking (no cabin-cross inflation)
INNER JOIN (
    SELECT BookingID, COUNT(*) AS PassengersInParty
    FROM   BookingPassenger
    GROUP  BY BookingID
) party ON party.BookingID = b.BookingID
WHERE bp.PassengerID = 1
GROUP BY v.DepartureDateTime, cc.CategoryName, party.PassengersInParty;

-- -------------------------------------------------------
-- Query xvii
-- Excursions with no sales.
-- An excursion is considered unsold if it has no
-- BookingExcursion record with status Booked or Completed.
-- -------------------------------------------------------
SELECT
    e.ExcursionID,
    e.ExcursionName,
    p.PortName,
    p.Country,
    e.DurationHours,
    e.Price
FROM Excursion e
INNER JOIN Port p ON e.PortID = p.PortID
WHERE e.ExcursionID NOT IN (
    SELECT ve.ExcursionID
    FROM   VoyageExcursion  ve
    INNER JOIN BookingExcursion be ON ve.VoyageExcursionID = be.VoyageExcursionID
    WHERE  be.ExcursionStatus IN ('Booked', 'Completed')
)
ORDER BY p.Country, e.ExcursionName;

-- -------------------------------------------------------
-- Query xviii
-- Details of passengers booked through a specified cruise
-- operator on a given date for multi-destination island-
-- hopping itineraries.
-- -------------------------------------------------------
SELECT
    p.PassengerID,
    p.FullName,
    p.PassportNo,
    p.Nationality,
    p.ContactNo,
    b.BookingID,
    b.BookingDate,
    b.BookingStatus,
    co.OperatorName,
    r.RouteName                     AS Itinerary,
    v.DepartureDateTime
FROM Passenger      p
INNER JOIN BookingPassenger bp ON p.PassengerID    = bp.PassengerID
INNER JOIN Booking          b  ON bp.BookingID     = b.BookingID
INNER JOIN CruiseVoyage     v  ON b.VoyageID       = v.VoyageID
INNER JOIN CruiseShip       s  ON v.ShipID         = s.ShipID
INNER JOIN CruiseOperator   co ON s.OperatorID     = co.OperatorID
INNER JOIN CruiseRoute      r  ON v.RouteID        = r.RouteID
WHERE co.OperatorName  = 'Global Luxury Cruise Lines'
  AND CAST(b.BookingDate AS DATE) = '2026-07-01'
  AND r.RouteType        = 'Multi-destination'
ORDER BY p.FullName;

-- -------------------------------------------------------
-- Query xix
-- Total passengers requesting wheelchair assistance per
-- cruise operator for a given departure date.
-- Detailed breakdown per operator + grand total via ROLLUP.
-- Wheelchair assistance is tracked via PassengerSpecialService
-- linked to SpecialService where ServiceType = 'Accessibility'
-- or 'Mobility'.
-- -------------------------------------------------------
SELECT
    COALESCE(co.OperatorName, 'All Operators')  AS CruiseOperator,
    COUNT(DISTINCT pss.BookingPassengerID)       AS WheelchairPassengers
FROM PassengerSpecialService  pss
INNER JOIN SpecialService     ss  ON pss.ServiceID         = ss.ServiceID
INNER JOIN BookingPassenger   bp  ON pss.BookingPassengerID = bp.BookingPassengerID
INNER JOIN Booking            b   ON bp.BookingID          = b.BookingID
INNER JOIN CruiseVoyage       v   ON b.VoyageID            = v.VoyageID
INNER JOIN CruiseShip         s   ON v.ShipID              = s.ShipID
INNER JOIN CruiseOperator     co  ON s.OperatorID          = co.OperatorID
WHERE ss.ServiceType IN ('Accessibility', 'Mobility')
  AND CAST(v.DepartureDateTime AS DATE) = '2026-08-01'
  AND pss.RequestStatus IN ('Requested', 'Approved', 'Completed')
GROUP BY ROLLUP(co.OperatorName);

-- -------------------------------------------------------
-- Query xx
-- Details of passengers who have availed the Chaperoned
-- Youth extra service for a given sailing on a specified date.
-- -------------------------------------------------------
SELECT
    p.PassengerID,
    p.FullName,
    p.DateOfBirth,
    dbo.fn_CalculateAge(p.DateOfBirth, CAST(v.DepartureDateTime AS DATE))   AS AgeAtDeparture,
    b.BookingID,
    b.BookingDate,
    co.OperatorName,
    v.VoyageID,
    v.DepartureDateTime,
    bp.DailySupervisionFee,
    v.VoyageLengthDays,
    ROUND(bp.DailySupervisionFee * v.VoyageLengthDays, 2)       AS TotalSupervisionFee
FROM BookingPassenger  bp
INNER JOIN Passenger      p   ON bp.PassengerID = p.PassengerID
INNER JOIN Booking        b   ON bp.BookingID   = b.BookingID
INNER JOIN CruiseVoyage   v   ON b.VoyageID     = v.VoyageID
INNER JOIN CruiseShip     s   ON v.ShipID       = s.ShipID
INNER JOIN CruiseOperator co  ON s.OperatorID   = co.OperatorID
WHERE bp.IsChaperonedYouth = 1
  AND v.VoyageID           = 2
  AND CAST(v.DepartureDateTime AS DATE) = '2026-09-10'
ORDER BY p.FullName;

-- -------------------------------------------------------
-- Query xxi  (additional — own design)
-- Cancellation revenue impact analysis by cruise operator.
-- Shows total cancellations, penalty fees retained,
-- refunds issued, and the percentage of original booking
-- value that was retained as penalty income.
-- Useful for the finance team to monitor cancellation
-- policy effectiveness and refund exposure.
-- -------------------------------------------------------
SELECT
    co.OperatorName,
    COUNT(bc.CancellationID)                                AS TotalCancellations,
    SUM(b.TotalAmount)                                      AS TotalOriginalValue,
    SUM(bc.PenaltyAmount)                                   AS TotalPenaltiesRetained,
    SUM(bc.RefundAmount)                                    AS TotalRefundsIssued,
    ROUND(
        SUM(bc.PenaltyAmount) * 100.0
        / NULLIF(SUM(b.TotalAmount), 0)
    , 2)                                                    AS PenaltyRetentionPct,
    ROUND(
        SUM(bc.RefundAmount) * 100.0
        / NULLIF(SUM(b.TotalAmount), 0)
    , 2)                                                    AS RefundRatePct
FROM BookingCancellation  bc
INNER JOIN Booking        b   ON bc.BookingID  = b.BookingID
INNER JOIN CruiseVoyage   v   ON b.VoyageID   = v.VoyageID
INNER JOIN CruiseShip     s   ON v.ShipID     = s.ShipID
INNER JOIN CruiseOperator co  ON s.OperatorID = co.OperatorID
GROUP BY co.OperatorID, co.OperatorName
ORDER BY TotalPenaltiesRetained DESC;

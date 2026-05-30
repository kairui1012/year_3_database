/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    Q2c - Stored Procedure

    Object:
      sp_GetPassengerBookings

    Purpose:
      Returns all bookings for one passenger, including voyage,
      ship, cabin, booking status, and fare paid. Used by front-desk
      staff and the customer "My Trips" page.

    Why a stored procedure:
      - Keeps the six-table booking lookup in one reusable place.
      - Accepts @PassengerID directly, so the filter is applied before
        the full result set is produced.
      - Allows input validation with THROW before returning data.
      - Can be granted with EXECUTE permission without exposing direct
        SELECT rights on the underlying tables.

    Example:
      EXEC sp_GetPassengerBookings @PassengerID = 1;
*/

USE GLCL_DB;
GO

IF OBJECT_ID('sp_GetPassengerBookings', 'P') IS NOT NULL
    DROP PROCEDURE sp_GetPassengerBookings;
GO

CREATE PROCEDURE sp_GetPassengerBookings
    @PassengerID INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Guard clause: the caller must provide an existing passenger.
    IF NOT EXISTS (SELECT 1 FROM Passenger WHERE PassengerID = @PassengerID)
        THROW 50000, 'Passenger not found.', 1;

    -- Passenger booking history, newest voyage first.
    SELECT
        b.BookingID,
        b.BookingDate,
        b.BookingStatus,
        co.OperatorName,
        s.ShipName,
        r.RouteName,
        v.DepartureDateTime,
        v.ArrivalDateTime,
        c.CabinNumber,
        cc.CategoryName        AS CabinCategory,
        bp.FinalFare           AS FarePaid
    FROM BookingPassenger   bp
    INNER JOIN Booking        b   ON bp.BookingID      = b.BookingID
    INNER JOIN CruiseVoyage   v   ON b.VoyageID        = v.VoyageID
    INNER JOIN CruiseShip     s   ON v.ShipID          = s.ShipID
    INNER JOIN CruiseOperator co  ON s.OperatorID      = co.OperatorID
    INNER JOIN CruiseRoute    r   ON v.RouteID         = r.RouteID
    INNER JOIN BookingCabin   bc  ON bp.BookingCabinID = bc.BookingCabinID
    INNER JOIN Cabin          c   ON bc.CabinID        = c.CabinID
    INNER JOIN CabinCategory  cc  ON c.CabinCategoryID = cc.CabinCategoryID
    WHERE bp.PassengerID = @PassengerID
    ORDER BY v.DepartureDateTime DESC;
END;
GO

/* Demo */
EXEC sp_GetPassengerBookings @PassengerID = 1;

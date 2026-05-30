/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    Member 2 — Q1b: Optimization Strategy

    Strategy: Selective denormalization for historical price preservation.

    PassengerSpecialService.Fee stores the fee charged at the moment
    of booking, not a live reference to SpecialService.Fee.
    A BEFORE INSERT trigger (TR_PassengerSpecialService_BI_SnapFee)
    automatically snapshots the catalogue price at insert time so
    historical billing records are never corrupted by future price changes.

    Full justification: see docs/Optimization_Constraints_Triggers.md
*/

USE GLCL_DB;

/* =========================================================
   Q1b — OPTIMIZATION STRATEGY
   ========================================================= */

-- Snapshot the catalogue fee at booking time so historical
-- records are never corrupted by future price-list changes.
IF OBJECT_ID('TR_PassengerSpecialService_BI_SnapFee', 'TR') IS NOT NULL
    DROP TRIGGER TR_PassengerSpecialService_BI_SnapFee;

EXEC(N'CREATE TRIGGER TR_PassengerSpecialService_BI_SnapFee
ON PassengerSpecialService
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        LEFT JOIN SpecialService ss ON ss.ServiceID = i.ServiceID
        WHERE ss.ServiceID IS NULL
    )
        THROW 50000, ''Referenced SpecialService not found.'', 1;

    INSERT INTO PassengerSpecialService (BookingPassengerID, ServiceID, RequestStatus, Fee)
    SELECT
        i.BookingPassengerID,
        i.ServiceID,
        COALESCE(i.RequestStatus, ''Requested''),
        ss.Fee
    FROM inserted i
    INNER JOIN SpecialService ss ON ss.ServiceID = i.ServiceID;
END;
');

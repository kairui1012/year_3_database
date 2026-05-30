/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    Member 1 — Q1b: Optimization Strategy

    Strategy: Composite indexes targeting the query paths
    executed inside the system's triggers, particularly
    TR_BookingPassenger_BI_ValidateRules (7 sub-queries per INSERT)
    and TR_BookingCabin_BI_PreventDoubleBooking.

    Run AFTER seed data is loaded so SQL Server builds each index
    in a single pass over the existing rows rather than updating
    it incrementally on every INSERT.
*/

USE GLCL_DB;

/* =========================================================
   Q1b — OPTIMIZATION STRATEGY
   ========================================================= */

-- Fare lookup: filters (VoyageID, CabinCategoryID, AgeCategoryID),
-- sorts EffectiveFrom DESC TOP 1. Without this, the fare trigger
-- performs a full scan of FareRule on every passenger insert.
CREATE INDEX IDX_FareRule_Voyage_Cabin_Age_Date
    ON FareRule (VoyageID, CabinCategoryID, AgeCategoryID, EffectiveFrom DESC);

-- Occupancy count: COUNT(*) WHERE BookingCabinID = ? fires on every
-- BookingPassenger insert. Also supports the booking ownership check.
CREATE INDEX IDX_BookingPassenger_Cabin_Booking
    ON BookingPassenger (BookingCabinID, BookingID);

-- Double-booking EXISTS check: seeks by CabinID, then uses BookingID
-- to join Booking without returning to the clustered row.
CREATE INDEX IDX_BookingCabin_Cabin_Booking
    ON BookingCabin (CabinID, BookingID);

-- Voyage manifest and conflict checks: VoyageID first (high selectivity),
-- BookingStatus second (6 distinct values, low selectivity).
CREATE INDEX IDX_Booking_Voyage_Status
    ON Booking (VoyageID, BookingStatus);

-- Cancellation trigger: SELECT TOP 1 ORDER BY HoursBeforeDeparture ASC
-- per operator. Index pre-sorts the range, eliminating a sort operation.
CREATE INDEX IDX_CancellationPolicy_Operator_Hours
    ON CancellationPolicy (OperatorID, HoursBeforeDeparture ASC);

-- Baggage limit lookup: filters OperatorID + date range on EffectiveFrom/EffectiveTo.
CREATE INDEX IDX_BaggageRule_Operator_Date
    ON BaggageRule (OperatorID, EffectiveFrom, EffectiveTo);

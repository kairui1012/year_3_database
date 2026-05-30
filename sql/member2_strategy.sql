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
DELIMITER $$

CREATE TRIGGER TR_PassengerSpecialService_BI_SnapFee
BEFORE INSERT ON PassengerSpecialService
FOR EACH ROW
BEGIN
    DECLARE v_CurrentFee DECIMAL(10,2);

    SELECT Fee
    INTO   v_CurrentFee
    FROM   SpecialService
    WHERE  ServiceID = NEW.ServiceID;

    IF v_CurrentFee IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Referenced SpecialService not found.';
    END IF;

    SET NEW.Fee = v_CurrentFee;
END$$

DELIMITER ;

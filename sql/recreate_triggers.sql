/*
 * recreate_triggers.sql
 * Drops and recreates all 6 triggers and fn_CalculateAge for GLCL_DB.
 * Run via CLI:  mysql -u root -p GLCL_DB < recreate_triggers.sql
 */

USE GLCL_DB;

-- Drop existing objects so re-runs are safe
DROP FUNCTION  IF EXISTS fn_CalculateAge;
DROP TRIGGER   IF EXISTS TR_BookingCabin_BI_PreventDoubleBooking;
DROP TRIGGER   IF EXISTS TR_BookingPassenger_BI_ValidateRules;
DROP TRIGGER   IF EXISTS TR_BookingBaggage_BI_ValidateLimit;
DROP TRIGGER   IF EXISTS TR_BookingCancellation_BI_ApplyPenalty;
DROP TRIGGER   IF EXISTS TR_BookingCancellation_AI_UpdateBookingStatus;
DROP TRIGGER   IF EXISTS TR_BookingPassenger_AI_UpdateBookingTotal;

DELIMITER $$

/* ============================================================
   SECTION 8: FUNCTION AND TRIGGERS
   ============================================================
   6 Schema Constraints (CHECK constraints in Sections 1–7):
     1. CK_Cabin_MaxOccupancy                  — enforces max 5 passengers per cabin
     2. CK_CruiseVoyage_ArrivalAfterDeparture  — arrival must be after departure
     3. CK_BookingPassenger_InfantBedOption    — valid bed options for infants
     4. CK_Booking_Status                      — restricts to valid booking states
     5. CK_CancellationPolicy_PenaltyType      — restricts to valid penalty types
     6. CK_AgeCategory_AgeRange                — ensures MinAge <= MaxAge

   6 Triggers (BEFORE/AFTER INSERT only):
     1. TR_BookingCabin_BI_PreventDoubleBooking
     2. TR_BookingPassenger_BI_ValidateRules
     3. TR_BookingBaggage_BI_ValidateLimit
     4. TR_BookingCancellation_BI_ApplyPenalty
     5. TR_BookingCancellation_AI_UpdateBookingStatus
     6. TR_BookingPassenger_AI_UpdateBookingTotal
   ============================================================ */
   
CREATE FUNCTION fn_CalculateAge(DateOfBirth DATE, ReferenceDate DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN TIMESTAMPDIFF(YEAR, DateOfBirth, ReferenceDate);
END$$

/* ---------------------------------------------------------------
   Trigger 1: TR_BookingCabin_BI_PreventDoubleBooking
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCabin_BI_PreventDoubleBooking
BEFORE INSERT ON BookingCabin
FOR EACH ROW
BEGIN
    DECLARE v_BookingShipID INT;
    DECLARE v_CabinShipID   INT;

    SELECT v.ShipID INTO v_BookingShipID
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = NEW.BookingID;

    SELECT ShipID INTO v_CabinShipID FROM Cabin WHERE CabinID = NEW.CabinID;

    IF v_BookingShipID <> v_CabinShipID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cabin must belong to the ship assigned to the booked voyage.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM BookingCabin bc
        INNER JOIN Booking b  ON bc.BookingID = b.BookingID
        INNER JOIN Booking nb ON NEW.BookingID = nb.BookingID
        WHERE bc.CabinID = NEW.CabinID
          AND b.VoyageID = nb.VoyageID
          AND b.BookingStatus  IN ('Pending', 'Confirmed')
          AND nb.BookingStatus IN ('Pending', 'Confirmed')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This cabin is already booked for the same voyage.';
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger 2: TR_BookingPassenger_BI_ValidateRules
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_BI_ValidateRules
BEFORE INSERT ON BookingPassenger
FOR EACH ROW
BEGIN
    DECLARE v_CabinBookingID  INT;
    DECLARE v_MaxOccupancy    INT;
    DECLARE v_OccupancyCount  INT;
    DECLARE v_PassengerAge    INT;
    DECLARE v_CategoryMin     INT;
    DECLARE v_CategoryMax     INT;
    DECLARE v_CategoryName    VARCHAR(30);
    DECLARE v_AllowsYouth     BOOLEAN;
    DECLARE v_HasGuardian     INT DEFAULT 0;
    DECLARE v_FareRuleID      INT;
    DECLARE v_BaseFare        DECIMAL(12,2);
    DECLARE v_AdultFare       DECIMAL(12,2);
    DECLARE v_ChildFare       DECIMAL(12,2);
    DECLARE v_SupervisionFee  DECIMAL(10,2);

    SELECT bc.BookingID, c.MaxOccupancy
    INTO v_CabinBookingID, v_MaxOccupancy
    FROM BookingCabin bc
    INNER JOIN Cabin c ON bc.CabinID = c.CabinID
    WHERE bc.BookingCabinID = NEW.BookingCabinID;

    IF v_CabinBookingID <> NEW.BookingID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BookingPassenger.BookingID must match BookingCabin.BookingID.';
    END IF;

    SELECT COUNT(*) INTO v_OccupancyCount
    FROM BookingPassenger WHERE BookingCabinID = NEW.BookingCabinID;

    IF v_OccupancyCount + 1 > v_MaxOccupancy OR v_OccupancyCount + 1 > 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A cabin can contain a maximum of 5 passengers only.';
    END IF;

    SELECT fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime)),
           ac.MinAge, ac.MaxAge, ac.CategoryName, co.AllowsChaperonedYouth
    INTO v_PassengerAge, v_CategoryMin, v_CategoryMax, v_CategoryName, v_AllowsYouth
    FROM Passenger p
    INNER JOIN Booking b         ON b.BookingID     = NEW.BookingID
    INNER JOIN CruiseVoyage v    ON b.VoyageID       = v.VoyageID
    INNER JOIN CruiseShip s      ON v.ShipID         = s.ShipID
    INNER JOIN CruiseOperator co ON s.OperatorID     = co.OperatorID
    INNER JOIN AgeCategory ac    ON ac.AgeCategoryID = NEW.AgeCategoryID
    WHERE p.PassengerID = NEW.PassengerID;

    IF v_PassengerAge < v_CategoryMin
       OR (v_CategoryMax IS NOT NULL AND v_PassengerAge > v_CategoryMax) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger age category must match the passenger age at voyage departure.';
    END IF;

    IF v_CategoryName = 'Infant' AND NEW.InfantBedOption NOT IN ('SharedBed', 'Cot') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Infant passengers must have either SharedBed or Cot as InfantBedOption.';
    END IF;

    IF v_CategoryName <> 'Infant' AND NEW.InfantBedOption <> 'NotApplicable' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InfantBedOption must be NotApplicable for non-infant passengers.';
    END IF;

    IF NEW.IsChaperonedYouth = TRUE
       AND (v_AllowsYouth = FALSE OR v_CategoryName <> 'Teen' OR v_PassengerAge NOT BETWEEN 15 AND 17) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Chaperoned Youth is only allowed for age 15 to 17 when the operator supports the program.';
    END IF;

    IF v_PassengerAge <= 17 AND NEW.IsChaperonedYouth = FALSE THEN
        SELECT COUNT(*) INTO v_HasGuardian
        FROM BookingPassenger bp
        INNER JOIN AgeCategory ac ON bp.AgeCategoryID = ac.AgeCategoryID
        WHERE bp.BookingID = NEW.BookingID AND bp.BookingCabinID = NEW.BookingCabinID
          AND ac.MinAge >= 18;

        IF v_HasGuardian = 0 THEN
            SELECT COUNT(*) INTO v_HasGuardian
            FROM BookingPassenger   guardian_bp
            INNER JOIN AgeCategory  guardian_ac ON guardian_bp.AgeCategoryID  = guardian_ac.AgeCategoryID
            INNER JOIN BookingCabin guardian_bc ON guardian_bp.BookingCabinID = guardian_bc.BookingCabinID
            INNER JOIN Booking      guardian_b  ON guardian_bc.BookingID      = guardian_b.BookingID
            INNER JOIN BookingCabin teen_bc     ON teen_bc.BookingCabinID     = NEW.BookingCabinID
            INNER JOIN CabinAdjacency ca        ON ca.CabinID       = teen_bc.CabinID
                                               AND ca.AdjacentCabinID = guardian_bc.CabinID
            INNER JOIN Booking      teen_b      ON teen_b.BookingID = NEW.BookingID
            WHERE guardian_b.VoyageID = teen_b.VoyageID
              AND guardian_b.BookingStatus IN ('Pending', 'Confirmed')
              AND guardian_ac.MinAge >= 18;
        END IF;

        IF v_HasGuardian = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Passengers aged 17 or below require an adult in the same or adjacent cabin unless approved for Chaperoned Youth.';
        END IF;
    END IF;

    IF NEW.IsChaperonedYouth = TRUE THEN
        SELECT COALESCE(MAX(Fee), 0) INTO v_SupervisionFee
        FROM SpecialService WHERE ServiceType = 'Chaperoned Youth';
        SET NEW.DailySupervisionFee = v_SupervisionFee;
    ELSE
        SET NEW.DailySupervisionFee = 0;
    END IF;

    IF v_CategoryName = 'Infant' THEN
        SELECT fr.BaseFare INTO v_AdultFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID        = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID  = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID          = bc.CabinID
        INNER JOIN AgeCategory ac  ON ac.AgeCategoryID   = fr.AgeCategoryID
        WHERE fr.VoyageID = b.VoyageID AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName = 'Adult'
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC LIMIT 1;

        IF v_AdultFare IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Adult fare rule is required to calculate SharedBed infant fare.';
        END IF;

        SELECT fr.BaseFare INTO v_ChildFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID        = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID  = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID          = bc.CabinID
        INNER JOIN AgeCategory ac  ON ac.AgeCategoryID   = fr.AgeCategoryID
        WHERE fr.VoyageID = b.VoyageID AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName = 'Child'
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC LIMIT 1;

        IF v_ChildFare IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Child fare rule is required to calculate Cot infant fare.';
        END IF;

        SET NEW.FareRuleID = NULL;
        SET NEW.FinalFare  = IF(NEW.InfantBedOption = 'SharedBed', v_AdultFare * 0.15, v_ChildFare * 0.50);

    ELSE
        SELECT fr.FareRuleID, fr.BaseFare INTO v_FareRuleID, v_BaseFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID        = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID  = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID          = bc.CabinID
        WHERE fr.VoyageID = b.VoyageID AND fr.CabinCategoryID = c.CabinCategoryID
          AND fr.AgeCategoryID = NEW.AgeCategoryID
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC LIMIT 1;

        IF v_BaseFare IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Fare rule is required for this voyage, cabin category, and age category.';
        END IF;

        SET NEW.FareRuleID = v_FareRuleID;
        SET NEW.FinalFare  = v_BaseFare;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger 3: TR_BookingBaggage_BI_ValidateLimit
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingBaggage_BI_ValidateLimit
BEFORE INSERT ON BookingBaggage
FOR EACH ROW
BEGIN
    DECLARE v_AllowedWeight DECIMAL(6,2);
    SELECT v.BaggageWeightLimitKG INTO v_AllowedWeight
    FROM BookingPassenger bp
    INNER JOIN Booking b      ON bp.BookingID = b.BookingID
    INNER JOIN CruiseVoyage v ON b.VoyageID   = v.VoyageID
    WHERE bp.BookingPassengerID = NEW.BookingPassengerID;
    SET NEW.IsOverLimit = NEW.WeightKG > v_AllowedWeight;
END$$

/* ---------------------------------------------------------------
   Trigger 4: TR_BookingCancellation_BI_ApplyPenalty
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCancellation_BI_ApplyPenalty
BEFORE INSERT ON BookingCancellation
FOR EACH ROW
BEGIN
    DECLARE v_DepartureTime DATETIME;
    DECLARE v_BookingTotal  DECIMAL(12,2);
    DECLARE v_HoursUntil    INT;
    DECLARE v_PenaltyType   VARCHAR(30) DEFAULT NULL;
    DECLARE v_PenaltyValue  DECIMAL(10,2) DEFAULT 0;
    DECLARE v_OperatorID    INT;

    SELECT v.DepartureDateTime, b.TotalAmount, s.OperatorID
    INTO v_DepartureTime, v_BookingTotal, v_OperatorID
    FROM Booking b
    JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    JOIN CruiseShip s   ON v.ShipID = s.ShipID
    WHERE b.BookingID = NEW.BookingID;

    IF v_DepartureTime IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid Booking or Voyage';
    END IF;

    SET v_HoursUntil = TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, v_DepartureTime);

    SELECT cp.PenaltyType, cp.PenaltyValue
    INTO v_PenaltyType, v_PenaltyValue
    FROM CancellationPolicy cp
    WHERE cp.OperatorID = v_OperatorID
      AND cp.HoursBeforeDeparture >= v_HoursUntil
    ORDER BY cp.HoursBeforeDeparture ASC
    LIMIT 1;

    IF v_PenaltyType IS NULL THEN
        SET v_PenaltyType  = 'Percentage';
        SET v_PenaltyValue = 0;
    END IF;

    IF v_HoursUntil <= 48 AND v_PenaltyType = 'FullForfeit' THEN
        SET NEW.PenaltyAmount = v_BookingTotal;
        SET NEW.RefundAmount  = 0;
    ELSEIF v_PenaltyType = 'Percentage' THEN
        SET NEW.PenaltyAmount = v_BookingTotal * (v_PenaltyValue / 100);
        SET NEW.RefundAmount  = v_BookingTotal - NEW.PenaltyAmount;
    ELSEIF v_PenaltyType = 'FixedAmount' THEN
        SET NEW.PenaltyAmount = LEAST(v_PenaltyValue, v_BookingTotal);
        SET NEW.RefundAmount  = v_BookingTotal - NEW.PenaltyAmount;
    ELSE
        SET NEW.PenaltyAmount = 0;
        SET NEW.RefundAmount  = v_BookingTotal;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger 5: TR_BookingCancellation_AI_UpdateBookingStatus
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCancellation_AI_UpdateBookingStatus
AFTER INSERT ON BookingCancellation
FOR EACH ROW
BEGIN
    UPDATE Booking SET BookingStatus = 'Cancelled' WHERE BookingID = NEW.BookingID;
END$$

/* ---------------------------------------------------------------
   Trigger 6: TR_BookingPassenger_AI_UpdateBookingTotal
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_AI_UpdateBookingTotal
AFTER INSERT ON BookingPassenger
FOR EACH ROW
BEGIN
    UPDATE Booking
    SET TotalAmount = (SELECT COALESCE(SUM(FinalFare), 0)
                       FROM BookingPassenger WHERE BookingID = NEW.BookingID)
    WHERE BookingID = NEW.BookingID;
END$$

DELIMITER ;

SELECT 'All 6 triggers and fn_CalculateAge recreated successfully.' AS Message;
SHOW TRIGGERS;

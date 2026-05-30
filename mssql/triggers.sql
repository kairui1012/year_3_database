/*
 * recreate_triggers_MSSQL.sql
 * Drops and recreates all 6 triggers and fn_CalculateAge for GLCL_DB.
 * Run via SSMS or sqlcmd:  sqlcmd -S <server> -d GLCL_DB -i recreate_triggers_MSSQL.sql
 *
 * Notes:
 *   - MySQL BEFORE INSERT triggers that modified NEW.* are converted to
 *     INSTEAD OF INSERT triggers; validation fires, then the trigger
 *     performs the actual INSERT with computed column values.
 *   - AFTER INSERT triggers remain AFTER INSERT.
 *   - SIGNAL SQLSTATE '45000' is replaced with THROW 50000, '...', 1.
 *   - Triggers operate on the inserted pseudo-table (single-row inserts assumed).
 */

USE GLCL_DB;

-- ============================================================
-- Drop existing objects so re-runs are safe
-- ============================================================
IF OBJECT_ID('dbo.fn_CalculateAge',                                    'FN') IS NOT NULL DROP FUNCTION  dbo.fn_CalculateAge;
IF OBJECT_ID('TR_BookingCabin_BI_PreventDoubleBooking',                'TR') IS NOT NULL DROP TRIGGER   TR_BookingCabin_BI_PreventDoubleBooking;
IF OBJECT_ID('TR_BookingPassenger_BI_ValidateRules',                   'TR') IS NOT NULL DROP TRIGGER   TR_BookingPassenger_BI_ValidateRules;
IF OBJECT_ID('TR_BookingBaggage_BI_ValidateLimit',                     'TR') IS NOT NULL DROP TRIGGER   TR_BookingBaggage_BI_ValidateLimit;
IF OBJECT_ID('TR_BookingCancellation_BI_ApplyPenalty',                 'TR') IS NOT NULL DROP TRIGGER   TR_BookingCancellation_BI_ApplyPenalty;
IF OBJECT_ID('TR_BookingCancellation_AI_UpdateBookingStatus',          'TR') IS NOT NULL DROP TRIGGER   TR_BookingCancellation_AI_UpdateBookingStatus;
IF OBJECT_ID('TR_BookingPassenger_AI_UpdateBookingTotal',              'TR') IS NOT NULL DROP TRIGGER   TR_BookingPassenger_AI_UpdateBookingTotal;

/* ============================================================
   TRIGGERS
   ============================================================
   6 Schema Constraints (CHECK constraints in Sections 1-7):
     1. CK_Cabin_MaxOccupancy                  - enforces max 5 passengers per cabin
     2. CK_CruiseVoyage_ArrivalAfterDeparture  - arrival must be after departure
     3. CK_BookingPassenger_InfantBedOption    - valid bed options for infants
     4. CK_Booking_Status                      - restricts to valid booking states
     5. CK_CancellationPolicy_PenaltyType      - restricts to valid penalty types
     6. CK_AgeCategory_AgeRange                - ensures MinAge <= MaxAge

   6 Triggers (INSTEAD OF INSERT / AFTER INSERT):
     1. TR_BookingCabin_BI_PreventDoubleBooking
     2. TR_BookingPassenger_BI_ValidateRules
     3. TR_BookingBaggage_BI_ValidateLimit
     4. TR_BookingCancellation_BI_ApplyPenalty
     5. TR_BookingCancellation_AI_UpdateBookingStatus
     6. TR_BookingPassenger_AI_UpdateBookingTotal
   ============================================================ */

/* ---------------------------------------------------------------
   Helper function: fn_CalculateAge
   Replicates MySQL DATEDIFF(YEAR, ...) - subtracts 1 if the
   birthday has not yet occurred in the reference year.
   --------------------------------------------------------------- */
EXEC(N'CREATE FUNCTION dbo.fn_CalculateAge(
    @DateOfBirth   DATE,
    @ReferenceDate DATE
)
RETURNS INT
AS
BEGIN
    RETURN DATEDIFF(YEAR, @DateOfBirth, @ReferenceDate)
         - CASE
               WHEN @ReferenceDate < DATEADD(YEAR,
                        DATEDIFF(YEAR, @DateOfBirth, @ReferenceDate),
                        @DateOfBirth)
               THEN 1
               ELSE 0
           END;
END;
');

/* ---------------------------------------------------------------
   Trigger 1: TR_BookingCabin_BI_PreventDoubleBooking
   Converted from BEFORE INSERT -> INSTEAD OF INSERT
   (validation only; no column values are modified)
   --------------------------------------------------------------- */
EXEC(N'CREATE TRIGGER TR_BookingCabin_BI_PreventDoubleBooking
ON BookingCabin
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BookingID        INT;
    DECLARE @CabinID          INT;
    DECLARE @CabinPrice       DECIMAL(12,2);
    DECLARE @v_BookingShipID  INT;
    DECLARE @v_CabinShipID    INT;

    SELECT @BookingID  = BookingID,
           @CabinID    = CabinID,
           @CabinPrice = CabinPrice
    FROM inserted;

    -- Apply DEFAULT for columns the caller may have omitted (INSTEAD OF bypasses DEFAULT constraints)
    SET @CabinPrice = COALESCE(@CabinPrice, 0);

    SELECT @v_BookingShipID = v.ShipID
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = @BookingID;

    SELECT @v_CabinShipID = ShipID
    FROM Cabin
    WHERE CabinID = @CabinID;

    IF @v_BookingShipID <> @v_CabinShipID
        THROW 50000, ''Cabin must belong to the ship assigned to the booked voyage.'', 1;

    IF EXISTS (
        SELECT 1
        FROM BookingCabin bc
        INNER JOIN Booking b  ON bc.BookingID = b.BookingID
        INNER JOIN Booking nb ON nb.BookingID = @BookingID
        WHERE bc.CabinID = @CabinID
          AND b.VoyageID  = nb.VoyageID
          AND b.BookingStatus  IN (''Pending'', ''Confirmed'')
          AND nb.BookingStatus IN (''Pending'', ''Confirmed'')
    )
        THROW 50000, ''This cabin is already booked for the same voyage.'', 1;

    -- Perform the actual INSERT
    INSERT INTO BookingCabin (BookingID, CabinID, CabinPrice)
    VALUES (@BookingID, @CabinID, @CabinPrice);
END;
');

/* ---------------------------------------------------------------
   Trigger 2: TR_BookingPassenger_BI_ValidateRules
   Converted from BEFORE INSERT -> INSTEAD OF INSERT
   (validates rules AND computes DailySupervisionFee, FareRuleID,
   FinalFare before performing the actual INSERT)
   --------------------------------------------------------------- */
EXEC(N'CREATE TRIGGER TR_BookingPassenger_BI_ValidateRules
ON BookingPassenger
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Read values from inserted row
    DECLARE @BookingID           INT;
    DECLARE @BookingCabinID      INT;
    DECLARE @PassengerID         INT;
    DECLARE @AgeCategoryID       INT;
    DECLARE @FareRuleID          INT;
    DECLARE @InfantBedOption     VARCHAR(20);
    DECLARE @IsChaperonedYouth   BIT;
    DECLARE @DailySupervisionFee DECIMAL(10,2);
    DECLARE @FinalFare           DECIMAL(12,2);

    SELECT @BookingID           = BookingID,
           @BookingCabinID      = BookingCabinID,
           @PassengerID         = PassengerID,
           @AgeCategoryID       = AgeCategoryID,
           @FareRuleID          = FareRuleID,
           @InfantBedOption     = InfantBedOption,
           @IsChaperonedYouth   = IsChaperonedYouth,
           @DailySupervisionFee = DailySupervisionFee,
           @FinalFare           = FinalFare
    FROM inserted;

    -- Apply DEFAULTs for columns the caller may have omitted (INSTEAD OF bypasses DEFAULT constraints)
    SET @InfantBedOption   = COALESCE(@InfantBedOption, ''NotApplicable'');
    SET @IsChaperonedYouth = COALESCE(@IsChaperonedYouth, 0);

    -- Working variables
    DECLARE @v_CabinBookingID  INT;
    DECLARE @v_MaxOccupancy    INT;
    DECLARE @v_OccupancyCount  INT;
    DECLARE @v_PassengerAge    INT;
    DECLARE @v_CategoryMin     INT;
    DECLARE @v_CategoryMax     INT;
    DECLARE @v_CategoryName    VARCHAR(30);
    DECLARE @v_AllowsYouth     BIT;
    DECLARE @v_HasGuardian     INT = 0;
    DECLARE @v_FareRuleID      INT;
    DECLARE @v_BaseFare        DECIMAL(12,2);
    DECLARE @v_AdultFare       DECIMAL(12,2);
    DECLARE @v_ChildFare       DECIMAL(12,2);
    DECLARE @v_SupervisionFee  DECIMAL(10,2);

    -- Validate BookingCabinID belongs to the same booking
    SELECT @v_CabinBookingID = bc.BookingID,
           @v_MaxOccupancy   = c.MaxOccupancy
    FROM BookingCabin bc
    INNER JOIN Cabin c ON bc.CabinID = c.CabinID
    WHERE bc.BookingCabinID = @BookingCabinID;

    IF @v_CabinBookingID <> @BookingID
        THROW 50000, ''BookingPassenger.BookingID must match BookingCabin.BookingID.'', 1;

    -- Check cabin occupancy
    SELECT @v_OccupancyCount = COUNT(*)
    FROM BookingPassenger
    WHERE BookingCabinID = @BookingCabinID;

    IF @v_OccupancyCount + 1 > @v_MaxOccupancy OR @v_OccupancyCount + 1 > 5
        THROW 50000, ''A cabin can contain a maximum of 5 passengers only.'', 1;

    -- Passenger age and category details at voyage departure
    SELECT @v_PassengerAge = dbo.fn_CalculateAge(p.DateOfBirth, CAST(v.DepartureDateTime AS DATE)),
           @v_CategoryMin  = ac.MinAge,
           @v_CategoryMax  = ac.MaxAge,
           @v_CategoryName = ac.CategoryName,
           @v_AllowsYouth  = co.AllowsChaperonedYouth
    FROM Passenger p
    INNER JOIN Booking b         ON b.BookingID     = @BookingID
    INNER JOIN CruiseVoyage v    ON b.VoyageID      = v.VoyageID
    INNER JOIN CruiseShip s      ON v.ShipID        = s.ShipID
    INNER JOIN CruiseOperator co ON s.OperatorID    = co.OperatorID
    INNER JOIN AgeCategory ac    ON ac.AgeCategoryID = @AgeCategoryID
    WHERE p.PassengerID = @PassengerID;

    -- Validate age matches declared category
    IF @v_PassengerAge < @v_CategoryMin
       OR (@v_CategoryMax IS NOT NULL AND @v_PassengerAge > @v_CategoryMax)
        THROW 50000, ''Passenger age category must match the passenger age at voyage departure.'', 1;

    -- Validate infant bed option
    IF @v_CategoryName = ''Infant'' AND @InfantBedOption NOT IN (''SharedBed'', ''Cot'')
        THROW 50000, ''Infant passengers must have either SharedBed or Cot as InfantBedOption.'', 1;

    IF @v_CategoryName <> ''Infant'' AND @InfantBedOption <> ''NotApplicable''
        THROW 50000, ''InfantBedOption must be NotApplicable for non-infant passengers.'', 1;

    -- Validate Chaperoned Youth eligibility
    IF @IsChaperonedYouth = 1
       AND (@v_AllowsYouth = 0 OR @v_CategoryName <> ''Teen'' OR @v_PassengerAge NOT BETWEEN 15 AND 17)
        THROW 50000, ''Chaperoned Youth is only allowed for age 15 to 17 when the operator supports the program.'', 1;

    -- Minor guardian rule
    IF @v_PassengerAge <= 17 AND @IsChaperonedYouth = 0
    BEGIN
        -- Check for adult in the same cabin
        SELECT @v_HasGuardian = COUNT(*)
        FROM BookingPassenger bp
        INNER JOIN AgeCategory ac ON bp.AgeCategoryID = ac.AgeCategoryID
        WHERE bp.BookingID = @BookingID
          AND bp.BookingCabinID = @BookingCabinID
          AND ac.MinAge >= 18;

        -- If none, check for adult in an adjacent cabin on the same voyage
        IF @v_HasGuardian = 0
        BEGIN
            SELECT @v_HasGuardian = COUNT(*)
            FROM BookingPassenger   guardian_bp
            INNER JOIN AgeCategory  guardian_ac ON guardian_bp.AgeCategoryID  = guardian_ac.AgeCategoryID
            INNER JOIN BookingCabin guardian_bc ON guardian_bp.BookingCabinID = guardian_bc.BookingCabinID
            INNER JOIN Booking      guardian_b  ON guardian_bc.BookingID      = guardian_b.BookingID
            INNER JOIN BookingCabin teen_bc     ON teen_bc.BookingCabinID     = @BookingCabinID
            INNER JOIN CabinAdjacency ca        ON ca.CabinID        = teen_bc.CabinID
                                               AND ca.AdjacentCabinID = guardian_bc.CabinID
            INNER JOIN Booking      teen_b      ON teen_b.BookingID  = @BookingID
            WHERE guardian_b.VoyageID = teen_b.VoyageID
              AND guardian_b.BookingStatus IN (''Pending'', ''Confirmed'')
              AND guardian_ac.MinAge >= 18;
        END;

        IF @v_HasGuardian = 0
            THROW 50000, ''Passengers aged 17 or below require an adult in the same or adjacent cabin unless approved for Chaperoned Youth.'', 1;
    END;

    -- Set DailySupervisionFee
    IF @IsChaperonedYouth = 1
    BEGIN
        SELECT @v_SupervisionFee = COALESCE(MAX(Fee), 0)
        FROM SpecialService
        WHERE ServiceType = ''Chaperoned Youth'';

        SET @DailySupervisionFee = @v_SupervisionFee;
    END
    ELSE
        SET @DailySupervisionFee = 0;

    -- Calculate final fare
    IF @v_CategoryName = ''Infant''
    BEGIN
        -- Adult fare for SharedBed infant calculation
        SELECT TOP 1 @v_AdultFare = fr.BaseFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID       = @BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = @BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID         = bc.CabinID
        INNER JOIN AgeCategory ac  ON ac.AgeCategoryID  = fr.AgeCategoryID
        WHERE fr.VoyageID        = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName    = ''Adult''
          AND fr.EffectiveFrom  <= CAST(b.BookingDate AS DATE)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= CAST(b.BookingDate AS DATE))
        ORDER BY fr.EffectiveFrom DESC;

        IF @v_AdultFare IS NULL
            THROW 50000, ''Adult fare rule is required to calculate SharedBed infant fare.'', 1;

        -- Child fare for Cot infant calculation
        SELECT TOP 1 @v_ChildFare = fr.BaseFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID       = @BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = @BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID         = bc.CabinID
        INNER JOIN AgeCategory ac  ON ac.AgeCategoryID  = fr.AgeCategoryID
        WHERE fr.VoyageID        = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName    = ''Child''
          AND fr.EffectiveFrom  <= CAST(b.BookingDate AS DATE)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= CAST(b.BookingDate AS DATE))
        ORDER BY fr.EffectiveFrom DESC;

        IF @v_ChildFare IS NULL
            THROW 50000, ''Child fare rule is required to calculate Cot infant fare.'', 1;

        SET @FareRuleID = NULL;
        SET @FinalFare  = IIF(@InfantBedOption = ''SharedBed'', @v_AdultFare * 0.15, @v_ChildFare * 0.50);
    END
    ELSE
    BEGIN
        SELECT TOP 1 @v_FareRuleID = fr.FareRuleID,
                     @v_BaseFare   = fr.BaseFare
        FROM FareRule fr
        INNER JOIN Booking b       ON b.BookingID       = @BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = @BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID         = bc.CabinID
        WHERE fr.VoyageID        = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND fr.AgeCategoryID   = @AgeCategoryID
          AND fr.EffectiveFrom  <= CAST(b.BookingDate AS DATE)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= CAST(b.BookingDate AS DATE))
        ORDER BY fr.EffectiveFrom DESC;

        IF @v_BaseFare IS NULL
            THROW 50000, ''Fare rule is required for this voyage, cabin category, and age category.'', 1;

        SET @FareRuleID = @v_FareRuleID;
        SET @FinalFare  = @v_BaseFare;
    END;

    -- Perform the actual INSERT with computed values
    INSERT INTO BookingPassenger (
        BookingID, BookingCabinID, PassengerID, AgeCategoryID,
        FareRuleID, InfantBedOption, IsChaperonedYouth,
        DailySupervisionFee, FinalFare
    )
    VALUES (
        @BookingID, @BookingCabinID, @PassengerID, @AgeCategoryID,
        @FareRuleID, @InfantBedOption, @IsChaperonedYouth,
        @DailySupervisionFee, @FinalFare
    );
END;
');

/* ---------------------------------------------------------------
   Trigger 3: TR_BookingBaggage_BI_ValidateLimit
   Converted from BEFORE INSERT -> INSTEAD OF INSERT
   (computes IsOverLimit before performing the actual INSERT)
   --------------------------------------------------------------- */
EXEC(N'CREATE TRIGGER TR_BookingBaggage_BI_ValidateLimit
ON BookingBaggage
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BookingPassengerID INT;
    DECLARE @WeightKG           DECIMAL(6,2);
    DECLARE @ExcessFee          DECIMAL(10,2);
    DECLARE @v_AllowedWeight    DECIMAL(6,2);
    DECLARE @v_IsOverLimit      BIT;

    SELECT @BookingPassengerID = BookingPassengerID,
           @WeightKG           = WeightKG,
           @ExcessFee          = ExcessFee
    FROM inserted;

    -- Apply DEFAULT for columns the caller may have omitted (INSTEAD OF bypasses DEFAULT constraints)
    SET @ExcessFee = COALESCE(@ExcessFee, 0);

    SELECT @v_AllowedWeight = v.BaggageWeightLimitKG
    FROM BookingPassenger bp
    INNER JOIN Booking b      ON bp.BookingID = b.BookingID
    INNER JOIN CruiseVoyage v ON b.VoyageID   = v.VoyageID
    WHERE bp.BookingPassengerID = @BookingPassengerID;

    SET @v_IsOverLimit = IIF(@WeightKG > @v_AllowedWeight, 1, 0);

    -- Perform the actual INSERT with computed IsOverLimit
    INSERT INTO BookingBaggage (BookingPassengerID, WeightKG, IsOverLimit, ExcessFee)
    VALUES (@BookingPassengerID, @WeightKG, @v_IsOverLimit, @ExcessFee);
END;
');

/* ---------------------------------------------------------------
   Trigger 4: TR_BookingCancellation_BI_ApplyPenalty
   Converted from BEFORE INSERT -> INSTEAD OF INSERT
   (computes PenaltyAmount and RefundAmount before performing the
   actual INSERT; AFTER trigger 5 then updates Booking status)
   --------------------------------------------------------------- */
EXEC(N'CREATE TRIGGER TR_BookingCancellation_BI_ApplyPenalty
ON BookingCancellation
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Read values from inserted row
    DECLARE @BookingID            INT;
    DECLARE @CancellationDateTime DATETIME;
    DECLARE @Reason               VARCHAR(255);
    DECLARE @PenaltyAmount        DECIMAL(12,2);
    DECLARE @RefundAmount         DECIMAL(12,2);
    DECLARE @ProcessedBy          VARCHAR(100);

    SELECT @BookingID            = BookingID,
           @CancellationDateTime = CancellationDateTime,
           @Reason               = Reason,
           @PenaltyAmount        = PenaltyAmount,
           @RefundAmount         = RefundAmount,
           @ProcessedBy          = ProcessedBy
    FROM inserted;

    -- Apply DEFAULT for columns the caller may have omitted (INSTEAD OF bypasses DEFAULT constraints)
    -- Without this, DATEDIFF(HOUR, NULL, ...) returns NULL and all penalty calculations break.
    SET @CancellationDateTime = COALESCE(@CancellationDateTime, GETDATE());

    -- Working variables
    DECLARE @v_DepartureTime DATETIME;
    DECLARE @v_BookingTotal  DECIMAL(12,2);
    DECLARE @v_HoursUntil    INT;
    DECLARE @v_PenaltyType   VARCHAR(30) = NULL;
    DECLARE @v_PenaltyValue  DECIMAL(10,2) = 0;
    DECLARE @v_OperatorID    INT;

    SELECT @v_DepartureTime = v.DepartureDateTime,
           @v_BookingTotal  = b.TotalAmount,
           @v_OperatorID    = s.OperatorID
    FROM Booking b
    JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    JOIN CruiseShip s   ON v.ShipID   = s.ShipID
    WHERE b.BookingID = @BookingID;

    IF @v_DepartureTime IS NULL
        THROW 50000, ''Invalid Booking or Voyage'', 1;

    SET @v_HoursUntil = DATEDIFF(HOUR, @CancellationDateTime, @v_DepartureTime);

    SELECT TOP 1 @v_PenaltyType  = cp.PenaltyType,
                 @v_PenaltyValue = cp.PenaltyValue
    FROM CancellationPolicy cp
    WHERE cp.OperatorID = @v_OperatorID
      AND cp.HoursBeforeDeparture >= @v_HoursUntil
    ORDER BY cp.HoursBeforeDeparture ASC;

    IF @v_PenaltyType IS NULL
    BEGIN
        SET @v_PenaltyType  = ''Percentage'';
        SET @v_PenaltyValue = 0;
    END;

    IF @v_HoursUntil <= 48 AND @v_PenaltyType = ''FullForfeit''
    BEGIN
        SET @PenaltyAmount = @v_BookingTotal;
        SET @RefundAmount  = 0;
    END
    ELSE IF @v_PenaltyType = ''Percentage''
    BEGIN
        SET @PenaltyAmount = @v_BookingTotal * (@v_PenaltyValue / 100);
        SET @RefundAmount  = @v_BookingTotal - @PenaltyAmount;
    END
    ELSE IF @v_PenaltyType = ''FixedAmount''
    BEGIN
        SET @PenaltyAmount = CASE WHEN @v_PenaltyValue < @v_BookingTotal THEN @v_PenaltyValue ELSE @v_BookingTotal END;
        SET @RefundAmount  = @v_BookingTotal - @PenaltyAmount;
    END
    ELSE
    BEGIN
        SET @PenaltyAmount = 0;
        SET @RefundAmount  = @v_BookingTotal;
    END;

    -- Perform the actual INSERT with computed penalty values
    -- (triggers 5''s AFTER INSERT on BookingCancellation will then fire)
    INSERT INTO BookingCancellation (BookingID, CancellationDateTime, Reason, PenaltyAmount, RefundAmount, ProcessedBy)
    VALUES (@BookingID, @CancellationDateTime, @Reason, @PenaltyAmount, @RefundAmount, @ProcessedBy);
END;
');

/* ---------------------------------------------------------------
   Trigger 5: TR_BookingCancellation_AI_UpdateBookingStatus
   AFTER INSERT - fires after Trigger 4's internal INSERT
   --------------------------------------------------------------- */
EXEC(N'CREATE TRIGGER TR_BookingCancellation_AI_UpdateBookingStatus
ON BookingCancellation
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE Booking
    SET BookingStatus = ''Cancelled''
    WHERE BookingID IN (SELECT BookingID FROM inserted);
END;
');

/* ---------------------------------------------------------------
   Trigger 6: TR_BookingPassenger_AI_UpdateBookingTotal
   AFTER INSERT - fires after Trigger 2's internal INSERT
   --------------------------------------------------------------- */
EXEC(N'CREATE TRIGGER TR_BookingPassenger_AI_UpdateBookingTotal
ON BookingPassenger
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE b
    SET b.TotalAmount = (
        SELECT COALESCE(SUM(FinalFare), 0)
        FROM BookingPassenger
        WHERE BookingID = b.BookingID
    )
    FROM Booking b
    INNER JOIN inserted i ON b.BookingID = i.BookingID;
END;
');

SELECT 'All 6 triggers and fn_CalculateAge recreated successfully.' AS Message;

-- MSSQL equivalent of SHOW TRIGGERS
SELECT
    t.name                   AS TriggerName,
    OBJECT_NAME(t.parent_id) AS TableName,
    t.type_desc              AS TriggerType
FROM sys.triggers t
WHERE t.parent_class = 1
ORDER BY OBJECT_NAME(t.parent_id), t.name;

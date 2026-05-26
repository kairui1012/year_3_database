/*
    GLOBAL LUXURY CRUISE LINES (GLCL)
    MySQL Database Script

    Scope:
    - Cruise booking
    - Cancellation
    - Rescheduling

    Recommended version:
    - MySQL 8.0 or above

    This script includes:
    - Database creation
    - 3NF relational tables
    - Primary keys and foreign keys
    - Check constraints
    - Seed lookup data
    - Triggers for important business rules
*/

DROP DATABASE IF EXISTS GLCL_DB;
CREATE DATABASE GLCL_DB;
USE GLCL_DB;

/* =========================================================
   1. OPERATOR, SHIP, CABIN
   ========================================================= */

CREATE TABLE CruiseOperator (
    OperatorID INT AUTO_INCREMENT PRIMARY KEY,
    OperatorName VARCHAR(150) NOT NULL UNIQUE,
    HeadquartersCountry VARCHAR(100) NOT NULL,
    ContactEmail VARCHAR(150),
    AllowsChaperonedYouth BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE CruiseShip (
    ShipID INT AUTO_INCREMENT PRIMARY KEY,
    OperatorID INT NOT NULL,
    ShipName VARCHAR(150) NOT NULL,
    TotalDecks INT NOT NULL,
    PassengerCapacity INT NOT NULL,
    CONSTRAINT FK_CruiseShip_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID),
    CONSTRAINT CK_CruiseShip_TotalDecks
        CHECK (TotalDecks > 0),
    CONSTRAINT CK_CruiseShip_PassengerCapacity
        CHECK (PassengerCapacity > 0),
    CONSTRAINT UQ_CruiseShip_Operator_ShipName
        UNIQUE (OperatorID, ShipName)
);

CREATE TABLE CabinCategory (
    CabinCategoryID INT AUTO_INCREMENT PRIMARY KEY,
    CategoryName VARCHAR(50) NOT NULL UNIQUE,
    CategoryDescription VARCHAR(255),
    CONSTRAINT CK_CabinCategory_CategoryName
        CHECK (
            CategoryName IN (
                'Interior',
                'Ocean View',
                'Balcony',
                'Suite'
            )
        )
);

CREATE TABLE Cabin (
    CabinID INT AUTO_INCREMENT PRIMARY KEY,
    ShipID INT NOT NULL,
    CabinCategoryID INT NOT NULL,
    CabinNumber VARCHAR(20) NOT NULL,
    DeckNumber INT NOT NULL,
    MaxOccupancy INT NOT NULL,
    IsWheelchairAccessible BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT FK_Cabin_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_Cabin_CabinCategory
        FOREIGN KEY (CabinCategoryID) REFERENCES CabinCategory(CabinCategoryID),
    CONSTRAINT CK_Cabin_MaxOccupancy
        CHECK (MaxOccupancy BETWEEN 1 AND 5),
    CONSTRAINT CK_Cabin_DeckNumber
        CHECK (DeckNumber > 0),
    CONSTRAINT UQ_Cabin_Ship_CabinNumber
        UNIQUE (ShipID, CabinNumber)
);

/*
    CabinAdjacency stores which cabins are physically adjacent or
    connecting. Used to validate the teen-guardian rule: a teen may
    travel without an adult in their own cabin if an adult guardian
    occupies an adjacent/connecting cabin on the same voyage.
*/
CREATE TABLE CabinAdjacency (
    CabinAdjacencyID INT AUTO_INCREMENT PRIMARY KEY,
    CabinID          INT NOT NULL,
    AdjacentCabinID  INT NOT NULL,
    AdjacencyType    VARCHAR(20) NOT NULL DEFAULT 'Adjacent',
    CONSTRAINT FK_CabinAdjacency_Cabin
        FOREIGN KEY (CabinID) REFERENCES Cabin(CabinID),
    CONSTRAINT FK_CabinAdjacency_AdjacentCabin
        FOREIGN KEY (AdjacentCabinID) REFERENCES Cabin(CabinID),
    CONSTRAINT CK_CabinAdjacency_Type
        CHECK (AdjacencyType IN ('Adjacent', 'Connecting')),
    CONSTRAINT CK_CabinAdjacency_NotSelf
        CHECK (CabinID <> AdjacentCabinID),
    CONSTRAINT UQ_CabinAdjacency
        UNIQUE (CabinID, AdjacentCabinID)
);

/* =========================================================
   2. ROUTE AND VOYAGE
   ========================================================= */

CREATE TABLE CruiseRoute (
    RouteID INT AUTO_INCREMENT PRIMARY KEY,
    RouteName VARCHAR(150) NOT NULL,
    RouteType VARCHAR(30) NOT NULL,
    CONSTRAINT CK_CruiseRoute_RouteType
        CHECK (RouteType IN ('One-way', 'Round-trip', 'Multi-destination'))
);

CREATE TABLE Port (
    PortID INT AUTO_INCREMENT PRIMARY KEY,
    PortName VARCHAR(150) NOT NULL,
    Country VARCHAR(100) NOT NULL,
    CONSTRAINT UQ_Port_Name_Country
        UNIQUE (PortName, Country)
);

CREATE TABLE RoutePort (
    RoutePortID INT AUTO_INCREMENT PRIMARY KEY,
    RouteID INT NOT NULL,
    PortID INT NOT NULL,
    StopSequence INT NOT NULL,
    IsHomePort BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT FK_RoutePort_CruiseRoute
        FOREIGN KEY (RouteID) REFERENCES CruiseRoute(RouteID),
    CONSTRAINT FK_RoutePort_Port
        FOREIGN KEY (PortID) REFERENCES Port(PortID),
    CONSTRAINT CK_RoutePort_StopSequence
        CHECK (StopSequence > 0),
    CONSTRAINT UQ_RoutePort_Route_StopSequence
        UNIQUE (RouteID, StopSequence)
);

CREATE TABLE CruiseVoyage (
    VoyageID INT AUTO_INCREMENT PRIMARY KEY,
    ShipID INT NOT NULL,
    RouteID INT NOT NULL,
    DepartureDateTime DATETIME NOT NULL,
    ArrivalDateTime DATETIME NOT NULL,
    VoyageLengthDays INT GENERATED ALWAYS AS (DATEDIFF(ArrivalDateTime, DepartureDateTime)) STORED,
    BaggageWeightLimitKG DECIMAL(6,2) NOT NULL,
    VoyageStatus VARCHAR(30) NOT NULL DEFAULT 'Scheduled',
    CONSTRAINT FK_CruiseVoyage_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_CruiseVoyage_CruiseRoute
        FOREIGN KEY (RouteID) REFERENCES CruiseRoute(RouteID),
    CONSTRAINT CK_CruiseVoyage_ArrivalAfterDeparture
        CHECK (ArrivalDateTime > DepartureDateTime),
    CONSTRAINT CK_CruiseVoyage_BaggageLimit
        CHECK (BaggageWeightLimitKG > 0),
    CONSTRAINT CK_CruiseVoyage_Status
        CHECK (VoyageStatus IN ('Scheduled', 'Boarding', 'Departed', 'Completed', 'Cancelled'))
);

/* =========================================================
   3. PASSENGER, AGE CATEGORY, BOOKING
   ========================================================= */

CREATE TABLE Passenger (
    PassengerID INT AUTO_INCREMENT PRIMARY KEY,
    FullName VARCHAR(150) NOT NULL,
    DateOfBirth DATE NOT NULL,
    PassportNo VARCHAR(50) NOT NULL UNIQUE,
    Nationality VARCHAR(100) NOT NULL,
    Gender VARCHAR(20),
    ContactNo VARCHAR(30),
    Email VARCHAR(150)
);

CREATE TABLE AgeCategory (
    AgeCategoryID INT AUTO_INCREMENT PRIMARY KEY,
    CategoryName VARCHAR(30) NOT NULL UNIQUE,
    MinAge INT NOT NULL,
    MaxAge INT NULL,
    CONSTRAINT CK_AgeCategory_AgeRange
        CHECK (MinAge >= 0 AND (MaxAge IS NULL OR MaxAge >= MinAge))
);

CREATE TABLE Booking (
    BookingID INT AUTO_INCREMENT PRIMARY KEY,
    BookingDate DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CustomerPassengerID INT NOT NULL,
    VoyageID INT NOT NULL,
    BookingStatus VARCHAR(30) NOT NULL DEFAULT 'Confirmed',
    TotalAmount DECIMAL(12,2) NOT NULL DEFAULT 0,
    OriginalBookingID INT NULL,
    CONSTRAINT FK_Booking_CustomerPassenger
        FOREIGN KEY (CustomerPassengerID) REFERENCES Passenger(PassengerID),
    CONSTRAINT FK_Booking_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_Booking_OriginalBooking
        FOREIGN KEY (OriginalBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CK_Booking_Status
        CHECK (BookingStatus IN ('Pending', 'Confirmed', 'Waitlisted', 'Cancelled', 'Rescheduled', 'Completed')),
    CONSTRAINT CK_Booking_TotalAmount
        CHECK (TotalAmount >= 0)
);

CREATE TABLE BookingCabin (
    BookingCabinID INT AUTO_INCREMENT PRIMARY KEY,
    BookingID INT NOT NULL,
    CabinID INT NOT NULL,
    CabinPrice DECIMAL(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingCabin_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BookingCabin_Cabin
        FOREIGN KEY (CabinID) REFERENCES Cabin(CabinID),
    CONSTRAINT CK_BookingCabin_CabinPrice
        CHECK (CabinPrice >= 0),
    CONSTRAINT UQ_BookingCabin_Booking_Cabin
        UNIQUE (BookingID, CabinID)
);

CREATE TABLE FareRule (
    FareRuleID INT AUTO_INCREMENT PRIMARY KEY,
    VoyageID INT NOT NULL,
    CabinCategoryID INT NOT NULL,
    AgeCategoryID INT NOT NULL,
    BaseFare DECIMAL(12,2) NOT NULL,
    EffectiveFrom DATE NOT NULL,
    EffectiveTo DATE NULL,
    CONSTRAINT FK_FareRule_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_FareRule_CabinCategory
        FOREIGN KEY (CabinCategoryID) REFERENCES CabinCategory(CabinCategoryID),
    CONSTRAINT FK_FareRule_AgeCategory
        FOREIGN KEY (AgeCategoryID) REFERENCES AgeCategory(AgeCategoryID),
    CONSTRAINT CK_FareRule_BaseFare
        CHECK (BaseFare >= 0),
    CONSTRAINT CK_FareRule_EffectiveDate
        CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
    CONSTRAINT UQ_FareRule_Voyage_Category_Age_Date
        UNIQUE (VoyageID, CabinCategoryID, AgeCategoryID, EffectiveFrom)
);

CREATE TABLE BookingPassenger (
    BookingPassengerID INT AUTO_INCREMENT PRIMARY KEY,
    BookingID INT NOT NULL,
    BookingCabinID INT NOT NULL,
    PassengerID INT NOT NULL,
    AgeCategoryID INT NOT NULL,
    FareRuleID INT NULL,
    InfantBedOption VARCHAR(20) NOT NULL DEFAULT 'NotApplicable',
    IsChaperonedYouth BOOLEAN NOT NULL DEFAULT FALSE,
    DailySupervisionFee DECIMAL(10,2) NOT NULL DEFAULT 0,
    FinalFare DECIMAL(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingPassenger_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BookingPassenger_BookingCabin
        FOREIGN KEY (BookingCabinID) REFERENCES BookingCabin(BookingCabinID),
    CONSTRAINT FK_BookingPassenger_Passenger
        FOREIGN KEY (PassengerID) REFERENCES Passenger(PassengerID),
    CONSTRAINT FK_BookingPassenger_AgeCategory
        FOREIGN KEY (AgeCategoryID) REFERENCES AgeCategory(AgeCategoryID),
    CONSTRAINT FK_BookingPassenger_FareRule
        FOREIGN KEY (FareRuleID) REFERENCES FareRule(FareRuleID),
    CONSTRAINT CK_BookingPassenger_InfantBedOption
        CHECK (InfantBedOption IN ('SharedBed', 'Cot', 'NotApplicable')),
    CONSTRAINT CK_BookingPassenger_DailySupervisionFee
        CHECK (DailySupervisionFee >= 0),
    CONSTRAINT CK_BookingPassenger_FinalFare
        CHECK (FinalFare >= 0),
    CONSTRAINT UQ_BookingPassenger_Booking_Passenger
        UNIQUE (BookingID, PassengerID)
);

/* =========================================================
   4. DINING
   ========================================================= */

CREATE TABLE DiningOption (
    DiningOptionID INT AUTO_INCREMENT PRIMARY KEY,
    DiningName VARCHAR(100) NOT NULL UNIQUE,
    CONSTRAINT CK_DiningOption_DiningName
        CHECK (DiningName IN ('Fixed-time dining', 'Flexible dining', 'Specialty restaurant'))
);

CREATE TABLE ShipDiningOption (
    ShipDiningOptionID INT AUTO_INCREMENT PRIMARY KEY,
    ShipID INT NOT NULL,
    DiningOptionID INT NOT NULL,
    CONSTRAINT FK_ShipDiningOption_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_ShipDiningOption_DiningOption
        FOREIGN KEY (DiningOptionID) REFERENCES DiningOption(DiningOptionID),
    CONSTRAINT UQ_ShipDiningOption_Ship_DiningOption
        UNIQUE (ShipID, DiningOptionID)
);

/*
    SpecialtyDiningType captures the cuisine/dietary specialty
    offered at a specialty restaurant on a ship (e.g. Vegan, Gluten-free).
    Linked to ships via ShipSpecialtyDining.
*/
CREATE TABLE SpecialtyDiningType (
    SpecialtyDiningTypeID INT AUTO_INCREMENT PRIMARY KEY,
    TypeName              VARCHAR(100) NOT NULL UNIQUE,
    Description           VARCHAR(255)
);

CREATE TABLE ShipSpecialtyDining (
    ShipSpecialtyDiningID INT AUTO_INCREMENT PRIMARY KEY,
    ShipID                INT NOT NULL,
    SpecialtyDiningTypeID INT NOT NULL,
    CONSTRAINT FK_ShipSpecialtyDining_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_ShipSpecialtyDining_SpecialtyDiningType
        FOREIGN KEY (SpecialtyDiningTypeID) REFERENCES SpecialtyDiningType(SpecialtyDiningTypeID),
    CONSTRAINT UQ_ShipSpecialtyDining_Ship_Type
        UNIQUE (ShipID, SpecialtyDiningTypeID)
);

CREATE TABLE VoyageMealPackageType (
    MealPackageTypeID INT AUTO_INCREMENT PRIMARY KEY,
    PackageName VARCHAR(100) NOT NULL UNIQUE,
    CONSTRAINT CK_VoyageMealPackageType_PackageName
        CHECK (PackageName IN ('Standard boarding meal', 'Multi-day all-inclusive dining package'))
);

CREATE TABLE VoyageMealPackageRule (
    MealPackageRuleID INT AUTO_INCREMENT PRIMARY KEY,
    MealPackageTypeID INT NOT NULL,
    MinVoyageLengthDays INT NOT NULL,
    MaxVoyageLengthDays INT NULL,
    CONSTRAINT FK_VoyageMealPackageRule_VoyageMealPackageType
        FOREIGN KEY (MealPackageTypeID) REFERENCES VoyageMealPackageType(MealPackageTypeID),
    CONSTRAINT CK_VoyageMealPackageRule_LengthRange
        CHECK (MinVoyageLengthDays > 0 AND (MaxVoyageLengthDays IS NULL OR MaxVoyageLengthDays >= MinVoyageLengthDays)),
    CONSTRAINT UQ_VoyageMealPackageRule_LengthBand
        UNIQUE (MinVoyageLengthDays, MaxVoyageLengthDays)
);

CREATE TABLE VoyageMealPackage (
    VoyageMealPackageID INT AUTO_INCREMENT PRIMARY KEY,
    VoyageID INT NOT NULL,
    MealPackageRuleID INT NOT NULL,
    CONSTRAINT FK_VoyageMealPackage_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_VoyageMealPackage_VoyageMealPackageRule
        FOREIGN KEY (MealPackageRuleID) REFERENCES VoyageMealPackageRule(MealPackageRuleID),
    CONSTRAINT UQ_VoyageMealPackage_Voyage
        UNIQUE (VoyageID)
);

/* =========================================================
   5. SPECIAL SERVICES AND BAGGAGE
   ========================================================= */

CREATE TABLE SpecialService (
    ServiceID INT AUTO_INCREMENT PRIMARY KEY,
    ServiceName VARCHAR(100) NOT NULL UNIQUE,
    ServiceType VARCHAR(50) NOT NULL,
    AgeRestrictionMin INT NULL,
    AgeRestrictionMax INT NULL,
    Fee DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT CK_SpecialService_ServiceType
        CHECK (ServiceType IN ('Childcare', 'Teen Club', 'Accessibility', 'Mobility', 'Chaperoned Youth')),
    CONSTRAINT CK_SpecialService_AgeRestriction
        CHECK (
            (AgeRestrictionMin IS NULL AND AgeRestrictionMax IS NULL)
            OR
            (AgeRestrictionMin IS NOT NULL AND AgeRestrictionMax IS NOT NULL AND AgeRestrictionMax >= AgeRestrictionMin)
        ),
    CONSTRAINT CK_SpecialService_Fee
        CHECK (Fee >= 0)
);

CREATE TABLE PassengerSpecialService (
    PassengerServiceID INT AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID INT NOT NULL,
    ServiceID INT NOT NULL,
    RequestStatus VARCHAR(30) NOT NULL DEFAULT 'Requested',
    Fee DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT FK_PassengerSpecialService_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT FK_PassengerSpecialService_SpecialService
        FOREIGN KEY (ServiceID) REFERENCES SpecialService(ServiceID),
    CONSTRAINT CK_PassengerSpecialService_Status
        CHECK (RequestStatus IN ('Requested', 'Approved', 'Rejected', 'Completed', 'Cancelled')),
    CONSTRAINT CK_PassengerSpecialService_Fee
        CHECK (Fee >= 0),
    CONSTRAINT UQ_PassengerSpecialService_Passenger_Service
        UNIQUE (BookingPassengerID, ServiceID)
);

CREATE TABLE BaggageRule (
    BaggageRuleID INT AUTO_INCREMENT PRIMARY KEY,
    OperatorID INT NOT NULL,
    MaxWeightKG DECIMAL(6,2) NOT NULL,
    EffectiveFrom DATE NOT NULL,
    EffectiveTo DATE NULL,
    CONSTRAINT FK_BaggageRule_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID),
    CONSTRAINT CK_BaggageRule_MaxWeight
        CHECK (MaxWeightKG > 0),
    CONSTRAINT CK_BaggageRule_EffectiveDate
        CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
);

CREATE TABLE BookingBaggage (
    BaggageID INT AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID INT NOT NULL,
    WeightKG DECIMAL(6,2) NOT NULL,
    IsOverLimit BOOLEAN NOT NULL DEFAULT FALSE,
    ExcessFee DECIMAL(10,2) NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingBaggage_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT CK_BookingBaggage_Weight
        CHECK (WeightKG >= 0),
    CONSTRAINT CK_BookingBaggage_ExcessFee
        CHECK (ExcessFee >= 0)
);

/* =========================================================
   6. ONSHORE EXCURSIONS
   ========================================================= */

/*
    Excursion defines an activity available at a specific port.
    VoyageExcursion links excursions to a particular stop on a voyage
    (via RoutePort) and controls available slot capacity.
    BookingExcursion records which passengers have purchased an excursion,
    enabling queries for excursion sales and unsold excursions.
*/
CREATE TABLE Excursion (
    ExcursionID   INT AUTO_INCREMENT PRIMARY KEY,
    PortID        INT NOT NULL,
    ExcursionName VARCHAR(150) NOT NULL,
    Description   VARCHAR(500),
    DurationHours DECIMAL(5,2) NOT NULL,
    Price         DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT FK_Excursion_Port
        FOREIGN KEY (PortID) REFERENCES Port(PortID),
    CONSTRAINT CK_Excursion_Price
        CHECK (Price >= 0),
    CONSTRAINT CK_Excursion_Duration
        CHECK (DurationHours > 0),
    CONSTRAINT UQ_Excursion_Port_Name
        UNIQUE (PortID, ExcursionName)
);

CREATE TABLE VoyageExcursion (
    VoyageExcursionID INT AUTO_INCREMENT PRIMARY KEY,
    VoyageID          INT NOT NULL,
    RoutePortID       INT NOT NULL,
    ExcursionID       INT NOT NULL,
    AvailableSlots    INT NOT NULL DEFAULT 0,
    CONSTRAINT FK_VoyageExcursion_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_VoyageExcursion_RoutePort
        FOREIGN KEY (RoutePortID) REFERENCES RoutePort(RoutePortID),
    CONSTRAINT FK_VoyageExcursion_Excursion
        FOREIGN KEY (ExcursionID) REFERENCES Excursion(ExcursionID),
    CONSTRAINT CK_VoyageExcursion_Slots
        CHECK (AvailableSlots >= 0),
    CONSTRAINT UQ_VoyageExcursion_Voyage_Port_Excursion
        UNIQUE (VoyageID, RoutePortID, ExcursionID)
);

CREATE TABLE BookingExcursion (
    BookingExcursionID INT AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID INT NOT NULL,
    VoyageExcursionID  INT NOT NULL,
    BookingDateTime    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ExcursionStatus    VARCHAR(30) NOT NULL DEFAULT 'Booked',
    AmountPaid         DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT FK_BookingExcursion_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT FK_BookingExcursion_VoyageExcursion
        FOREIGN KEY (VoyageExcursionID) REFERENCES VoyageExcursion(VoyageExcursionID),
    CONSTRAINT CK_BookingExcursion_Status
        CHECK (ExcursionStatus IN ('Booked', 'Cancelled', 'Completed')),
    CONSTRAINT CK_BookingExcursion_Amount
        CHECK (AmountPaid >= 0),
    CONSTRAINT UQ_BookingExcursion_Passenger_Excursion
        UNIQUE (BookingPassengerID, VoyageExcursionID)
);

/* =========================================================
   7. CANCELLATION, RESCHEDULING, PAYMENT
   ========================================================= */

CREATE TABLE CancellationPolicy (
    PolicyID INT AUTO_INCREMENT PRIMARY KEY,
    OperatorID INT NOT NULL,
    HoursBeforeDeparture INT NOT NULL,
    PenaltyType VARCHAR(30) NOT NULL,
    PenaltyValue DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_CancellationPolicy_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID),
    CONSTRAINT CK_CancellationPolicy_Hours
        CHECK (HoursBeforeDeparture >= 0),
    CONSTRAINT CK_CancellationPolicy_PenaltyType
        CHECK (PenaltyType IN ('Percentage', 'FixedAmount', 'FullForfeit')),
    CONSTRAINT CK_CancellationPolicy_PenaltyValue
        CHECK (PenaltyValue >= 0)
);

CREATE TABLE BookingCancellation (
    CancellationID INT AUTO_INCREMENT PRIMARY KEY,
    BookingID INT NOT NULL UNIQUE,
    CancellationDateTime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Reason VARCHAR(255),
    PenaltyAmount DECIMAL(12,2) NOT NULL DEFAULT 0,
    RefundAmount DECIMAL(12,2) NOT NULL DEFAULT 0,
    ProcessedBy VARCHAR(100),
    CONSTRAINT FK_BookingCancellation_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CK_BookingCancellation_Amounts
        CHECK (PenaltyAmount >= 0 AND RefundAmount >= 0)
);

CREATE TABLE RescheduleRequest (
    RescheduleID INT AUTO_INCREMENT PRIMARY KEY,
    OriginalBookingID INT NOT NULL,
    NewBookingID INT NULL,
    RequestDateTime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    NewVoyageID INT NOT NULL,
    RescheduleFee DECIMAL(12,2) NOT NULL DEFAULT 0,
    RequestStatus VARCHAR(30) NOT NULL DEFAULT 'Requested',
    Reason VARCHAR(255),
    CONSTRAINT FK_RescheduleRequest_OriginalBooking
        FOREIGN KEY (OriginalBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_RescheduleRequest_NewBooking
        FOREIGN KEY (NewBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_RescheduleRequest_NewVoyage
        FOREIGN KEY (NewVoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT CK_RescheduleRequest_Fee
        CHECK (RescheduleFee >= 0),
    CONSTRAINT CK_RescheduleRequest_Status
        CHECK (RequestStatus IN ('Requested', 'Approved', 'Rejected', 'Completed', 'Cancelled'))
);

CREATE TABLE Payment (
    PaymentID INT AUTO_INCREMENT PRIMARY KEY,
    BookingID INT NOT NULL,
    PaymentDateTime DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Amount DECIMAL(12,2) NOT NULL,
    PaymentMethod VARCHAR(50) NOT NULL,
    PaymentStatus VARCHAR(30) NOT NULL DEFAULT 'Pending',
    TransactionReference VARCHAR(100) UNIQUE,
    CONSTRAINT FK_Payment_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CK_Payment_Amount
        CHECK (Amount > 0),
    CONSTRAINT CK_Payment_Status
        CHECK (PaymentStatus IN ('Pending', 'Paid', 'Failed', 'Refunded', 'Partially Refunded'))
);

/* =========================================================
   8. FUNCTION AND TRIGGERS FOR KEY BUSINESS RULES
   ========================================================= */

DELIMITER $$

CREATE FUNCTION fn_CalculateAge(DateOfBirth DATE, ReferenceDate DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE AgeValue INT;

    SET AgeValue = TIMESTAMPDIFF(YEAR, DateOfBirth, ReferenceDate);
    RETURN AgeValue;
END$$

CREATE TRIGGER TR_Passenger_BI_ValidateDateOfBirth
BEFORE INSERT ON Passenger
FOR EACH ROW
BEGIN
    IF NEW.DateOfBirth > CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger date of birth cannot be in the future.';
    END IF;
END$$

CREATE TRIGGER TR_Passenger_BU_ValidateDateOfBirth
BEFORE UPDATE ON Passenger
FOR EACH ROW
BEGIN
    IF NEW.DateOfBirth > CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger date of birth cannot be in the future.';
    END IF;
END$$

CREATE TRIGGER TR_BookingCabin_BI_PreventDoubleBooking
BEFORE INSERT ON BookingCabin
FOR EACH ROW
BEGIN
    DECLARE BookingShipID INT;
    DECLARE CabinShipID INT;

    SELECT v.ShipID
    INTO BookingShipID
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = NEW.BookingID;

    SELECT ShipID
    INTO CabinShipID
    FROM Cabin
    WHERE CabinID = NEW.CabinID;

    IF BookingShipID <> CabinShipID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cabin must belong to the ship assigned to the booked voyage.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM BookingCabin bc
        INNER JOIN Booking b ON bc.BookingID = b.BookingID
        INNER JOIN Booking nb ON NEW.BookingID = nb.BookingID
        WHERE bc.CabinID = NEW.CabinID
          AND b.VoyageID = nb.VoyageID
          AND b.BookingStatus IN ('Pending', 'Confirmed')
          AND nb.BookingStatus IN ('Pending', 'Confirmed')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This cabin is already booked for the same voyage.';
    END IF;
END$$

CREATE TRIGGER TR_BookingCabin_BU_PreventDoubleBooking
BEFORE UPDATE ON BookingCabin
FOR EACH ROW
BEGIN
    DECLARE BookingShipID INT;
    DECLARE CabinShipID INT;

    SELECT v.ShipID
    INTO BookingShipID
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = NEW.BookingID;

    SELECT ShipID
    INTO CabinShipID
    FROM Cabin
    WHERE CabinID = NEW.CabinID;

    IF BookingShipID <> CabinShipID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cabin must belong to the ship assigned to the booked voyage.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM BookingCabin bc
        INNER JOIN Booking b ON bc.BookingID = b.BookingID
        INNER JOIN Booking nb ON NEW.BookingID = nb.BookingID
        WHERE bc.CabinID = NEW.CabinID
          AND bc.BookingCabinID <> OLD.BookingCabinID
          AND b.VoyageID = nb.VoyageID
          AND b.BookingStatus IN ('Pending', 'Confirmed')
          AND nb.BookingStatus IN ('Pending', 'Confirmed')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This cabin is already booked for the same voyage.';
    END IF;
END$$

CREATE TRIGGER TR_BookingPassenger_BI_ValidateRules
BEFORE INSERT ON BookingPassenger
FOR EACH ROW
BEGIN
    DECLARE CabinBookingID INT;
    DECLARE CabinMaxOccupancy INT;
    DECLARE ExistingPassengerCount INT;
    DECLARE PassengerAge INT;
    DECLARE CategoryMinAge INT;
    DECLARE CategoryMaxAge INT;
    DECLARE CategoryNameValue VARCHAR(30);
    DECLARE OperatorAllowsYouth BOOLEAN;
    DECLARE CabinIDValue INT;
    DECLARE FareRuleIDValue INT;
    DECLARE BaseFareValue DECIMAL(12,2);
    DECLARE AdultFareValue DECIMAL(12,2);
    DECLARE ChildFareValue DECIMAL(12,2);
    DECLARE HasAdultGuardian INT DEFAULT 0;
    DECLARE SupervisionFeeValue DECIMAL(10,2);

    SELECT bc.BookingID, c.MaxOccupancy, c.CabinID
    INTO CabinBookingID, CabinMaxOccupancy, CabinIDValue
    FROM BookingCabin bc
    INNER JOIN Cabin c ON bc.CabinID = c.CabinID
    WHERE bc.BookingCabinID = NEW.BookingCabinID;

    IF CabinBookingID <> NEW.BookingID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BookingPassenger.BookingID must match BookingCabin.BookingID.';
    END IF;

    SELECT COUNT(*)
    INTO ExistingPassengerCount
    FROM BookingPassenger
    WHERE BookingCabinID = NEW.BookingCabinID;

    IF ExistingPassengerCount + 1 > CabinMaxOccupancy OR ExistingPassengerCount + 1 > 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A cabin can contain a maximum of 5 passengers only.';
    END IF;

    SELECT
        fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime)),
        ac.MinAge,
        ac.MaxAge,
        ac.CategoryName,
        co.AllowsChaperonedYouth
    INTO
        PassengerAge,
        CategoryMinAge,
        CategoryMaxAge,
        CategoryNameValue,
        OperatorAllowsYouth
    FROM Passenger p
    INNER JOIN Booking b ON b.BookingID = NEW.BookingID
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s ON v.ShipID = s.ShipID
    INNER JOIN CruiseOperator co ON s.OperatorID = co.OperatorID
    INNER JOIN AgeCategory ac ON ac.AgeCategoryID = NEW.AgeCategoryID
    WHERE p.PassengerID = NEW.PassengerID;

    IF PassengerAge < CategoryMinAge OR (CategoryMaxAge IS NOT NULL AND PassengerAge > CategoryMaxAge) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger age category must match the passenger age at voyage departure.';
    END IF;

    IF CategoryNameValue = 'Infant' AND NEW.InfantBedOption NOT IN ('SharedBed', 'Cot') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Infant passengers must have either SharedBed or Cot as InfantBedOption.';
    END IF;

    IF CategoryNameValue <> 'Infant' AND NEW.InfantBedOption <> 'NotApplicable' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InfantBedOption must be NotApplicable for non-infant passengers.';
    END IF;

    IF NEW.IsChaperonedYouth = TRUE
       AND (OperatorAllowsYouth = FALSE OR CategoryNameValue <> 'Teen' OR PassengerAge NOT BETWEEN 15 AND 17) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Chaperoned Youth is only allowed for age 15 to 17 when the operator supports the program.';
    END IF;

    IF PassengerAge <= 17 AND NEW.IsChaperonedYouth = FALSE THEN
        /* Step 1: check for an adult already in the same cabin. */
        SELECT COUNT(*)
        INTO HasAdultGuardian
        FROM BookingPassenger bp
        INNER JOIN AgeCategory adult_ac ON bp.AgeCategoryID = adult_ac.AgeCategoryID
        WHERE bp.BookingID = NEW.BookingID
          AND adult_ac.MinAge >= 18
          AND bp.BookingCabinID = NEW.BookingCabinID;

        /*
            Step 2: if none found, check whether an adult guardian is
            booked on the SAME voyage in an adjacent or connecting cabin.
            Business rule: "an adult guardian (18 or older) is booked in
            an adjacent or connecting cabin."
        */
        IF HasAdultGuardian = 0 THEN
            SELECT COUNT(*)
            INTO HasAdultGuardian
            FROM BookingPassenger     guardian_bp
            INNER JOIN AgeCategory    guardian_ac  ON guardian_bp.AgeCategoryID = guardian_ac.AgeCategoryID
            INNER JOIN BookingCabin   guardian_bc  ON guardian_bp.BookingCabinID = guardian_bc.BookingCabinID
            INNER JOIN Booking        guardian_b   ON guardian_bc.BookingID = guardian_b.BookingID
            INNER JOIN BookingCabin   teen_bc      ON teen_bc.BookingCabinID = NEW.BookingCabinID
            INNER JOIN CabinAdjacency ca           ON ca.CabinID = teen_bc.CabinID
                                                  AND ca.AdjacentCabinID = guardian_bc.CabinID
            INNER JOIN Booking        teen_b       ON teen_b.BookingID = NEW.BookingID
            WHERE guardian_b.VoyageID = teen_b.VoyageID
              AND guardian_b.BookingStatus IN ('Pending', 'Confirmed')
              AND guardian_ac.MinAge >= 18;
        END IF;

        IF HasAdultGuardian = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Passengers aged 17 or below require an adult in the same or adjacent cabin unless approved for Chaperoned Youth.';
        END IF;
    END IF;

    IF NEW.IsChaperonedYouth = TRUE THEN
        SELECT COALESCE(MAX(Fee), 0)
        INTO SupervisionFeeValue
        FROM SpecialService
        WHERE ServiceType = 'Chaperoned Youth';

        SET NEW.DailySupervisionFee = SupervisionFeeValue;
    ELSE
        SET NEW.DailySupervisionFee = 0;
    END IF;

    IF CategoryNameValue = 'Infant' THEN
        SELECT fr.BaseFare
        INTO AdultFareValue
        FROM FareRule fr
        INNER JOIN Booking b ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c ON c.CabinID = bc.CabinID
        INNER JOIN AgeCategory ac ON ac.AgeCategoryID = fr.AgeCategoryID
        WHERE fr.VoyageID = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName = 'Adult'
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC
        LIMIT 1;

        IF AdultFareValue IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Adult fare rule is required to calculate SharedBed infant fare.';
        END IF;

        SELECT fr.BaseFare
        INTO ChildFareValue
        FROM FareRule fr
        INNER JOIN Booking b ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c ON c.CabinID = bc.CabinID
        INNER JOIN AgeCategory ac ON ac.AgeCategoryID = fr.AgeCategoryID
        WHERE fr.VoyageID = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName = 'Child'
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC
        LIMIT 1;

        IF ChildFareValue IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Child fare rule is required to calculate Cot infant fare.';
        END IF;

        SET NEW.FareRuleID = NULL;
        SET NEW.FinalFare = CASE
            WHEN NEW.InfantBedOption = 'SharedBed' THEN AdultFareValue * 0.15
            ELSE ChildFareValue * 0.50
        END;
    ELSE
        SELECT fr.FareRuleID, fr.BaseFare
        INTO FareRuleIDValue, BaseFareValue
        FROM FareRule fr
        INNER JOIN Booking b ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c ON c.CabinID = bc.CabinID
        WHERE fr.VoyageID = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND fr.AgeCategoryID = NEW.AgeCategoryID
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC
        LIMIT 1;

        IF BaseFareValue IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Fare rule is required for this voyage, cabin category, and age category.';
        END IF;

        SET NEW.FareRuleID = FareRuleIDValue;
        SET NEW.FinalFare = BaseFareValue;
    END IF;
END$$

CREATE TRIGGER TR_BookingPassenger_BU_ValidateRules
BEFORE UPDATE ON BookingPassenger
FOR EACH ROW
BEGIN
    DECLARE CabinBookingID INT;
    DECLARE CabinMaxOccupancy INT;
    DECLARE ExistingPassengerCount INT;
    DECLARE PassengerAge INT;
    DECLARE CategoryMinAge INT;
    DECLARE CategoryMaxAge INT;
    DECLARE CategoryNameValue VARCHAR(30);
    DECLARE OperatorAllowsYouth BOOLEAN;
    DECLARE CabinIDValue INT;
    DECLARE FareRuleIDValue INT;
    DECLARE BaseFareValue DECIMAL(12,2);
    DECLARE AdultFareValue DECIMAL(12,2);
    DECLARE ChildFareValue DECIMAL(12,2);
    DECLARE HasAdultGuardian INT DEFAULT 0;
    DECLARE SupervisionFeeValue DECIMAL(10,2);

    SELECT bc.BookingID, c.MaxOccupancy, c.CabinID
    INTO CabinBookingID, CabinMaxOccupancy, CabinIDValue
    FROM BookingCabin bc
    INNER JOIN Cabin c ON bc.CabinID = c.CabinID
    WHERE bc.BookingCabinID = NEW.BookingCabinID;

    IF CabinBookingID <> NEW.BookingID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BookingPassenger.BookingID must match BookingCabin.BookingID.';
    END IF;

    SELECT COUNT(*)
    INTO ExistingPassengerCount
    FROM BookingPassenger
    WHERE BookingCabinID = NEW.BookingCabinID
      AND BookingPassengerID <> OLD.BookingPassengerID;

    IF ExistingPassengerCount + 1 > CabinMaxOccupancy OR ExistingPassengerCount + 1 > 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A cabin can contain a maximum of 5 passengers only.';
    END IF;

    SELECT
        fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime)),
        ac.MinAge,
        ac.MaxAge,
        ac.CategoryName,
        co.AllowsChaperonedYouth
    INTO
        PassengerAge,
        CategoryMinAge,
        CategoryMaxAge,
        CategoryNameValue,
        OperatorAllowsYouth
    FROM Passenger p
    INNER JOIN Booking b ON b.BookingID = NEW.BookingID
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s ON v.ShipID = s.ShipID
    INNER JOIN CruiseOperator co ON s.OperatorID = co.OperatorID
    INNER JOIN AgeCategory ac ON ac.AgeCategoryID = NEW.AgeCategoryID
    WHERE p.PassengerID = NEW.PassengerID;

    IF PassengerAge < CategoryMinAge OR (CategoryMaxAge IS NOT NULL AND PassengerAge > CategoryMaxAge) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger age category must match the passenger age at voyage departure.';
    END IF;

    IF CategoryNameValue = 'Infant' AND NEW.InfantBedOption NOT IN ('SharedBed', 'Cot') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Infant passengers must have either SharedBed or Cot as InfantBedOption.';
    END IF;

    IF CategoryNameValue <> 'Infant' AND NEW.InfantBedOption <> 'NotApplicable' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InfantBedOption must be NotApplicable for non-infant passengers.';
    END IF;

    IF NEW.IsChaperonedYouth = TRUE
       AND (OperatorAllowsYouth = FALSE OR CategoryNameValue <> 'Teen' OR PassengerAge NOT BETWEEN 15 AND 17) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Chaperoned Youth is only allowed for age 15 to 17 when the operator supports the program.';
    END IF;

    IF PassengerAge <= 17 AND NEW.IsChaperonedYouth = FALSE THEN
                SELECT COUNT(*)
                INTO HasAdultGuardian
                FROM BookingPassenger bp
                INNER JOIN AgeCategory adult_ac ON bp.AgeCategoryID = adult_ac.AgeCategoryID
                WHERE bp.BookingID = NEW.BookingID
                    AND bp.BookingPassengerID <> OLD.BookingPassengerID
                    AND adult_ac.MinAge >= 18
                    AND bp.BookingCabinID = NEW.BookingCabinID;

                IF HasAdultGuardian = 0 THEN
                        SIGNAL SQLSTATE '45000'
                                SET MESSAGE_TEXT = 'Passengers aged 17 or below require an adult in the same cabin unless approved for Chaperoned Youth.';
                END IF;
    END IF;

    IF NEW.IsChaperonedYouth = TRUE THEN
        SELECT COALESCE(MAX(Fee), 0)
        INTO SupervisionFeeValue
        FROM SpecialService
        WHERE ServiceType = 'Chaperoned Youth';

        SET NEW.DailySupervisionFee = SupervisionFeeValue;
    ELSE
        SET NEW.DailySupervisionFee = 0;
    END IF;

    IF CategoryNameValue = 'Infant' THEN
        SELECT fr.BaseFare
        INTO AdultFareValue
        FROM FareRule fr
        INNER JOIN Booking b ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c ON c.CabinID = bc.CabinID
        INNER JOIN AgeCategory ac ON ac.AgeCategoryID = fr.AgeCategoryID
        WHERE fr.VoyageID = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName = 'Adult'
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC
        LIMIT 1;

        IF AdultFareValue IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Adult fare rule is required to calculate SharedBed infant fare.';
        END IF;

        SELECT fr.BaseFare
        INTO ChildFareValue
        FROM FareRule fr
        INNER JOIN Booking b ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c ON c.CabinID = bc.CabinID
        INNER JOIN AgeCategory ac ON ac.AgeCategoryID = fr.AgeCategoryID
        WHERE fr.VoyageID = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND ac.CategoryName = 'Child'
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC
        LIMIT 1;

        IF ChildFareValue IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Child fare rule is required to calculate Cot infant fare.';
        END IF;

        SET NEW.FareRuleID = NULL;
        SET NEW.FinalFare = CASE
            WHEN NEW.InfantBedOption = 'SharedBed' THEN AdultFareValue * 0.15
            ELSE ChildFareValue * 0.50
        END;
    ELSE
        SELECT fr.FareRuleID, fr.BaseFare
        INTO FareRuleIDValue, BaseFareValue
        FROM FareRule fr
        INNER JOIN Booking b ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c ON c.CabinID = bc.CabinID
        WHERE fr.VoyageID = b.VoyageID
          AND fr.CabinCategoryID = c.CabinCategoryID
          AND fr.AgeCategoryID = NEW.AgeCategoryID
          AND fr.EffectiveFrom <= DATE(b.BookingDate)
          AND (fr.EffectiveTo IS NULL OR fr.EffectiveTo >= DATE(b.BookingDate))
        ORDER BY fr.EffectiveFrom DESC
        LIMIT 1;

        IF BaseFareValue IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Fare rule is required for this voyage, cabin category, and age category.';
        END IF;

        SET NEW.FareRuleID = FareRuleIDValue;
        SET NEW.FinalFare = BaseFareValue;
    END IF;
END$$

CREATE TRIGGER TR_BookingBaggage_BI_ValidateLimit
BEFORE INSERT ON BookingBaggage
FOR EACH ROW
BEGIN
    DECLARE AllowedWeight DECIMAL(6,2);

    SELECT v.BaggageWeightLimitKG
    INTO AllowedWeight
    FROM BookingPassenger bp
    INNER JOIN Booking b ON bp.BookingID = b.BookingID
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE bp.BookingPassengerID = NEW.BookingPassengerID;

    SET NEW.IsOverLimit = NEW.WeightKG > AllowedWeight;
END$$

CREATE TRIGGER TR_BookingBaggage_BU_ValidateLimit
BEFORE UPDATE ON BookingBaggage
FOR EACH ROW
BEGIN
    DECLARE AllowedWeight DECIMAL(6,2);

    SELECT v.BaggageWeightLimitKG
    INTO AllowedWeight
    FROM BookingPassenger bp
    INNER JOIN Booking b ON bp.BookingID = b.BookingID
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE bp.BookingPassengerID = NEW.BookingPassengerID;

    SET NEW.IsOverLimit = NEW.WeightKG > AllowedWeight;
END$$

CREATE TRIGGER TR_BookingCancellation_BI_ApplyPenalty
BEFORE INSERT ON BookingCancellation
FOR EACH ROW
BEGIN
    DECLARE DepartureTime DATETIME;
    DECLARE BookingTotal DECIMAL(12,2);
    DECLARE HoursUntilDeparture INT;
    DECLARE PolicyPenaltyType VARCHAR(30);
    DECLARE PolicyPenaltyValue DECIMAL(10,2);

    SELECT v.DepartureDateTime, b.TotalAmount, cp.PenaltyType, cp.PenaltyValue
    INTO DepartureTime, BookingTotal, PolicyPenaltyType, PolicyPenaltyValue
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s ON v.ShipID = s.ShipID
    LEFT JOIN CancellationPolicy cp
        ON s.OperatorID = cp.OperatorID
       AND cp.HoursBeforeDeparture >= TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, v.DepartureDateTime)
    WHERE b.BookingID = NEW.BookingID
    ORDER BY cp.HoursBeforeDeparture ASC
    LIMIT 1;

    SET HoursUntilDeparture = TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, DepartureTime);

    IF HoursUntilDeparture <= 48 AND PolicyPenaltyType = 'FullForfeit' THEN
        SET NEW.PenaltyAmount = BookingTotal;
        SET NEW.RefundAmount = 0;
    ELSEIF PolicyPenaltyType = 'Percentage' THEN
        SET NEW.PenaltyAmount = BookingTotal * (PolicyPenaltyValue / 100);
        SET NEW.RefundAmount = BookingTotal - NEW.PenaltyAmount;
    ELSEIF PolicyPenaltyType = 'FixedAmount' THEN
        SET NEW.PenaltyAmount = LEAST(PolicyPenaltyValue, BookingTotal);
        SET NEW.RefundAmount = BookingTotal - NEW.PenaltyAmount;
    ELSEIF PolicyPenaltyType IS NULL THEN
        SET NEW.PenaltyAmount = 0;
        SET NEW.RefundAmount = BookingTotal;
    END IF;
END$$

CREATE TRIGGER TR_BookingCancellation_AI_UpdateBookingStatus
AFTER INSERT ON BookingCancellation
FOR EACH ROW
BEGIN
    UPDATE Booking
    SET BookingStatus = 'Cancelled'
    WHERE BookingID = NEW.BookingID;
END$$

CREATE TRIGGER TR_BookingCancellation_BU_ApplyPenalty
BEFORE UPDATE ON BookingCancellation
FOR EACH ROW
BEGIN
    DECLARE DepartureTime DATETIME;
    DECLARE BookingTotal DECIMAL(12,2);
    DECLARE HoursUntilDeparture INT;
    DECLARE PolicyPenaltyType VARCHAR(30);
    DECLARE PolicyPenaltyValue DECIMAL(10,2);

    SELECT v.DepartureDateTime, b.TotalAmount, cp.PenaltyType, cp.PenaltyValue
    INTO DepartureTime, BookingTotal, PolicyPenaltyType, PolicyPenaltyValue
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s ON v.ShipID = s.ShipID
    LEFT JOIN CancellationPolicy cp
        ON s.OperatorID = cp.OperatorID
       AND cp.HoursBeforeDeparture >= TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, v.DepartureDateTime)
    WHERE b.BookingID = NEW.BookingID
    ORDER BY cp.HoursBeforeDeparture ASC
    LIMIT 1;

    SET HoursUntilDeparture = TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, DepartureTime);

    IF HoursUntilDeparture <= 48 AND PolicyPenaltyType = 'FullForfeit' THEN
        SET NEW.PenaltyAmount = BookingTotal;
        SET NEW.RefundAmount = 0;
    ELSEIF PolicyPenaltyType = 'Percentage' THEN
        SET NEW.PenaltyAmount = BookingTotal * (PolicyPenaltyValue / 100);
        SET NEW.RefundAmount = BookingTotal - NEW.PenaltyAmount;
    ELSEIF PolicyPenaltyType = 'FixedAmount' THEN
        SET NEW.PenaltyAmount = LEAST(PolicyPenaltyValue, BookingTotal);
        SET NEW.RefundAmount = BookingTotal - NEW.PenaltyAmount;
    ELSEIF PolicyPenaltyType IS NULL THEN
        SET NEW.PenaltyAmount = 0;
        SET NEW.RefundAmount = BookingTotal;
    END IF;
END$$

CREATE TRIGGER TR_RescheduleRequest_BI_ValidateRules
BEFORE INSERT ON RescheduleRequest
FOR EACH ROW
BEGIN
    DECLARE OriginalBookingDate DATETIME;
    DECLARE OriginalDepartureTime DATETIME;
    DECLARE NewDepartureTime DATETIME;
    DECLARE OriginalTotal DECIMAL(12,2);

    SELECT b.BookingDate, v.DepartureDateTime, b.TotalAmount
    INTO OriginalBookingDate, OriginalDepartureTime, OriginalTotal
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = NEW.OriginalBookingID;

    SELECT DepartureDateTime
    INTO NewDepartureTime
    FROM CruiseVoyage
    WHERE VoyageID = NEW.NewVoyageID;

    IF NEW.RequestDateTime >= OriginalDepartureTime THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A departed cruise ticket cannot be rescheduled.';
    END IF;

    IF NewDepartureTime > DATE_ADD(OriginalBookingDate, INTERVAL 1 YEAR) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'The new voyage must start within one year from the original booking date.';
    END IF;

    IF TIMESTAMPDIFF(HOUR, NEW.RequestDateTime, OriginalDepartureTime) <= 48 THEN
        SET NEW.RescheduleFee = OriginalTotal;
    END IF;
END$$

CREATE TRIGGER TR_RescheduleRequest_BU_ValidateRules
BEFORE UPDATE ON RescheduleRequest
FOR EACH ROW
BEGIN
    DECLARE OriginalBookingDate DATETIME;
    DECLARE OriginalDepartureTime DATETIME;
    DECLARE NewDepartureTime DATETIME;
    DECLARE OriginalTotal DECIMAL(12,2);

    SELECT b.BookingDate, v.DepartureDateTime, b.TotalAmount
    INTO OriginalBookingDate, OriginalDepartureTime, OriginalTotal
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = NEW.OriginalBookingID;

    SELECT DepartureDateTime
    INTO NewDepartureTime
    FROM CruiseVoyage
    WHERE VoyageID = NEW.NewVoyageID;

    IF NEW.RequestDateTime >= OriginalDepartureTime THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A departed cruise ticket cannot be rescheduled.';
    END IF;

    IF NewDepartureTime > DATE_ADD(OriginalBookingDate, INTERVAL 1 YEAR) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'The new voyage must start within one year from the original booking date.';
    END IF;

    IF TIMESTAMPDIFF(HOUR, NEW.RequestDateTime, OriginalDepartureTime) <= 48 THEN
        SET NEW.RescheduleFee = OriginalTotal;
    END IF;
END$$

DELIMITER ;

/* =========================================================
   9. SEED DATA
   ========================================================= */

INSERT INTO CabinCategory (CategoryName, CategoryDescription)
VALUES
('Interior', 'Inside cabin without sea view.'),
('Ocean View', 'Cabin with sea-facing window.'),
('Balcony', 'Cabin with private balcony.'),
('Suite', 'Premium suite with luxury facilities.');

INSERT INTO AgeCategory (CategoryName, MinAge, MaxAge)
VALUES
('Infant', 0, 1),
('Child', 2, 12),
('Teen', 13, 17),
('Adult', 18, 59),
('Senior', 60, NULL);

INSERT INTO DiningOption (DiningName)
VALUES
('Fixed-time dining'),
('Flexible dining'),
('Specialty restaurant');

INSERT INTO VoyageMealPackageType (PackageName)
VALUES
('Standard boarding meal'),
('Multi-day all-inclusive dining package');

/*
    Meal package rule: voyages of 1 day get a standard boarding meal;
    voyages of 2+ days get a multi-day all-inclusive package.
*/
INSERT INTO VoyageMealPackageRule (MealPackageTypeID, MinVoyageLengthDays, MaxVoyageLengthDays)
VALUES
(1, 1, 1),     -- Standard boarding meal  : exactly 1 day
(2, 2, NULL);  -- All-inclusive package   : 2 days and above

INSERT INTO SpecialService (ServiceName, ServiceType, AgeRestrictionMin, AgeRestrictionMax, Fee)
VALUES
('Onboard Childcare Service', 'Childcare', 2, 12, 35.00),
('Teen Exclusive Club', 'Teen Club', 13, 17, 0.00),
('Wheelchair Accessible Cabin Request', 'Accessibility', NULL, NULL, 0.00),
('Mobility Assistance Service', 'Mobility', NULL, NULL, 0.00),
('Chaperoned Youth Supervision', 'Chaperoned Youth', 15, 17, 50.00);

INSERT INTO CruiseOperator (OperatorName, HeadquartersCountry, ContactEmail, AllowsChaperonedYouth)
VALUES
('Global Luxury Cruise Lines', 'Malaysia', 'reservations@glcl.example', TRUE),
('Royal Oceanic Voyages', 'United Kingdom', 'support@royaloceanic.example', FALSE);

INSERT INTO CruiseShip (OperatorID, ShipName, TotalDecks, PassengerCapacity)
VALUES
(1, 'GLCL Majesty', 15, 3200),
(1, 'GLCL Pearl', 12, 2200),
(2, 'Oceanic Star', 14, 2800);

INSERT INTO CruiseRoute (RouteName, RouteType)
VALUES
('Kuala Lumpur to Singapore Repositioning', 'One-way'),
('Penang Island Luxury Loop', 'Round-trip'),
('Langkawi, Phuket and Krabi Island Hopper', 'Multi-destination');

INSERT INTO Port (PortName, Country)
VALUES
('Port Klang', 'Malaysia'),
('Singapore Cruise Centre', 'Singapore'),
('Penang Port', 'Malaysia'),
('Langkawi Cruise Terminal', 'Malaysia'),
('Phuket Deep Sea Port', 'Thailand'),
('Krabi Cruise Port', 'Thailand');

INSERT INTO RoutePort (RouteID, PortID, StopSequence, IsHomePort)
VALUES
(1, 1, 1, TRUE),
(1, 2, 2, FALSE),
(2, 3, 1, TRUE),
(2, 4, 2, FALSE),
(2, 3, 3, TRUE),
(3, 1, 1, TRUE),
(3, 4, 2, FALSE),
(3, 5, 3, FALSE),
(3, 6, 4, FALSE),
(3, 1, 5, TRUE);

INSERT INTO Cabin (ShipID, CabinCategoryID, CabinNumber, DeckNumber, MaxOccupancy, IsWheelchairAccessible)
VALUES
-- GLCL Majesty (ShipID 1)
(1, 1, 'I-801',  8,  4, FALSE),
(1, 2, 'O-802',  8,  4, FALSE),
(1, 2, 'O-803',  8,  4, FALSE),
(1, 3, 'B-901',  9,  5, TRUE),
(1, 4, 'S-1001', 10, 5, TRUE),
-- GLCL Pearl (ShipID 2)
(2, 1, 'I-501',  5,  4, FALSE),
(2, 2, 'O-502',  5,  4, FALSE),
(2, 3, 'B-601',  6,  5, TRUE),
(2, 4, 'S-701',  7,  5, TRUE),
-- Oceanic Star (ShipID 3)
(3, 1, 'I-601',  6,  4, FALSE),
(3, 2, 'O-602',  6,  4, FALSE),
(3, 3, 'B-701',  7,  5, TRUE),
(3, 4, 'S-801',  8,  5, TRUE);

/*
    CabinAdjacency: O-802 and O-803 on GLCL Majesty are physically
    adjacent cabins on Deck 8. This supports the teen-guardian rule.
*/
INSERT INTO CabinAdjacency (CabinID, AdjacentCabinID, AdjacencyType)
VALUES
(2, 3, 'Adjacent'),
(3, 2, 'Adjacent');

INSERT INTO ShipDiningOption (ShipID, DiningOptionID)
VALUES
(1, 1),
(1, 2),
(1, 3),
(2, 1),
(2, 3),
(3, 2),
(3, 3);

INSERT INTO SpecialtyDiningType (TypeName, Description)
VALUES
('Vegan',           'Fully plant-based menu with no animal products.'),
('Gluten-Free',     'Dishes prepared without gluten-containing ingredients.'),
('Halal',           'Meals prepared in accordance with Islamic dietary laws.'),
('Kosher',          'Meals prepared in accordance with Jewish dietary laws.'),
('Low-Sodium',      'Heart-healthy dishes with reduced sodium content.'),
('Seafood Grill',   'Premium fresh seafood grilled to order.');

/* Ships that offer specialty dining offer specific cuisine types. */
INSERT INTO ShipSpecialtyDining (ShipID, SpecialtyDiningTypeID)
VALUES
-- GLCL Majesty (ShipID 1): Vegan, Gluten-Free, Halal, Seafood Grill
(1, 1),
(1, 2),
(1, 3),
(1, 6),
-- GLCL Pearl (ShipID 2): Vegan, Halal
(2, 1),
(2, 3),
-- Oceanic Star (ShipID 3): Gluten-Free, Low-Sodium, Seafood Grill
(3, 2),
(3, 5),
(3, 6);

INSERT INTO CruiseVoyage (ShipID, RouteID, DepartureDateTime, ArrivalDateTime, BaggageWeightLimitKG, VoyageStatus)
VALUES
(1, 1, '2026-08-01 18:00:00', '2026-08-03 08:00:00', 25.00, 'Scheduled'),
(1, 3, '2026-09-10 17:00:00', '2026-09-18 09:00:00', 30.00, 'Scheduled');

/*
    FareRule covers all four cabin categories for both voyages
    and all four billable age categories (Child, Teen, Adult, Senior).
    Infants are calculated dynamically in the trigger from Adult/Child fares,
    so they do not need a FareRule row.
*/
INSERT INTO FareRule (VoyageID, CabinCategoryID, AgeCategoryID, BaseFare, EffectiveFrom, EffectiveTo)
VALUES
-- Voyage 1 (One-way, 2 days) — CabinCategoryID: 1=Interior, 2=OceanView, 3=Balcony, 4=Suite
-- AgeCategoryID: 2=Child, 3=Teen, 4=Adult, 5=Senior
(1, 1, 2,  600.00, '2026-01-01', NULL),
(1, 1, 3,  750.00, '2026-01-01', NULL),
(1, 1, 4, 1000.00, '2026-01-01', NULL),
(1, 1, 5,  850.00, '2026-01-01', NULL),

(1, 2, 2,  850.00, '2026-01-01', NULL),
(1, 2, 3, 1000.00, '2026-01-01', NULL),
(1, 2, 4, 1350.00, '2026-01-01', NULL),
(1, 2, 5, 1150.00, '2026-01-01', NULL),

(1, 3, 2, 1100.00, '2026-01-01', NULL),
(1, 3, 3, 1300.00, '2026-01-01', NULL),
(1, 3, 4, 1750.00, '2026-01-01', NULL),
(1, 3, 5, 1500.00, '2026-01-01', NULL),

(1, 4, 2, 1800.00, '2026-01-01', NULL),
(1, 4, 3, 2100.00, '2026-01-01', NULL),
(1, 4, 4, 2800.00, '2026-01-01', NULL),
(1, 4, 5, 2500.00, '2026-01-01', NULL),

-- Voyage 2 (Multi-destination, 8 days)
(2, 1, 2, 1200.00, '2026-01-01', NULL),
(2, 1, 3, 1500.00, '2026-01-01', NULL),
(2, 1, 4, 2000.00, '2026-01-01', NULL),
(2, 1, 5, 1750.00, '2026-01-01', NULL),

(2, 2, 2, 1600.00, '2026-01-01', NULL),
(2, 2, 3, 2000.00, '2026-01-01', NULL),
(2, 2, 4, 2700.00, '2026-01-01', NULL),
(2, 2, 5, 2400.00, '2026-01-01', NULL),

(2, 3, 2, 1800.00, '2026-01-01', NULL),
(2, 3, 3, 2300.00, '2026-01-01', NULL),
(2, 3, 4, 3200.00, '2026-01-01', NULL),
(2, 3, 5, 2800.00, '2026-01-01', NULL),

(2, 4, 2, 3000.00, '2026-01-01', NULL),
(2, 4, 3, 3800.00, '2026-01-01', NULL),
(2, 4, 4, 5200.00, '2026-01-01', NULL),
(2, 4, 5, 4600.00, '2026-01-01', NULL);

/*
    VoyageMealPackage: Voyage 1 is 2 days → all-inclusive (rule 2).
    Voyage 2 is 8 days → all-inclusive (rule 2).
*/
INSERT INTO VoyageMealPackage (VoyageID, MealPackageRuleID)
VALUES
(1, 2),
(2, 2);

INSERT INTO BaggageRule (OperatorID, MaxWeightKG, EffectiveFrom, EffectiveTo)
VALUES
(1, 30.00, '2026-01-01', NULL),
(2, 25.00, '2026-01-01', NULL);

/*
    Excursions are defined per port.
    VoyageExcursion ties each excursion to a specific voyage stop (RoutePort).
    RoutePortID reference: see RoutePort inserts above.
      RoutePortID 2  = Singapore (Route 1, stop 2)
      RoutePortID 4  = Langkawi  (Route 3, stop 2)
      RoutePortID 5  = Phuket    (Route 3, stop 3)
      RoutePortID 6  = Krabi     (Route 3, stop 4)
*/
INSERT INTO Excursion (PortID, ExcursionName, Description, DurationHours, Price)
VALUES
-- Singapore (PortID 2)
(2, 'Gardens by the Bay Night Tour',   'Guided evening tour of the iconic garden domes.',  3.00,  85.00),
(2, 'Sentosa Island Beach Day',        'Full-day beach and resort experience.',             8.00, 120.00),
-- Langkawi (PortID 4)
(4, 'Mangrove Kayak Adventure',        'Guided kayaking through Langkawi mangrove forests.', 4.00,  75.00),
(4, 'Eagle Square & Cable Car Tour',   'Visit Eagle Square and ride the Langkawi cable car.', 5.00,  95.00),
-- Phuket (PortID 5)
(5, 'Phi Phi Island Snorkel Trip',     'Speedboat trip to Phi Phi Island with snorkelling.', 7.00, 110.00),
(5, 'Old Phuket Town Heritage Walk',   'Walking tour through the historic Sino-Portuguese district.', 3.00,  50.00),
-- Krabi (PortID 6)
(6, 'Railay Beach Longtail Boat Trip', 'Longtail boat excursion to the secluded Railay Beach.', 5.00,  90.00),
(6, 'Tiger Cave Temple Hike',          'Guided hike up 1,237 steps to the Tiger Cave Temple summit.', 4.00,  60.00);

/*
    VoyageExcursion: link excursions to Voyage 2 (Multi-destination, ShipID 1).
    Voyage 2 stops at Langkawi (RoutePortID 8), Phuket (RoutePortID 9), Krabi (RoutePortID 10).
*/
INSERT INTO VoyageExcursion (VoyageID, RoutePortID, ExcursionID, AvailableSlots)
VALUES
-- Langkawi stop (RoutePortID 8, ExcursionID 3 & 4)
(2, 8,  3, 30),
(2, 8,  4, 40),
-- Phuket stop (RoutePortID 9, ExcursionID 5 & 6)
(2, 9,  5, 25),
(2, 9,  6, 50),
-- Krabi stop (RoutePortID 10, ExcursionID 7 & 8)
(2, 10, 7, 35),
(2, 10, 8, 45);

INSERT INTO CancellationPolicy (OperatorID, HoursBeforeDeparture, PenaltyType, PenaltyValue)
VALUES
(1, 48, 'FullForfeit', 100.00),
(2, 48, 'FullForfeit', 100.00);

/* =========================================================
   10. USEFUL REPORTING VIEWS
   ========================================================= */

CREATE VIEW vw_BookingPassengerDetails AS
SELECT
    b.BookingID,
    b.BookingDate,
    b.BookingStatus,
    v.VoyageID,
    r.RouteName,
    r.RouteType,
    s.ShipName,
    c.CabinNumber,
    cc.CategoryName AS CabinCategory,
    p.PassengerID,
    p.FullName,
    p.PassportNo,
    fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime)) AS AgeAtDeparture,
    ac.CategoryName AS AgeCategory,
    bp.InfantBedOption,
    bp.IsChaperonedYouth,
    bp.FinalFare
FROM BookingPassenger bp
INNER JOIN Booking b ON bp.BookingID = b.BookingID
INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
INNER JOIN CruiseRoute r ON v.RouteID = r.RouteID
INNER JOIN CruiseShip s ON v.ShipID = s.ShipID
INNER JOIN BookingCabin bc ON bp.BookingCabinID = bc.BookingCabinID
INNER JOIN Cabin c ON bc.CabinID = c.CabinID
INNER JOIN CabinCategory cc ON c.CabinCategoryID = cc.CabinCategoryID
INNER JOIN Passenger p ON bp.PassengerID = p.PassengerID
INNER JOIN AgeCategory ac ON bp.AgeCategoryID = ac.AgeCategoryID;

CREATE VIEW vw_VoyageCabinAvailability AS
SELECT
    v.VoyageID,
    s.ShipName,
    r.RouteName,
    c.CabinID,
    c.CabinNumber,
    cc.CategoryName AS CabinCategory,
    c.MaxOccupancy,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM BookingCabin bc
            INNER JOIN Booking b ON bc.BookingID = b.BookingID
            WHERE b.VoyageID = v.VoyageID
              AND bc.CabinID = c.CabinID
              AND b.BookingStatus IN ('Pending', 'Confirmed')
        ) THEN 'Booked'
        ELSE 'Available'
    END AS AvailabilityStatus
FROM CruiseVoyage v
INNER JOIN CruiseShip s ON v.ShipID = s.ShipID
INNER JOIN CruiseRoute r ON v.RouteID = r.RouteID
INNER JOIN Cabin c ON s.ShipID = c.ShipID
INNER JOIN CabinCategory cc ON c.CabinCategoryID = cc.CabinCategoryID;

SELECT 'GLCL_DB MySQL database created successfully.' AS Message;

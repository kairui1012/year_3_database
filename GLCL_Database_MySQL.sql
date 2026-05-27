/*
 * ============================================================
 *  GLOBAL LUXURY CRUISE LINES (GLCL)
 *  MySQL 8+ Database Script
 *
 *  Scope:
 *    - Cruise reservations
 *    - Cabin and passenger management
 *    - Dining, special services, and baggage
 *    - Onshore excursions
 *    - Cancellations and rescheduling
 *    - Payments
 *
 *  Standards:
 *    - MySQL 8.0 or above
 *    - 3NF normalisation unless noted otherwise
 *    - PascalCase table and column names
 *    - Constraint naming: PK_, FK_, CK_, UQ_
 * ============================================================
 */

DROP DATABASE IF EXISTS GLCL_DB;
CREATE DATABASE GLCL_DB;
USE GLCL_DB;

/* ============================================================
   SECTION 1: OPERATOR, SHIP, AND CABIN
   ============================================================ */

/*
 * CruiseOperator
 * Stores each cruise operator managed by GLCL.
 * AllowsChaperonedYouth controls whether the operator offers
 * the supervised teen travel programme for ages 15–17.
 */
CREATE TABLE CruiseOperator (
    OperatorID             INT           AUTO_INCREMENT PRIMARY KEY,
    OperatorName           VARCHAR(150)  NOT NULL UNIQUE,
    HeadquartersCountry    VARCHAR(100)  NOT NULL,
    ContactEmail           VARCHAR(150),
    AllowsChaperonedYouth  BOOLEAN       NOT NULL DEFAULT FALSE
);

/*
 * CruiseShip
 * A ship belongs to exactly one operator.
 * ShipName must be unique within the same operator.
 */
CREATE TABLE CruiseShip (
    ShipID             INT           AUTO_INCREMENT PRIMARY KEY,
    OperatorID         INT           NOT NULL,
    ShipName           VARCHAR(150)  NOT NULL,
    TotalDecks         INT           NOT NULL,
    PassengerCapacity  INT           NOT NULL,
    CONSTRAINT FK_CruiseShip_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID),
    CONSTRAINT CK_CruiseShip_TotalDecks
        CHECK (TotalDecks > 0),
    CONSTRAINT CK_CruiseShip_PassengerCapacity
        CHECK (PassengerCapacity > 0),
    CONSTRAINT UQ_CruiseShip_Operator_ShipName
        UNIQUE (OperatorID, ShipName)
);

/*
 * CabinCategory
 * Lookup table for the four permitted cabin types:
 *   Interior | Ocean View | Balcony | Suite
 */
CREATE TABLE CabinCategory (
    CabinCategoryID      INT           AUTO_INCREMENT PRIMARY KEY,
    CategoryName         VARCHAR(50)   NOT NULL UNIQUE,
    CategoryDescription  VARCHAR(255),
    CONSTRAINT CK_CabinCategory_CategoryName
        CHECK (CategoryName IN ('Interior', 'Ocean View', 'Balcony', 'Suite'))
);

/*
 * Cabin
 * Physical cabin on a specific ship.
 * Business rule: maximum occupancy is 5 passengers per cabin.
 * IsWheelchairAccessible supports the accessibility service requirement.
 */
CREATE TABLE Cabin (
    CabinID                INT           AUTO_INCREMENT PRIMARY KEY,
    ShipID                 INT           NOT NULL,
    CabinCategoryID        INT           NOT NULL,
    CabinNumber            VARCHAR(20)   NOT NULL,
    DeckNumber             INT           NOT NULL,
    MaxOccupancy           INT           NOT NULL,
    IsWheelchairAccessible BOOLEAN       NOT NULL DEFAULT FALSE,
    CONSTRAINT FK_Cabin_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_Cabin_CabinCategory
        FOREIGN KEY (CabinCategoryID) REFERENCES CabinCategory(CabinCategoryID),
    -- Business rule: strict maximum of 5 passengers per cabin
    CONSTRAINT CK_Cabin_MaxOccupancy
        CHECK (MaxOccupancy BETWEEN 1 AND 5),
    CONSTRAINT CK_Cabin_DeckNumber
        CHECK (DeckNumber > 0),
    CONSTRAINT UQ_Cabin_Ship_CabinNumber
        UNIQUE (ShipID, CabinNumber)
);

/*
 * CabinAdjacency
 * Records which cabins are physically adjacent or connecting.
 * Business rule: a minor (age ≤ 17) may occupy a cabin without
 * an adult in the same cabin ONLY if an adult guardian is booked
 * in an adjacent or connecting cabin on the same voyage.
 * Rows must be inserted bidirectionally (A→B and B→A).
 */
CREATE TABLE CabinAdjacency (
    CabinAdjacencyID  INT          AUTO_INCREMENT PRIMARY KEY,
    CabinID           INT          NOT NULL,
    AdjacentCabinID   INT          NOT NULL,
    AdjacencyType     VARCHAR(20)  NOT NULL DEFAULT 'Adjacent',
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

/* ============================================================
   SECTION 2: ROUTE AND VOYAGE
   ============================================================ */

/*
 * CruiseRoute
 * Defines the sailing itinerary type:
 *   One-way | Round-trip | Multi-destination
 */
CREATE TABLE CruiseRoute (
    RouteID    INT           AUTO_INCREMENT PRIMARY KEY,
    RouteName  VARCHAR(150)  NOT NULL,
    RouteType  VARCHAR(30)   NOT NULL,
    CONSTRAINT CK_CruiseRoute_RouteType
        CHECK (RouteType IN ('One-way', 'Round-trip', 'Multi-destination'))
);

/*
 * Port
 * A port of call or home port used in cruise routes.
 * Unique on (PortName, Country) to avoid duplicate entries.
 */
CREATE TABLE Port (
    PortID    INT           AUTO_INCREMENT PRIMARY KEY,
    PortName  VARCHAR(150)  NOT NULL,
    Country   VARCHAR(100)  NOT NULL,
    CONSTRAINT UQ_Port_Name_Country
        UNIQUE (PortName, Country)
);

/*
 * RoutePort
 * Junction between a route and its ports, ordered by StopSequence.
 * IsHomePort marks the departure/home port of the itinerary.
 */
CREATE TABLE RoutePort (
    RoutePortID    INT      AUTO_INCREMENT PRIMARY KEY,
    RouteID        INT      NOT NULL,
    PortID         INT      NOT NULL,
    StopSequence   INT      NOT NULL,
    IsHomePort     BOOLEAN  NOT NULL DEFAULT FALSE,
    CONSTRAINT FK_RoutePort_CruiseRoute
        FOREIGN KEY (RouteID) REFERENCES CruiseRoute(RouteID),
    CONSTRAINT FK_RoutePort_Port
        FOREIGN KEY (PortID) REFERENCES Port(PortID),
    CONSTRAINT CK_RoutePort_StopSequence
        CHECK (StopSequence > 0),
    CONSTRAINT UQ_RoutePort_Route_StopSequence
        UNIQUE (RouteID, StopSequence)
);

/*
 * CruiseVoyage
 * A specific scheduled sailing of a ship along a route.
 * VoyageLengthDays is a computed column (ArrivalDateTime - DepartureDateTime).
 * BaggageWeightLimitKG enforces the per-passenger baggage limit for this voyage.
 */
CREATE TABLE CruiseVoyage (
    VoyageID              INT             AUTO_INCREMENT PRIMARY KEY,
    ShipID                INT             NOT NULL,
    RouteID               INT             NOT NULL,
    DepartureDateTime     DATETIME        NOT NULL,
    ArrivalDateTime       DATETIME        NOT NULL,
    -- Computed: number of days between departure and arrival
    VoyageLengthDays      INT             GENERATED ALWAYS AS (DATEDIFF(ArrivalDateTime, DepartureDateTime)) STORED,
    BaggageWeightLimitKG  DECIMAL(6,2)    NOT NULL,
    VoyageStatus          VARCHAR(30)     NOT NULL DEFAULT 'Scheduled',
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

/* ============================================================
   SECTION 3: PASSENGER, AGE CATEGORY, BOOKING
   ============================================================ */

/*
 * Passenger
 * A person who can be booked on a voyage.
 * PassportNo is globally unique (used as identity in bookings).
 */
CREATE TABLE Passenger (
    PassengerID  INT           AUTO_INCREMENT PRIMARY KEY,
    FullName     VARCHAR(150)  NOT NULL,
    DateOfBirth  DATE          NOT NULL,
    PassportNo   VARCHAR(50)   NOT NULL UNIQUE,
    Nationality  VARCHAR(100)  NOT NULL,
    Gender       VARCHAR(20),
    ContactNo    VARCHAR(30),
    Email        VARCHAR(150)
);

/*
 * AgeCategory
 * Lookup table for GLCL fare age bands:
 *   Infant (0–1) | Child (2–12) | Teen (13–17) | Adult (18–59) | Senior (60+)
 * MaxAge is NULL for the Senior category (no upper bound).
 */
CREATE TABLE AgeCategory (
    AgeCategoryID  INT          AUTO_INCREMENT PRIMARY KEY,
    CategoryName   VARCHAR(30)  NOT NULL UNIQUE,
    MinAge         INT          NOT NULL,
    MaxAge         INT          NULL,
    CONSTRAINT CK_AgeCategory_AgeRange
        CHECK (MinAge >= 0 AND (MaxAge IS NULL OR MaxAge >= MinAge))
);

/*
 * Booking
 * A reservation made by a customer (CustomerPassengerID) for a voyage.
 * TotalAmount is the sum of all passenger fares within this booking.
 * OriginalBookingID self-references the booking replaced by a reschedule.
 */
CREATE TABLE Booking (
    BookingID            INT             AUTO_INCREMENT PRIMARY KEY,
    BookingDate          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CustomerPassengerID  INT             NOT NULL,
    VoyageID             INT             NOT NULL,
    BookingStatus        VARCHAR(30)     NOT NULL DEFAULT 'Confirmed',
    TotalAmount          DECIMAL(12,2)   NOT NULL DEFAULT 0,
    -- NULL unless this booking replaced an earlier one via reschedule
    OriginalBookingID    INT             NULL,
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

/*
 * BookingCabin
 * Links a booking to a specific cabin.
 * A cabin may only appear once per booking (UQ constraint).
 * Double-booking prevention for the same voyage is handled by trigger.
 */
CREATE TABLE BookingCabin (
    BookingCabinID  INT            AUTO_INCREMENT PRIMARY KEY,
    BookingID       INT            NOT NULL,
    CabinID         INT            NOT NULL,
    CabinPrice      DECIMAL(12,2)  NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingCabin_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BookingCabin_Cabin
        FOREIGN KEY (CabinID) REFERENCES Cabin(CabinID),
    CONSTRAINT CK_BookingCabin_CabinPrice
        CHECK (CabinPrice >= 0),
    CONSTRAINT UQ_BookingCabin_Booking_Cabin
        UNIQUE (BookingID, CabinID)
);

/*
 * FareRule
 * Defines the base fare for a (Voyage, CabinCategory, AgeCategory) combination.
 * EffectiveFrom/EffectiveTo allow time-limited fare changes.
 * Infant fares are NOT stored here — they are computed dynamically from
 * Adult and Child fares in the BookingPassenger insert trigger.
 */
CREATE TABLE FareRule (
    FareRuleID       INT            AUTO_INCREMENT PRIMARY KEY,
    VoyageID         INT            NOT NULL,
    CabinCategoryID  INT            NOT NULL,
    AgeCategoryID    INT            NOT NULL,
    BaseFare         DECIMAL(12,2)  NOT NULL,
    EffectiveFrom    DATE           NOT NULL,
    EffectiveTo      DATE           NULL,
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

/*
 * BookingPassenger
 * Links a specific passenger to a cabin within a booking.
 * FinalFare is automatically computed by the insert/update trigger:
 *   - Infant (SharedBed): 15% of adult base fare
 *   - Infant (Cot):       50% of child base fare
 *   - All others:         base fare from FareRule
 * DailySupervisionFee is set by the trigger when IsChaperonedYouth = TRUE.
 */
CREATE TABLE BookingPassenger (
    BookingPassengerID    INT            AUTO_INCREMENT PRIMARY KEY,
    BookingID             INT            NOT NULL,
    BookingCabinID        INT            NOT NULL,
    PassengerID           INT            NOT NULL,
    AgeCategoryID         INT            NOT NULL,
    -- NULL for infants (fare is derived, not from a FareRule row)
    FareRuleID            INT            NULL,
    -- 'SharedBed' or 'Cot' for infants; 'NotApplicable' for all others
    InfantBedOption       VARCHAR(20)    NOT NULL DEFAULT 'NotApplicable',
    IsChaperonedYouth     BOOLEAN        NOT NULL DEFAULT FALSE,
    -- Set by trigger from SpecialService.Fee where ServiceType = 'Chaperoned Youth'
    DailySupervisionFee   DECIMAL(10,2)  NOT NULL DEFAULT 0,
    -- Computed and set by trigger on insert/update
    FinalFare             DECIMAL(12,2)  NOT NULL DEFAULT 0,
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
    -- A passenger can only appear once per booking
    CONSTRAINT UQ_BookingPassenger_Booking_Passenger
        UNIQUE (BookingID, PassengerID)
);

/* ============================================================
   SECTION 4: DINING
   ============================================================ */

/*
 * DiningOption
 * The three dining styles available on GLCL ships.
 */
CREATE TABLE DiningOption (
    DiningOptionID  INT           AUTO_INCREMENT PRIMARY KEY,
    DiningName      VARCHAR(100)  NOT NULL UNIQUE,
    CONSTRAINT CK_DiningOption_DiningName
        CHECK (DiningName IN ('Fixed-time dining', 'Flexible dining', 'Specialty restaurant'))
);

/*
 * ShipDiningOption
 * Many-to-many: which dining options a specific ship offers.
 */
CREATE TABLE ShipDiningOption (
    ShipDiningOptionID  INT  AUTO_INCREMENT PRIMARY KEY,
    ShipID              INT  NOT NULL,
    DiningOptionID      INT  NOT NULL,
    CONSTRAINT FK_ShipDiningOption_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_ShipDiningOption_DiningOption
        FOREIGN KEY (DiningOptionID) REFERENCES DiningOption(DiningOptionID),
    CONSTRAINT UQ_ShipDiningOption_Ship_DiningOption
        UNIQUE (ShipID, DiningOptionID)
);

/*
 * SpecialtyDiningType
 * Cuisine or dietary categories offered at specialty restaurants
 * (e.g., Vegan, Gluten-Free, Halal, Kosher).
 */
CREATE TABLE SpecialtyDiningType (
    SpecialtyDiningTypeID  INT           AUTO_INCREMENT PRIMARY KEY,
    TypeName               VARCHAR(100)  NOT NULL UNIQUE,
    Description            VARCHAR(255)
);

/*
 * ShipSpecialtyDining
 * Many-to-many: which specialty dining types a specific ship provides.
 */
CREATE TABLE ShipSpecialtyDining (
    ShipSpecialtyDiningID  INT  AUTO_INCREMENT PRIMARY KEY,
    ShipID                 INT  NOT NULL,
    SpecialtyDiningTypeID  INT  NOT NULL,
    CONSTRAINT FK_ShipSpecialtyDining_CruiseShip
        FOREIGN KEY (ShipID) REFERENCES CruiseShip(ShipID),
    CONSTRAINT FK_ShipSpecialtyDining_SpecialtyDiningType
        FOREIGN KEY (SpecialtyDiningTypeID) REFERENCES SpecialtyDiningType(SpecialtyDiningTypeID),
    CONSTRAINT UQ_ShipSpecialtyDining_Ship_Type
        UNIQUE (ShipID, SpecialtyDiningTypeID)
);

/*
 * VoyageMealPackageType
 * Two possible meal package types based on voyage length:
 *   - Standard boarding meal   (1-day voyages)
 *   - Multi-day all-inclusive  (2+ day voyages)
 */
CREATE TABLE VoyageMealPackageType (
    MealPackageTypeID  INT           AUTO_INCREMENT PRIMARY KEY,
    PackageName        VARCHAR(100)  NOT NULL UNIQUE,
    CONSTRAINT CK_VoyageMealPackageType_PackageName
        CHECK (PackageName IN ('Standard boarding meal', 'Multi-day all-inclusive dining package'))
);

/*
 * VoyageMealPackageRule
 * Maps a voyage length band to a meal package type.
 * MaxVoyageLengthDays is NULL for open-ended upper bounds.
 */
CREATE TABLE VoyageMealPackageRule (
    MealPackageRuleID    INT  AUTO_INCREMENT PRIMARY KEY,
    MealPackageTypeID    INT  NOT NULL,
    MinVoyageLengthDays  INT  NOT NULL,
    MaxVoyageLengthDays  INT  NULL,
    CONSTRAINT FK_VoyageMealPackageRule_VoyageMealPackageType
        FOREIGN KEY (MealPackageTypeID) REFERENCES VoyageMealPackageType(MealPackageTypeID),
    CONSTRAINT CK_VoyageMealPackageRule_LengthRange
        CHECK (MinVoyageLengthDays > 0
               AND (MaxVoyageLengthDays IS NULL OR MaxVoyageLengthDays >= MinVoyageLengthDays)),
    CONSTRAINT UQ_VoyageMealPackageRule_LengthBand
        UNIQUE (MinVoyageLengthDays, MaxVoyageLengthDays)
);

/*
 * VoyageMealPackage
 * Assigns the applicable meal package rule to a specific voyage.
 * Each voyage has exactly one meal package (unique on VoyageID).
 */
CREATE TABLE VoyageMealPackage (
    VoyageMealPackageID  INT  AUTO_INCREMENT PRIMARY KEY,
    VoyageID             INT  NOT NULL,
    MealPackageRuleID    INT  NOT NULL,
    CONSTRAINT FK_VoyageMealPackage_CruiseVoyage
        FOREIGN KEY (VoyageID) REFERENCES CruiseVoyage(VoyageID),
    CONSTRAINT FK_VoyageMealPackage_VoyageMealPackageRule
        FOREIGN KEY (MealPackageRuleID) REFERENCES VoyageMealPackageRule(MealPackageRuleID),
    CONSTRAINT UQ_VoyageMealPackage_Voyage
        UNIQUE (VoyageID)
);

/* ============================================================
   SECTION 5: SPECIAL SERVICES AND BAGGAGE
   ============================================================ */

/*
 * SpecialService
 * Defines available special services and their age restrictions.
 * Types: Childcare | Teen Club | Accessibility | Mobility | Chaperoned Youth
 * Fee for 'Chaperoned Youth' is used by the trigger as DailySupervisionFee.
 */
CREATE TABLE SpecialService (
    ServiceID          INT            AUTO_INCREMENT PRIMARY KEY,
    ServiceName        VARCHAR(100)   NOT NULL UNIQUE,
    ServiceType        VARCHAR(50)    NOT NULL,
    AgeRestrictionMin  INT            NULL,
    AgeRestrictionMax  INT            NULL,
    Fee                DECIMAL(10,2)  NOT NULL DEFAULT 0,
    CONSTRAINT CK_SpecialService_ServiceType
        CHECK (ServiceType IN ('Childcare', 'Teen Club', 'Accessibility', 'Mobility', 'Chaperoned Youth')),
    -- Age restriction must be either fully specified or fully absent
    CONSTRAINT CK_SpecialService_AgeRestriction
        CHECK (
            (AgeRestrictionMin IS NULL AND AgeRestrictionMax IS NULL)
            OR
            (AgeRestrictionMin IS NOT NULL AND AgeRestrictionMax IS NOT NULL
             AND AgeRestrictionMax >= AgeRestrictionMin)
        ),
    CONSTRAINT CK_SpecialService_Fee
        CHECK (Fee >= 0)
);

/*
 * PassengerSpecialService
 * Records a special service request for a specific booked passenger.
 * One passenger cannot request the same service twice (UQ constraint).
 */
CREATE TABLE PassengerSpecialService (
    PassengerServiceID  INT            AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT            NOT NULL,
    ServiceID           INT            NOT NULL,
    RequestStatus       VARCHAR(30)    NOT NULL DEFAULT 'Requested',
    Fee                 DECIMAL(10,2)  NOT NULL DEFAULT 0,
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

/*
 * BaggageRule
 * Per-operator baggage weight rules with effective date ranges.
 * EffectiveTo NULL means the rule is currently in force.
 */
CREATE TABLE BaggageRule (
    BaggageRuleID  INT            AUTO_INCREMENT PRIMARY KEY,
    OperatorID     INT            NOT NULL,
    MaxWeightKG    DECIMAL(6,2)   NOT NULL,
    EffectiveFrom  DATE           NOT NULL,
    EffectiveTo    DATE           NULL,
    CONSTRAINT FK_BaggageRule_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID),
    CONSTRAINT CK_BaggageRule_MaxWeight
        CHECK (MaxWeightKG > 0),
    CONSTRAINT CK_BaggageRule_EffectiveDate
        CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
);

/*
 * BookingBaggage
 * Records the actual baggage weight declared for a booked passenger.
 * IsOverLimit and ExcessFee are set automatically by the insert/update trigger,
 * comparing WeightKG against the voyage's BaggageWeightLimitKG.
 */
CREATE TABLE BookingBaggage (
    BaggageID           INT            AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT            NOT NULL,
    WeightKG            DECIMAL(6,2)   NOT NULL,
    -- Computed by trigger: TRUE if WeightKG exceeds voyage limit
    IsOverLimit         BOOLEAN        NOT NULL DEFAULT FALSE,
    ExcessFee           DECIMAL(10,2)  NOT NULL DEFAULT 0,
    CONSTRAINT FK_BookingBaggage_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT CK_BookingBaggage_Weight
        CHECK (WeightKG >= 0),
    CONSTRAINT CK_BookingBaggage_ExcessFee
        CHECK (ExcessFee >= 0)
);

/* ============================================================
   SECTION 6: ONSHORE EXCURSIONS
   ============================================================ */

/*
 * Excursion
 * An activity available at a specific port of call.
 * Unique on (PortID, ExcursionName) to avoid duplicate entries per port.
 */
CREATE TABLE Excursion (
    ExcursionID    INT            AUTO_INCREMENT PRIMARY KEY,
    PortID         INT            NOT NULL,
    ExcursionName  VARCHAR(150)   NOT NULL,
    Description    VARCHAR(500),
    DurationHours  DECIMAL(5,2)   NOT NULL,
    Price          DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    CONSTRAINT FK_Excursion_Port
        FOREIGN KEY (PortID) REFERENCES Port(PortID),
    CONSTRAINT CK_Excursion_Price
        CHECK (Price >= 0),
    CONSTRAINT CK_Excursion_Duration
        CHECK (DurationHours > 0),
    CONSTRAINT UQ_Excursion_Port_Name
        UNIQUE (PortID, ExcursionName)
);

/*
 * VoyageExcursion
 * Links an excursion to a specific route stop (RoutePort) on a voyage,
 * and tracks available slot capacity.
 */
CREATE TABLE VoyageExcursion (
    VoyageExcursionID  INT  AUTO_INCREMENT PRIMARY KEY,
    VoyageID           INT  NOT NULL,
    RoutePortID        INT  NOT NULL,
    ExcursionID        INT  NOT NULL,
    AvailableSlots     INT  NOT NULL DEFAULT 0,
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

/*
 * BookingExcursion
 * Records a passenger's purchase of a voyage excursion.
 * Used to identify sold and unsold excursions via LEFT JOIN queries.
 */
CREATE TABLE BookingExcursion (
    BookingExcursionID  INT            AUTO_INCREMENT PRIMARY KEY,
    BookingPassengerID  INT            NOT NULL,
    VoyageExcursionID   INT            NOT NULL,
    BookingDateTime     DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ExcursionStatus     VARCHAR(30)    NOT NULL DEFAULT 'Booked',
    AmountPaid          DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    CONSTRAINT FK_BookingExcursion_BookingPassenger
        FOREIGN KEY (BookingPassengerID) REFERENCES BookingPassenger(BookingPassengerID),
    CONSTRAINT FK_BookingExcursion_VoyageExcursion
        FOREIGN KEY (VoyageExcursionID) REFERENCES VoyageExcursion(VoyageExcursionID),
    CONSTRAINT CK_BookingExcursion_Status
        CHECK (ExcursionStatus IN ('Booked', 'Cancelled', 'Completed')),
    CONSTRAINT CK_BookingExcursion_Amount
        CHECK (AmountPaid >= 0),
    -- A passenger can book the same excursion only once
    CONSTRAINT UQ_BookingExcursion_Passenger_Excursion
        UNIQUE (BookingPassengerID, VoyageExcursionID)
);

/* ============================================================
   SECTION 7: CANCELLATION, RESCHEDULING, AND PAYMENT
   ============================================================ */

/*
 * CancellationPolicy
 * Per-operator rules that define how penalties are applied based on
 * how far in advance of departure the cancellation is made.
 * PenaltyType: Percentage | FixedAmount | FullForfeit
 */
CREATE TABLE CancellationPolicy (
    PolicyID               INT            AUTO_INCREMENT PRIMARY KEY,
    OperatorID             INT            NOT NULL,
    HoursBeforeDeparture   INT            NOT NULL,
    PenaltyType            VARCHAR(30)    NOT NULL,
    PenaltyValue           DECIMAL(10,2)  NOT NULL,
    CONSTRAINT FK_CancellationPolicy_CruiseOperator
        FOREIGN KEY (OperatorID) REFERENCES CruiseOperator(OperatorID),
    CONSTRAINT CK_CancellationPolicy_Hours
        CHECK (HoursBeforeDeparture >= 0),
    CONSTRAINT CK_CancellationPolicy_PenaltyType
        CHECK (PenaltyType IN ('Percentage', 'FixedAmount', 'FullForfeit')),
    CONSTRAINT CK_CancellationPolicy_PenaltyValue
        CHECK (PenaltyValue >= 0)
);

/*
 * BookingCancellation
 * Records a cancellation event for a booking.
 * PenaltyAmount and RefundAmount are computed automatically by the
 * BEFORE INSERT trigger using the operator's CancellationPolicy.
 * The AFTER INSERT trigger then marks the Booking status as 'Cancelled'.
 * Business rule: cancellation < 48 hours before departure forfeits full fare.
 */
CREATE TABLE BookingCancellation (
    CancellationID        INT            AUTO_INCREMENT PRIMARY KEY,
    BookingID             INT            NOT NULL UNIQUE,
    CancellationDateTime  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Reason                VARCHAR(255),
    -- Computed by trigger
    PenaltyAmount         DECIMAL(12,2)  NOT NULL DEFAULT 0,
    RefundAmount          DECIMAL(12,2)  NOT NULL DEFAULT 0,
    ProcessedBy           VARCHAR(100),
    CONSTRAINT FK_BookingCancellation_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CK_BookingCancellation_Amounts
        CHECK (PenaltyAmount >= 0 AND RefundAmount >= 0)
);

/*
 * RescheduleRequest
 * Tracks a request to move a booking to a different voyage.
 * Business rules (enforced by trigger):
 *   1. Cannot reschedule after the original voyage has departed.
 *   2. New voyage must start within one year of the original booking date.
 *   3. Rescheduling < 48 hours before departure charges the full booking total.
 */
CREATE TABLE RescheduleRequest (
    RescheduleID       INT             AUTO_INCREMENT PRIMARY KEY,
    OriginalBookingID  INT             NOT NULL,
    -- Linked once the reschedule is approved and a new booking is created
    NewBookingID       INT             NULL,
    RequestDateTime    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    NewVoyageID        INT             NOT NULL,
    -- Computed by trigger when < 48 hours before departure
    RescheduleFee      DECIMAL(12,2)   NOT NULL DEFAULT 0,
    RequestStatus      VARCHAR(30)     NOT NULL DEFAULT 'Requested',
    Reason             VARCHAR(255),
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

/*
 * Payment
 * Records each payment transaction against a booking.
 * TransactionReference is unique to prevent duplicate payment records.
 */
CREATE TABLE Payment (
    PaymentID             INT             AUTO_INCREMENT PRIMARY KEY,
    BookingID             INT             NOT NULL,
    PaymentDateTime       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Amount                DECIMAL(12,2)   NOT NULL,
    PaymentMethod         VARCHAR(50)     NOT NULL,
    PaymentStatus         VARCHAR(30)     NOT NULL DEFAULT 'Pending',
    TransactionReference  VARCHAR(100)    UNIQUE,
    CONSTRAINT FK_Payment_Booking
        FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CK_Payment_Amount
        CHECK (Amount > 0),
    CONSTRAINT CK_Payment_Status
        CHECK (PaymentStatus IN ('Pending', 'Paid', 'Failed', 'Refunded', 'Partially Refunded'))
);

/* ============================================================
   SECTION 8: FUNCTION AND TRIGGERS
   ============================================================
   NOTE: MySQL does not support shared trigger body logic via
   a CALL within a trigger. As a result, the business rule logic
   is intentionally repeated in matching BEFORE INSERT (BI) and
   BEFORE UPDATE (BU) triggers. This is a MySQL limitation, not
   a design choice.
   ============================================================ */

DELIMITER $$

/*
 * fn_CalculateAge
 * Returns the age of a person in whole years on a given reference date.
 * Used in triggers to determine whether a passenger's age category
 * matches their actual age at voyage departure.
 */
CREATE FUNCTION fn_CalculateAge(DateOfBirth DATE, ReferenceDate DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    DECLARE AgeValue INT;
    SET AgeValue = TIMESTAMPDIFF(YEAR, DateOfBirth, ReferenceDate);
    RETURN AgeValue;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_Passenger_BI_ValidateDateOfBirth
   Purpose: Prevent a future date of birth from being inserted.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_Passenger_BI_ValidateDateOfBirth
BEFORE INSERT ON Passenger
FOR EACH ROW
BEGIN
    IF NEW.DateOfBirth > CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger date of birth cannot be in the future.';
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_Passenger_BU_ValidateDateOfBirth
   Purpose: Prevent a future date of birth from being updated.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_Passenger_BU_ValidateDateOfBirth
BEFORE UPDATE ON Passenger
FOR EACH ROW
BEGIN
    IF NEW.DateOfBirth > CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger date of birth cannot be in the future.';
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingCabin_BI_PreventDoubleBooking
   Purpose:
     1. Ensure the cabin belongs to the ship assigned to the voyage.
     2. Prevent the same cabin from being booked twice on the same voyage.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCabin_BI_PreventDoubleBooking
BEFORE INSERT ON BookingCabin
FOR EACH ROW
BEGIN
    DECLARE BookingShipID INT;
    DECLARE CabinShipID   INT;

    -- Retrieve the ship associated with the booking's voyage
    SELECT v.ShipID
    INTO BookingShipID
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = NEW.BookingID;

    -- Retrieve the ship to which this cabin belongs
    SELECT ShipID
    INTO CabinShipID
    FROM Cabin
    WHERE CabinID = NEW.CabinID;

    -- Business rule: cabin must be on the same ship as the voyage
    IF BookingShipID <> CabinShipID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cabin must belong to the ship assigned to the booked voyage.';
    END IF;

    -- Business rule: no double-booking of the same cabin on the same voyage
    IF EXISTS (
        SELECT 1
        FROM BookingCabin bc
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
   Trigger: TR_BookingCabin_BU_PreventDoubleBooking
   Purpose: Same double-booking checks applied on update.
            Excludes the current row (OLD.BookingCabinID) from
            the conflict check.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCabin_BU_PreventDoubleBooking
BEFORE UPDATE ON BookingCabin
FOR EACH ROW
BEGIN
    DECLARE BookingShipID INT;
    DECLARE CabinShipID   INT;

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
        INNER JOIN Booking b  ON bc.BookingID = b.BookingID
        INNER JOIN Booking nb ON NEW.BookingID = nb.BookingID
        WHERE bc.CabinID = NEW.CabinID
          AND bc.BookingCabinID <> OLD.BookingCabinID   -- exclude the row being updated
          AND b.VoyageID = nb.VoyageID
          AND b.BookingStatus  IN ('Pending', 'Confirmed')
          AND nb.BookingStatus IN ('Pending', 'Confirmed')
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This cabin is already booked for the same voyage.';
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingPassenger_BI_ValidateRules
   Purpose (in order):
     1.  Verify BookingCabin belongs to the same booking.
     2.  Enforce maximum cabin occupancy of 5.
     3.  Validate passenger age matches the selected AgeCategory.
     4.  Enforce InfantBedOption rules (SharedBed/Cot for infants only).
     5.  Validate Chaperoned Youth eligibility (ages 15–17, operator must allow).
     6.  Require adult guardian in same or adjacent/connecting cabin for minors.
     7.  Set DailySupervisionFee for Chaperoned Youth passengers.
     8.  Calculate FinalFare:
           - Infant SharedBed: 15% of adult base fare
           - Infant Cot:       50% of child base fare
           - All others:       base fare from matching FareRule
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_BI_ValidateRules
BEFORE INSERT ON BookingPassenger
FOR EACH ROW
BEGIN
    DECLARE CabinBookingID        INT;
    DECLARE CabinMaxOccupancy     INT;
    DECLARE ExistingPassengerCount INT;
    DECLARE PassengerAge          INT;
    DECLARE CategoryMinAge        INT;
    DECLARE CategoryMaxAge        INT;
    DECLARE CategoryNameValue     VARCHAR(30);
    DECLARE OperatorAllowsYouth   BOOLEAN;
    DECLARE CabinIDValue          INT;
    DECLARE FareRuleIDValue       INT;
    DECLARE BaseFareValue         DECIMAL(12,2);
    DECLARE AdultFareValue        DECIMAL(12,2);
    DECLARE ChildFareValue        DECIMAL(12,2);
    DECLARE HasAdultGuardian      INT DEFAULT 0;
    DECLARE SupervisionFeeValue   DECIMAL(10,2);

    -- Step 1: confirm the BookingCabin belongs to this booking
    SELECT bc.BookingID, c.MaxOccupancy, c.CabinID
    INTO CabinBookingID, CabinMaxOccupancy, CabinIDValue
    FROM BookingCabin bc
    INNER JOIN Cabin c ON bc.CabinID = c.CabinID
    WHERE bc.BookingCabinID = NEW.BookingCabinID;

    IF CabinBookingID <> NEW.BookingID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BookingPassenger.BookingID must match BookingCabin.BookingID.';
    END IF;

    -- Step 2: enforce maximum cabin occupancy (hard cap of 5 per GLCL rules)
    SELECT COUNT(*)
    INTO ExistingPassengerCount
    FROM BookingPassenger
    WHERE BookingCabinID = NEW.BookingCabinID;

    IF ExistingPassengerCount + 1 > CabinMaxOccupancy OR ExistingPassengerCount + 1 > 5 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A cabin can contain a maximum of 5 passengers only.';
    END IF;

    -- Step 3: retrieve passenger age at voyage departure and category bounds
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
    INNER JOIN Booking b       ON b.BookingID = NEW.BookingID
    INNER JOIN CruiseVoyage v  ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s    ON v.ShipID = s.ShipID
    INNER JOIN CruiseOperator co ON s.OperatorID = co.OperatorID
    INNER JOIN AgeCategory ac  ON ac.AgeCategoryID = NEW.AgeCategoryID
    WHERE p.PassengerID = NEW.PassengerID;

    -- Business rule: age category must match actual passenger age at departure
    IF PassengerAge < CategoryMinAge OR (CategoryMaxAge IS NOT NULL AND PassengerAge > CategoryMaxAge) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Passenger age category must match the passenger age at voyage departure.';
    END IF;

    -- Step 4: InfantBedOption validation
    -- Business rule: infants must specify SharedBed or Cot
    IF CategoryNameValue = 'Infant' AND NEW.InfantBedOption NOT IN ('SharedBed', 'Cot') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Infant passengers must have either SharedBed or Cot as InfantBedOption.';
    END IF;

    -- Business rule: non-infants must have InfantBedOption = 'NotApplicable'
    IF CategoryNameValue <> 'Infant' AND NEW.InfantBedOption <> 'NotApplicable' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'InfantBedOption must be NotApplicable for non-infant passengers.';
    END IF;

    -- Step 5: Chaperoned Youth eligibility
    -- Business rule: ages 15–17 only, operator must support the programme
    IF NEW.IsChaperonedYouth = TRUE
       AND (OperatorAllowsYouth = FALSE OR CategoryNameValue <> 'Teen' OR PassengerAge NOT BETWEEN 15 AND 17) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Chaperoned Youth is only allowed for age 15 to 17 when the operator supports the program.';
    END IF;

    -- Step 6: adult guardian requirement for minors (age ≤ 17) not in the programme
    IF PassengerAge <= 17 AND NEW.IsChaperonedYouth = FALSE THEN

        -- Check for an adult already assigned to the same cabin in this booking
        SELECT COUNT(*)
        INTO HasAdultGuardian
        FROM BookingPassenger bp
        INNER JOIN AgeCategory adult_ac ON bp.AgeCategoryID = adult_ac.AgeCategoryID
        WHERE bp.BookingID = NEW.BookingID
          AND adult_ac.MinAge >= 18
          AND bp.BookingCabinID = NEW.BookingCabinID;

        -- If no adult in the same cabin, check for an adult in an adjacent/connecting cabin
        -- Business rule: adult guardian in adjacent or connecting cabin is sufficient
        IF HasAdultGuardian = 0 THEN
            SELECT COUNT(*)
            INTO HasAdultGuardian
            FROM BookingPassenger   guardian_bp
            INNER JOIN AgeCategory  guardian_ac ON guardian_bp.AgeCategoryID = guardian_ac.AgeCategoryID
            INNER JOIN BookingCabin guardian_bc ON guardian_bp.BookingCabinID = guardian_bc.BookingCabinID
            INNER JOIN Booking      guardian_b  ON guardian_bc.BookingID = guardian_b.BookingID
            INNER JOIN BookingCabin teen_bc     ON teen_bc.BookingCabinID = NEW.BookingCabinID
            INNER JOIN CabinAdjacency ca        ON ca.CabinID = teen_bc.CabinID
                                               AND ca.AdjacentCabinID = guardian_bc.CabinID
            INNER JOIN Booking      teen_b      ON teen_b.BookingID = NEW.BookingID
            WHERE guardian_b.VoyageID = teen_b.VoyageID
              AND guardian_b.BookingStatus IN ('Pending', 'Confirmed')
              AND guardian_ac.MinAge >= 18;
        END IF;

        IF HasAdultGuardian = 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Passengers aged 17 or below require an adult in the same or adjacent cabin unless approved for Chaperoned Youth.';
        END IF;
    END IF;

    -- Step 7: set daily supervision fee for Chaperoned Youth passengers
    IF NEW.IsChaperonedYouth = TRUE THEN
        SELECT COALESCE(MAX(Fee), 0)
        INTO SupervisionFeeValue
        FROM SpecialService
        WHERE ServiceType = 'Chaperoned Youth';

        SET NEW.DailySupervisionFee = SupervisionFeeValue;
    ELSE
        SET NEW.DailySupervisionFee = 0;
    END IF;

    -- Step 8: compute FinalFare
    IF CategoryNameValue = 'Infant' THEN
        -- Infant SharedBed: 15% of adult base fare
        SELECT fr.BaseFare
        INTO AdultFareValue
        FROM FareRule fr
        INNER JOIN Booking b     ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c        ON c.CabinID = bc.CabinID
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

        -- Infant Cot: 50% of child base fare
        SELECT fr.BaseFare
        INTO ChildFareValue
        FROM FareRule fr
        INNER JOIN Booking b     ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c        ON c.CabinID = bc.CabinID
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

        SET NEW.FareRuleID = NULL;  -- infants have no direct FareRule row
        SET NEW.FinalFare = CASE
            WHEN NEW.InfantBedOption = 'SharedBed' THEN AdultFareValue * 0.15
            ELSE ChildFareValue * 0.50
        END;

    ELSE
        -- Non-infant: look up the base fare from FareRule
        SELECT fr.FareRuleID, fr.BaseFare
        INTO FareRuleIDValue, BaseFareValue
        FROM FareRule fr
        INNER JOIN Booking b     ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c        ON c.CabinID = bc.CabinID
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
        SET NEW.FinalFare  = BaseFareValue;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingPassenger_BU_ValidateRules
   Purpose: Same validations as the BI trigger applied on update.
            Key difference: excludes the current row from the
            occupancy count (AND BookingPassengerID <> OLD.BookingPassengerID).
            Adjacent cabin check is omitted on update because the
            guardian relationship was already verified on insert.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_BU_ValidateRules
BEFORE UPDATE ON BookingPassenger
FOR EACH ROW
BEGIN
    DECLARE CabinBookingID        INT;
    DECLARE CabinMaxOccupancy     INT;
    DECLARE ExistingPassengerCount INT;
    DECLARE PassengerAge          INT;
    DECLARE CategoryMinAge        INT;
    DECLARE CategoryMaxAge        INT;
    DECLARE CategoryNameValue     VARCHAR(30);
    DECLARE OperatorAllowsYouth   BOOLEAN;
    DECLARE CabinIDValue          INT;
    DECLARE FareRuleIDValue       INT;
    DECLARE BaseFareValue         DECIMAL(12,2);
    DECLARE AdultFareValue        DECIMAL(12,2);
    DECLARE ChildFareValue        DECIMAL(12,2);
    DECLARE HasAdultGuardian      INT DEFAULT 0;
    DECLARE SupervisionFeeValue   DECIMAL(10,2);

    SELECT bc.BookingID, c.MaxOccupancy, c.CabinID
    INTO CabinBookingID, CabinMaxOccupancy, CabinIDValue
    FROM BookingCabin bc
    INNER JOIN Cabin c ON bc.CabinID = c.CabinID
    WHERE bc.BookingCabinID = NEW.BookingCabinID;

    IF CabinBookingID <> NEW.BookingID THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BookingPassenger.BookingID must match BookingCabin.BookingID.';
    END IF;

    -- Exclude the row being updated from the occupancy count
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
    INNER JOIN Booking b       ON b.BookingID = NEW.BookingID
    INNER JOIN CruiseVoyage v  ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s    ON v.ShipID = s.ShipID
    INNER JOIN CruiseOperator co ON s.OperatorID = co.OperatorID
    INNER JOIN AgeCategory ac  ON ac.AgeCategoryID = NEW.AgeCategoryID
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

    -- On update: only check for an adult in the same cabin (guardian relationship
    -- already validated at insert; the adjacent-cabin check is not repeated here)
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
        INNER JOIN Booking b      ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID = bc.CabinID
        INNER JOIN AgeCategory ac  ON ac.AgeCategoryID = fr.AgeCategoryID
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
        INNER JOIN Booking b      ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID = bc.CabinID
        INNER JOIN AgeCategory ac  ON ac.AgeCategoryID = fr.AgeCategoryID
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
        INNER JOIN Booking b      ON b.BookingID = NEW.BookingID
        INNER JOIN BookingCabin bc ON bc.BookingCabinID = NEW.BookingCabinID
        INNER JOIN Cabin c         ON c.CabinID = bc.CabinID
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
        SET NEW.FinalFare  = BaseFareValue;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingBaggage_BI_ValidateLimit
   Purpose: Automatically set IsOverLimit by comparing the declared
            baggage weight against the voyage's BaggageWeightLimitKG.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingBaggage_BI_ValidateLimit
BEFORE INSERT ON BookingBaggage
FOR EACH ROW
BEGIN
    DECLARE AllowedWeight DECIMAL(6,2);

    SELECT v.BaggageWeightLimitKG
    INTO AllowedWeight
    FROM BookingPassenger bp
    INNER JOIN Booking b       ON bp.BookingID = b.BookingID
    INNER JOIN CruiseVoyage v  ON b.VoyageID = v.VoyageID
    WHERE bp.BookingPassengerID = NEW.BookingPassengerID;

    -- Business rule: flag baggage that exceeds the voyage weight limit
    SET NEW.IsOverLimit = NEW.WeightKG > AllowedWeight;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingBaggage_BU_ValidateLimit
   Purpose: Re-evaluate IsOverLimit when baggage weight is updated.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingBaggage_BU_ValidateLimit
BEFORE UPDATE ON BookingBaggage
FOR EACH ROW
BEGIN
    DECLARE AllowedWeight DECIMAL(6,2);

    SELECT v.BaggageWeightLimitKG
    INTO AllowedWeight
    FROM BookingPassenger bp
    INNER JOIN Booking b       ON bp.BookingID = b.BookingID
    INNER JOIN CruiseVoyage v  ON b.VoyageID = v.VoyageID
    WHERE bp.BookingPassengerID = NEW.BookingPassengerID;

    SET NEW.IsOverLimit = NEW.WeightKG > AllowedWeight;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingCancellation_BI_ApplyPenalty
   Purpose: Compute PenaltyAmount and RefundAmount based on the
            operator's CancellationPolicy and hours until departure.
   Business rule: cancellation < 48 hours before departure → full forfeit.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCancellation_BI_ApplyPenalty
BEFORE INSERT ON BookingCancellation
FOR EACH ROW
BEGIN
    DECLARE DepartureTime       DATETIME;
    DECLARE BookingTotal        DECIMAL(12,2);
    DECLARE HoursUntilDeparture INT;
    DECLARE PolicyPenaltyType   VARCHAR(30);
    DECLARE PolicyPenaltyValue  DECIMAL(10,2);

    -- Find the most applicable cancellation policy (closest threshold not exceeded)
    SELECT v.DepartureDateTime, b.TotalAmount, cp.PenaltyType, cp.PenaltyValue
    INTO DepartureTime, BookingTotal, PolicyPenaltyType, PolicyPenaltyValue
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s   ON v.ShipID = s.ShipID
    LEFT JOIN CancellationPolicy cp
        ON s.OperatorID = cp.OperatorID
       AND cp.HoursBeforeDeparture >= TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, v.DepartureDateTime)
    WHERE b.BookingID = NEW.BookingID
    ORDER BY cp.HoursBeforeDeparture ASC
    LIMIT 1;

    SET HoursUntilDeparture = TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, DepartureTime);

    -- Business rule: < 48 hours + FullForfeit policy → zero refund
    IF HoursUntilDeparture <= 48 AND PolicyPenaltyType = 'FullForfeit' THEN
        SET NEW.PenaltyAmount = BookingTotal;
        SET NEW.RefundAmount  = 0;
    ELSEIF PolicyPenaltyType = 'Percentage' THEN
        SET NEW.PenaltyAmount = BookingTotal * (PolicyPenaltyValue / 100);
        SET NEW.RefundAmount  = BookingTotal - NEW.PenaltyAmount;
    ELSEIF PolicyPenaltyType = 'FixedAmount' THEN
        SET NEW.PenaltyAmount = LEAST(PolicyPenaltyValue, BookingTotal);
        SET NEW.RefundAmount  = BookingTotal - NEW.PenaltyAmount;
    ELSEIF PolicyPenaltyType IS NULL THEN
        -- No applicable policy: full refund
        SET NEW.PenaltyAmount = 0;
        SET NEW.RefundAmount  = BookingTotal;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingCancellation_AI_UpdateBookingStatus
   Purpose: After a cancellation record is inserted, mark the
            associated booking as 'Cancelled'.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCancellation_AI_UpdateBookingStatus
AFTER INSERT ON BookingCancellation
FOR EACH ROW
BEGIN
    UPDATE Booking
    SET BookingStatus = 'Cancelled'
    WHERE BookingID = NEW.BookingID;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingCancellation_BU_ApplyPenalty
   Purpose: Re-apply penalty calculation when a cancellation record
            is updated (e.g., correction of cancellation date/time).
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingCancellation_BU_ApplyPenalty
BEFORE UPDATE ON BookingCancellation
FOR EACH ROW
BEGIN
    DECLARE DepartureTime       DATETIME;
    DECLARE BookingTotal        DECIMAL(12,2);
    DECLARE HoursUntilDeparture INT;
    DECLARE PolicyPenaltyType   VARCHAR(30);
    DECLARE PolicyPenaltyValue  DECIMAL(10,2);

    SELECT v.DepartureDateTime, b.TotalAmount, cp.PenaltyType, cp.PenaltyValue
    INTO DepartureTime, BookingTotal, PolicyPenaltyType, PolicyPenaltyValue
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    INNER JOIN CruiseShip s   ON v.ShipID = s.ShipID
    LEFT JOIN CancellationPolicy cp
        ON s.OperatorID = cp.OperatorID
       AND cp.HoursBeforeDeparture >= TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, v.DepartureDateTime)
    WHERE b.BookingID = NEW.BookingID
    ORDER BY cp.HoursBeforeDeparture ASC
    LIMIT 1;

    SET HoursUntilDeparture = TIMESTAMPDIFF(HOUR, NEW.CancellationDateTime, DepartureTime);

    IF HoursUntilDeparture <= 48 AND PolicyPenaltyType = 'FullForfeit' THEN
        SET NEW.PenaltyAmount = BookingTotal;
        SET NEW.RefundAmount  = 0;
    ELSEIF PolicyPenaltyType = 'Percentage' THEN
        SET NEW.PenaltyAmount = BookingTotal * (PolicyPenaltyValue / 100);
        SET NEW.RefundAmount  = BookingTotal - NEW.PenaltyAmount;
    ELSEIF PolicyPenaltyType = 'FixedAmount' THEN
        SET NEW.PenaltyAmount = LEAST(PolicyPenaltyValue, BookingTotal);
        SET NEW.RefundAmount  = BookingTotal - NEW.PenaltyAmount;
    ELSEIF PolicyPenaltyType IS NULL THEN
        SET NEW.PenaltyAmount = 0;
        SET NEW.RefundAmount  = BookingTotal;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_RescheduleRequest_BI_ValidateRules
   Purpose: Validate reschedule request on insert.
   Business rules:
     1. Cannot reschedule after the original voyage has departed.
     2. New voyage must begin within one year of the original booking date.
     3. Rescheduling < 48 hours before departure incurs a fee equal
        to the full booking total.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_RescheduleRequest_BI_ValidateRules
BEFORE INSERT ON RescheduleRequest
FOR EACH ROW
BEGIN
    DECLARE OriginalBookingDate   DATETIME;
    DECLARE OriginalDepartureTime DATETIME;
    DECLARE NewDepartureTime      DATETIME;
    DECLARE OriginalTotal         DECIMAL(12,2);

    SELECT b.BookingDate, v.DepartureDateTime, b.TotalAmount
    INTO OriginalBookingDate, OriginalDepartureTime, OriginalTotal
    FROM Booking b
    INNER JOIN CruiseVoyage v ON b.VoyageID = v.VoyageID
    WHERE b.BookingID = NEW.OriginalBookingID;

    SELECT DepartureDateTime
    INTO NewDepartureTime
    FROM CruiseVoyage
    WHERE VoyageID = NEW.NewVoyageID;

    -- Business rule: voyage must not have already departed
    IF NEW.RequestDateTime >= OriginalDepartureTime THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A departed cruise ticket cannot be rescheduled.';
    END IF;

    -- Business rule: new voyage must start within one year of the original booking
    IF NewDepartureTime > DATE_ADD(OriginalBookingDate, INTERVAL 1 YEAR) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'The new voyage must start within one year from the original booking date.';
    END IF;

    -- Business rule: < 48 hours before departure → full booking total as fee
    IF TIMESTAMPDIFF(HOUR, NEW.RequestDateTime, OriginalDepartureTime) <= 48 THEN
        SET NEW.RescheduleFee = OriginalTotal;
    END IF;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_RescheduleRequest_BU_ValidateRules
   Purpose: Re-apply the same reschedule validation rules on update.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_RescheduleRequest_BU_ValidateRules
BEFORE UPDATE ON RescheduleRequest
FOR EACH ROW
BEGIN
    DECLARE OriginalBookingDate   DATETIME;
    DECLARE OriginalDepartureTime DATETIME;
    DECLARE NewDepartureTime      DATETIME;
    DECLARE OriginalTotal         DECIMAL(12,2);

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

/* ---------------------------------------------------------------
   Trigger: TR_BookingPassenger_AI_UpdateBookingTotal
   Purpose: After a passenger fare is inserted into BookingPassenger,
            recalculate and update Booking.TotalAmount as the sum of
            all FinalFare values for that booking.
   This ensures Booking.TotalAmount is always accurate when the
   cancellation and reschedule triggers read it.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_AI_UpdateBookingTotal
AFTER INSERT ON BookingPassenger
FOR EACH ROW
BEGIN
    UPDATE Booking
    SET TotalAmount = (
        SELECT COALESCE(SUM(FinalFare), 0)
        FROM BookingPassenger
        WHERE BookingID = NEW.BookingID
    )
    WHERE BookingID = NEW.BookingID;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingPassenger_AU_UpdateBookingTotal
   Purpose: After a passenger fare is updated in BookingPassenger,
            recalculate Booking.TotalAmount to keep it in sync.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_AU_UpdateBookingTotal
AFTER UPDATE ON BookingPassenger
FOR EACH ROW
BEGIN
    UPDATE Booking
    SET TotalAmount = (
        SELECT COALESCE(SUM(FinalFare), 0)
        FROM BookingPassenger
        WHERE BookingID = NEW.BookingID
    )
    WHERE BookingID = NEW.BookingID;
END$$

/* ---------------------------------------------------------------
   Trigger: TR_BookingPassenger_AD_UpdateBookingTotal
   Purpose: After a passenger is deleted from BookingPassenger,
            recalculate Booking.TotalAmount to keep it in sync.
   --------------------------------------------------------------- */
CREATE TRIGGER TR_BookingPassenger_AD_UpdateBookingTotal
AFTER DELETE ON BookingPassenger
FOR EACH ROW
BEGIN
    UPDATE Booking
    SET TotalAmount = (
        SELECT COALESCE(SUM(FinalFare), 0)
        FROM BookingPassenger
        WHERE BookingID = OLD.BookingID
    )
    WHERE BookingID = OLD.BookingID;
END$$

DELIMITER ;

/* ============================================================
   SECTION 9: SEED DATA
   ============================================================ */

-- Cabin categories (the four permitted types in GLCL)
INSERT INTO CabinCategory (CategoryName, CategoryDescription)
VALUES
('Interior',   'Inside cabin without sea view.'),
('Ocean View', 'Cabin with sea-facing window.'),
('Balcony',    'Cabin with private balcony.'),
('Suite',      'Premium suite with luxury facilities.');

-- Age categories (AgeCategoryID: 1=Infant, 2=Child, 3=Teen, 4=Adult, 5=Senior)
INSERT INTO AgeCategory (CategoryName, MinAge, MaxAge)
VALUES
('Infant', 0,  1),
('Child',  2,  12),
('Teen',   13, 17),
('Adult',  18, 59),
('Senior', 60, NULL);  -- no upper age bound for seniors

-- Dining options
INSERT INTO DiningOption (DiningName)
VALUES
('Fixed-time dining'),
('Flexible dining'),
('Specialty restaurant');

-- Meal package types
INSERT INTO VoyageMealPackageType (PackageName)
VALUES
('Standard boarding meal'),
('Multi-day all-inclusive dining package');

/*
 * Meal package rules:
 *   Rule 1 (MealPackageTypeID=1): 1-day voyages → standard boarding meal
 *   Rule 2 (MealPackageTypeID=2): 2+ day voyages → all-inclusive package
 */
INSERT INTO VoyageMealPackageRule (MealPackageTypeID, MinVoyageLengthDays, MaxVoyageLengthDays)
VALUES
(1, 1, 1),    -- standard boarding meal: exactly 1 day
(2, 2, NULL); -- all-inclusive package:  2 days and above

-- Special services available across all operators
INSERT INTO SpecialService (ServiceName, ServiceType, AgeRestrictionMin, AgeRestrictionMax, Fee)
VALUES
('Onboard Childcare Service',           'Childcare',        2,    12,   35.00),
('Teen Exclusive Club',                 'Teen Club',         13,   17,   0.00),
('Wheelchair Accessible Cabin Request', 'Accessibility',     NULL, NULL, 0.00),
('Mobility Assistance Service',         'Mobility',          NULL, NULL, 0.00),
('Chaperoned Youth Supervision',        'Chaperoned Youth',  15,   17,   50.00);

-- Cruise operators (OperatorID: 1=GLCL, 2=Royal Oceanic)
INSERT INTO CruiseOperator (OperatorName, HeadquartersCountry, ContactEmail, AllowsChaperonedYouth)
VALUES
('Global Luxury Cruise Lines', 'Malaysia',        'reservations@glcl.example',      TRUE),
('Royal Oceanic Voyages',      'United Kingdom',  'support@royaloceanic.example',    FALSE);

-- Ships (ShipID: 1=GLCL Majesty, 2=GLCL Pearl, 3=Oceanic Star)
INSERT INTO CruiseShip (OperatorID, ShipName, TotalDecks, PassengerCapacity)
VALUES
(1, 'GLCL Majesty', 15, 3200),
(1, 'GLCL Pearl',   12, 2200),
(2, 'Oceanic Star', 14, 2800);

-- Routes (RouteID: 1=One-way, 2=Round-trip, 3=Multi-destination)
INSERT INTO CruiseRoute (RouteName, RouteType)
VALUES
('Kuala Lumpur to Singapore Repositioning',   'One-way'),
('Penang Island Luxury Loop',                 'Round-trip'),
('Langkawi, Phuket and Krabi Island Hopper', 'Multi-destination');

-- Ports (PortID: 1=Port Klang, 2=Singapore, 3=Penang, 4=Langkawi, 5=Phuket, 6=Krabi)
INSERT INTO Port (PortName, Country)
VALUES
('Port Klang',              'Malaysia'),
('Singapore Cruise Centre', 'Singapore'),
('Penang Port',             'Malaysia'),
('Langkawi Cruise Terminal','Malaysia'),
('Phuket Deep Sea Port',    'Thailand'),
('Krabi Cruise Port',       'Thailand');

/*
 * RoutePort entries:
 *   Route 1 (One-way):         Port Klang(1) → Singapore(2)
 *   Route 2 (Round-trip):      Penang(3) → Langkawi(4) → Penang(3)
 *   Route 3 (Multi-dest):      Port Klang(1) → Langkawi(4) → Phuket(5) → Krabi(6) → Port Klang(1)
 *
 *   RoutePortID sequence (auto-assigned):
 *     1=Route1/PortKlang, 2=Route1/Singapore
 *     3=Route2/Penang(dep), 4=Route2/Langkawi, 5=Route2/Penang(arr)
 *     6=Route3/PortKlang(dep), 7=Route3/Langkawi, 8=Route3/Phuket,
 *     9=Route3/Krabi, 10=Route3/PortKlang(arr)
 */
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

/*
 * Cabins per ship:
 *   GLCL Majesty (ShipID=1): CabinID 1–5
 *   GLCL Pearl   (ShipID=2): CabinID 6–9
 *   Oceanic Star (ShipID=3): CabinID 10–13
 *
 * CabinCategoryID: 1=Interior, 2=Ocean View, 3=Balcony, 4=Suite
 */
INSERT INTO Cabin (ShipID, CabinCategoryID, CabinNumber, DeckNumber, MaxOccupancy, IsWheelchairAccessible)
VALUES
-- GLCL Majesty
(1, 1, 'I-801',  8,  4, FALSE),  -- CabinID 1
(1, 2, 'O-802',  8,  4, FALSE),  -- CabinID 2
(1, 2, 'O-803',  8,  4, FALSE),  -- CabinID 3
(1, 3, 'B-901',  9,  5, TRUE),   -- CabinID 4
(1, 4, 'S-1001', 10, 5, TRUE),   -- CabinID 5
-- GLCL Pearl
(2, 1, 'I-501',  5,  4, FALSE),  -- CabinID 6
(2, 2, 'O-502',  5,  4, FALSE),  -- CabinID 7
(2, 3, 'B-601',  6,  5, TRUE),   -- CabinID 8
(2, 4, 'S-701',  7,  5, TRUE),   -- CabinID 9
-- Oceanic Star
(3, 1, 'I-601',  6,  4, FALSE),  -- CabinID 10
(3, 2, 'O-602',  6,  4, FALSE),  -- CabinID 11
(3, 3, 'B-701',  7,  5, TRUE),   -- CabinID 12
(3, 4, 'S-801',  8,  5, TRUE);   -- CabinID 13

/*
 * CabinAdjacency: O-802 (CabinID=2) and O-803 (CabinID=3) on GLCL Majesty
 * are physically adjacent on Deck 8. Inserted bidirectionally so the
 * teen-guardian trigger query works regardless of lookup direction.
 */
INSERT INTO CabinAdjacency (CabinID, AdjacentCabinID, AdjacencyType)
VALUES
(2, 3, 'Adjacent'),
(3, 2, 'Adjacent');

-- Dining options available per ship
INSERT INTO ShipDiningOption (ShipID, DiningOptionID)
VALUES
(1, 1),  -- GLCL Majesty: Fixed-time
(1, 2),  -- GLCL Majesty: Flexible
(1, 3),  -- GLCL Majesty: Specialty
(2, 1),  -- GLCL Pearl: Fixed-time
(2, 3),  -- GLCL Pearl: Specialty
(3, 2),  -- Oceanic Star: Flexible
(3, 3);  -- Oceanic Star: Specialty

-- Specialty cuisine types (SpecialtyDiningTypeID: 1=Vegan, 2=Gluten-Free,
--   3=Halal, 4=Kosher, 5=Low-Sodium, 6=Seafood Grill)
INSERT INTO SpecialtyDiningType (TypeName, Description)
VALUES
('Vegan',        'Fully plant-based menu with no animal products.'),
('Gluten-Free',  'Dishes prepared without gluten-containing ingredients.'),
('Halal',        'Meals prepared in accordance with Islamic dietary laws.'),
('Kosher',       'Meals prepared in accordance with Jewish dietary laws.'),
('Low-Sodium',   'Heart-healthy dishes with reduced sodium content.'),
('Seafood Grill','Premium fresh seafood grilled to order.');

-- Specialty dining types offered per ship
INSERT INTO ShipSpecialtyDining (ShipID, SpecialtyDiningTypeID)
VALUES
(1, 1),  -- GLCL Majesty: Vegan
(1, 2),  -- GLCL Majesty: Gluten-Free
(1, 3),  -- GLCL Majesty: Halal
(1, 6),  -- GLCL Majesty: Seafood Grill
(2, 1),  -- GLCL Pearl: Vegan
(2, 3),  -- GLCL Pearl: Halal
(3, 2),  -- Oceanic Star: Gluten-Free
(3, 5),  -- Oceanic Star: Low-Sodium
(3, 6);  -- Oceanic Star: Seafood Grill

/*
 * Voyages (VoyageID: 1=KL→Singapore 2-day, 2=Island Hopper 8-day)
 * Both use GLCL Majesty (ShipID=1).
 * VoyageLengthDays is computed: Voyage 1 = 2 days, Voyage 2 = 8 days.
 * Both → MealPackageRuleID=2 (all-inclusive, 2+ days).
 */
INSERT INTO CruiseVoyage (ShipID, RouteID, DepartureDateTime, ArrivalDateTime, BaggageWeightLimitKG, VoyageStatus)
VALUES
(1, 1, '2026-08-01 18:00:00', '2026-08-03 08:00:00', 25.00, 'Scheduled'),  -- VoyageID=1
(1, 3, '2026-09-10 17:00:00', '2026-09-18 09:00:00', 30.00, 'Scheduled');  -- VoyageID=2

/*
 * FareRule seed data:
 *   AgeCategoryID: 2=Child, 3=Teen, 4=Adult, 5=Senior
 *   CabinCategoryID: 1=Interior, 2=Ocean View, 3=Balcony, 4=Suite
 *   Infant fares are NOT included here — they are computed by trigger.
 */
INSERT INTO FareRule (VoyageID, CabinCategoryID, AgeCategoryID, BaseFare, EffectiveFrom, EffectiveTo)
VALUES
-- Voyage 1 — Interior
(1, 1, 2,  600.00, '2026-01-01', NULL),
(1, 1, 3,  750.00, '2026-01-01', NULL),
(1, 1, 4, 1000.00, '2026-01-01', NULL),
(1, 1, 5,  850.00, '2026-01-01', NULL),
-- Voyage 1 — Ocean View
(1, 2, 2,  850.00, '2026-01-01', NULL),
(1, 2, 3, 1000.00, '2026-01-01', NULL),
(1, 2, 4, 1350.00, '2026-01-01', NULL),
(1, 2, 5, 1150.00, '2026-01-01', NULL),
-- Voyage 1 — Balcony
(1, 3, 2, 1100.00, '2026-01-01', NULL),
(1, 3, 3, 1300.00, '2026-01-01', NULL),
(1, 3, 4, 1750.00, '2026-01-01', NULL),
(1, 3, 5, 1500.00, '2026-01-01', NULL),
-- Voyage 1 — Suite
(1, 4, 2, 1800.00, '2026-01-01', NULL),
(1, 4, 3, 2100.00, '2026-01-01', NULL),
(1, 4, 4, 2800.00, '2026-01-01', NULL),
(1, 4, 5, 2500.00, '2026-01-01', NULL),
-- Voyage 2 — Interior
(2, 1, 2, 1200.00, '2026-01-01', NULL),
(2, 1, 3, 1500.00, '2026-01-01', NULL),
(2, 1, 4, 2000.00, '2026-01-01', NULL),
(2, 1, 5, 1750.00, '2026-01-01', NULL),
-- Voyage 2 — Ocean View
(2, 2, 2, 1600.00, '2026-01-01', NULL),
(2, 2, 3, 2000.00, '2026-01-01', NULL),
(2, 2, 4, 2700.00, '2026-01-01', NULL),
(2, 2, 5, 2400.00, '2026-01-01', NULL),
-- Voyage 2 — Balcony
(2, 3, 2, 1800.00, '2026-01-01', NULL),
(2, 3, 3, 2300.00, '2026-01-01', NULL),
(2, 3, 4, 3200.00, '2026-01-01', NULL),
(2, 3, 5, 2800.00, '2026-01-01', NULL),
-- Voyage 2 — Suite
(2, 4, 2, 3000.00, '2026-01-01', NULL),
(2, 4, 3, 3800.00, '2026-01-01', NULL),
(2, 4, 4, 5200.00, '2026-01-01', NULL),
(2, 4, 5, 4600.00, '2026-01-01', NULL);

-- Both voyages are 2+ days → all-inclusive package (MealPackageRuleID=2)
INSERT INTO VoyageMealPackage (VoyageID, MealPackageRuleID)
VALUES
(1, 2),
(2, 2);

-- Baggage weight limits per operator
INSERT INTO BaggageRule (OperatorID, MaxWeightKG, EffectiveFrom, EffectiveTo)
VALUES
(1, 30.00, '2026-01-01', NULL),  -- GLCL: 30 kg
(2, 25.00, '2026-01-01', NULL);  -- Royal Oceanic: 25 kg

/*
 * Excursions by port:
 *   ExcursionID 1–2: Singapore (PortID=2)
 *   ExcursionID 3–4: Langkawi  (PortID=4)
 *   ExcursionID 5–6: Phuket    (PortID=5)
 *   ExcursionID 7–8: Krabi     (PortID=6)
 */
INSERT INTO Excursion (PortID, ExcursionName, Description, DurationHours, Price)
VALUES
(2, 'Gardens by the Bay Night Tour',   'Guided evening tour of the iconic garden domes.',                  3.00,  85.00),
(2, 'Sentosa Island Beach Day',        'Full-day beach and resort experience.',                            8.00, 120.00),
(4, 'Mangrove Kayak Adventure',        'Guided kayaking through Langkawi mangrove forests.',               4.00,  75.00),
(4, 'Eagle Square & Cable Car Tour',   'Visit Eagle Square and ride the Langkawi cable car.',              5.00,  95.00),
(5, 'Phi Phi Island Snorkel Trip',     'Speedboat trip to Phi Phi Island with snorkelling.',               7.00, 110.00),
(5, 'Old Phuket Town Heritage Walk',   'Walking tour through the historic Sino-Portuguese district.',      3.00,  50.00),
(6, 'Railay Beach Longtail Boat Trip', 'Longtail boat excursion to the secluded Railay Beach.',            5.00,  90.00),
(6, 'Tiger Cave Temple Hike',          'Guided hike up 1,237 steps to the Tiger Cave Temple summit.',     4.00,  60.00);

/*
 * VoyageExcursion: excursions available on Voyage 2 (Island Hopper).
 * RoutePort references for Voyage 2 (Route 3):
 *   RoutePortID 7 = Langkawi stop  (Route 3, StopSequence 2)
 *   RoutePortID 8 = Phuket stop    (Route 3, StopSequence 3)
 *   RoutePortID 9 = Krabi stop     (Route 3, StopSequence 4)
 * Note: Singapore excursions (ExcursionID 1–2) are not on this voyage.
 */
INSERT INTO VoyageExcursion (VoyageID, RoutePortID, ExcursionID, AvailableSlots)
VALUES
(2, 7, 3, 30),   -- Langkawi: Mangrove Kayak
(2, 7, 4, 40),   -- Langkawi: Eagle Square
(2, 8, 5, 25),   -- Phuket:   Phi Phi Snorkel
(2, 8, 6, 50),   -- Phuket:   Old Town Walk
(2, 9, 7, 35),   -- Krabi:    Railay Beach
(2, 9, 8, 45);   -- Krabi:    Tiger Cave Hike

-- Cancellation policies: full forfeit within 48 hours for both operators
INSERT INTO CancellationPolicy (OperatorID, HoursBeforeDeparture, PenaltyType, PenaltyValue)
VALUES
(1, 48, 'FullForfeit', 100.00),
(2, 48, 'FullForfeit', 100.00);

/* ============================================================
   SECTION 10: REPORTING VIEWS
   ============================================================ */

/*
 * vw_BookingPassengerDetails
 * Flat view combining booking, voyage, cabin, passenger, and fare
 * information. Intended for reservation summary reports.
 */
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
    cc.CategoryName                                                  AS CabinCategory,
    p.PassengerID,
    p.FullName,
    p.PassportNo,
    fn_CalculateAge(p.DateOfBirth, DATE(v.DepartureDateTime))        AS AgeAtDeparture,
    ac.CategoryName                                                  AS AgeCategory,
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
INNER JOIN AgeCategory   ac  ON bp.AgeCategoryID  = ac.AgeCategoryID;

/*
 * vw_VoyageCabinAvailability
 * Shows every cabin on every voyage with a computed availability status.
 * 'Booked'    = cabin has a Pending or Confirmed booking on this voyage.
 * 'Available' = cabin is free for this voyage.
 */
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
FROM CruiseVoyage   v
INNER JOIN CruiseShip    s  ON v.ShipID          = s.ShipID
INNER JOIN CruiseRoute   r  ON v.RouteID         = r.RouteID
INNER JOIN Cabin         c  ON s.ShipID          = c.ShipID
INNER JOIN CabinCategory cc ON c.CabinCategoryID = cc.CabinCategoryID;

SELECT 'GLCL_DB MySQL database created successfully.' AS Message;